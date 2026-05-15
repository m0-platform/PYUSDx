// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { EnumerableSet } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { SafeERC20 } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { UIntMath } from "../../../lib/evm-m-extensions/lib/common/src/libs/UIntMath.sol";

import { IERC20Metadata } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "../../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { YieldToOne } from "./YieldToOne.sol";

import { IMultiMint } from "./interfaces/IMultiMint.sol";
import { ISwapFacility } from "../../swap/interfaces/ISwapFacility.sol";

abstract contract MultiMintStorageLayout {
    struct Asset {
        uint256 cap;
        uint240 balance;
        uint8 decimals;
    }

    /// @custom:storage-location erc7201:PYUSDX.storage.MultiMint
    struct MultiMintStorage {
        mapping(address => Asset) assets;
        uint256 totalAssets;
        EnumerableSet.AddressSet replaceAssetWhitelist;
    }

    // keccak256(abi.encode(uint256(keccak256("PYUSDX.storage.MultiMint")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _MULTI_MINT_STORAGE_LOCATION =
        0x57e19e611dcbdde2876919e2fe591d15cb50f046f296d11a2b28e0b3b8b3f900;

    function _getMultiMintStorage() internal pure returns (MultiMintStorage storage $) {
        bytes32 location = _MULTI_MINT_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }
}

/// @title  MultiMint
/// @notice Upgradeable ERC20 token for wrapping PYUSDX or approved alternative stablecoins
///         into a token with yield claimable by a single recipient.
/// @dev    Extends YieldToOne with a multi-collateral backing model. Users
///         can mint by depositing PYUSDX. Unwrapping always returns PYUSDX, other
///         stablecoins can only be extracted via `replaceAsset`.
/// @author M0 Labs
contract MultiMint is IMultiMint, MultiMintStorageLayout, YieldToOne {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20Metadata;

    /* ============ Variables ============ */

    /// @inheritdoc IMultiMint
    bytes32 public constant ASSET_CAP_MANAGER_ROLE = keccak256("ASSET_CAP_MANAGER_ROLE");

    /// @inheritdoc IMultiMint
    uint8 public constant PYUSDX_DECIMALS = 6;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param pyusdx_       The address of the PYUSDX token.
    /// @param swapFacility_ The address of the swap facility.
    constructor(address pyusdx_, address swapFacility_) YieldToOne(pyusdx_, swapFacility_) {}

    /* ============ Initializer ============ */

    /// @notice Initializes the MultiMint extension token.
    /// @param  name                  The name of the token.
    /// @param  symbol                The symbol of the token.
    /// @param  yieldRecipient_       The address of the yield recipient.
    /// @param  admin                 The address of the admin.
    /// @param  assetCapManager       The address of the asset cap manager.
    /// @param  freezeManager         The address of the freeze manager.
    /// @param  pauser                The address of the pauser.
    /// @param  yieldRecipientManager The address of the yield recipient manager.
    /// @param  versionManager        The address of the version manager.
    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address assetCapManager,
        address freezeManager,
        address pauser,
        address yieldRecipientManager,
        address versionManager
    ) public virtual initializer {
        __MultiMint_init(
            name,
            symbol,
            yieldRecipient_,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            yieldRecipientManager,
            versionManager
        );
    }

    /// @dev   Internal initializer for MultiMint. Grants ASSET_CAP_MANAGER_ROLE
    ///        and delegates to `__YieldToOne_init`.
    /// @param name                  The name of the token.
    /// @param symbol                The symbol of the token.
    /// @param yieldRecipient_       The address of the yield recipient.
    /// @param admin                 The address of the admin.
    /// @param assetCapManager       The address of the asset cap manager.
    /// @param freezeManager         The address of the freeze manager.
    /// @param pauser                The address of the pauser.
    /// @param yieldRecipientManager The address of the yield recipient manager.
    /// @param versionManager        The address of the version manager.
    function __MultiMint_init(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address assetCapManager,
        address freezeManager,
        address pauser,
        address yieldRecipientManager,
        address versionManager
    ) internal onlyInitializing {
        if (assetCapManager == address(0)) revert ZeroAssetCapManager();

        __YieldToOne_init(
            name,
            symbol,
            yieldRecipient_,
            admin,
            freezeManager,
            pauser,
            yieldRecipientManager,
            versionManager
        );

        _grantRole(ASSET_CAP_MANAGER_ROLE, assetCapManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IMultiMint
    function wrap(address asset, address recipient, uint256 amount) external onlySwapFacility {
        _wrapAsset(asset, ISwapFacility(msg.sender).msgSender(), recipient, amount);
    }

    /// @inheritdoc IMultiMint
    function replaceAsset(address asset, address recipient, uint256 amount) external onlySwapFacility {
        _replaceAsset(asset, recipient, amount);
    }

    /// @inheritdoc IMultiMint
    function setAssetCap(address asset, uint256 cap) external onlyRole(ASSET_CAP_MANAGER_ROLE) {
        _revertIfInvalidAsset(asset);

        MultiMintStorage storage $ = _getMultiMintStorage();

        if ($.assets[asset].cap == cap) return;

        if ($.assets[asset].decimals == 0) $.assets[asset].decimals = IERC20Metadata(asset).decimals();

        $.assets[asset].cap = cap;

        emit AssetCapSet(asset, cap);
    }

    /// @inheritdoc IMultiMint
    function setReplaceAssetWhitelistCaller(address caller, bool allowed) external onlyRole(ASSET_CAP_MANAGER_ROLE) {
        _setReplaceAssetWhitelistCaller(caller, allowed);
    }

    /// @inheritdoc IMultiMint
    function setReplaceAssetWhitelistCaller(
        address[] calldata callers,
        bool[] calldata allowed
    ) external onlyRole(ASSET_CAP_MANAGER_ROLE) {
        if (callers.length != allowed.length) revert ArrayLengthMismatch();

        for (uint256 i; i < callers.length; ++i) {
            _setReplaceAssetWhitelistCaller(callers[i], allowed[i]);
        }
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IMultiMint
    function assetBalanceOf(address asset) public view returns (uint256) {
        return _getMultiMintStorage().assets[asset].balance;
    }

    /// @inheritdoc IMultiMint
    function assetCap(address asset) public view returns (uint256) {
        return _getMultiMintStorage().assets[asset].cap;
    }

    /// @inheritdoc IMultiMint
    function assetDecimals(address asset) public view returns (uint8) {
        return _getMultiMintStorage().assets[asset].decimals;
    }

    /// @inheritdoc IMultiMint
    function totalAssets() public view returns (uint256) {
        return _getMultiMintStorage().totalAssets;
    }

    /// @inheritdoc IMultiMint
    function isAllowedAsset(address asset) public view returns (bool) {
        return assetCap(asset) != 0;
    }

    /// @inheritdoc IMultiMint
    function isAllowedToWrap(address asset, uint256 amount) public view returns (bool) {
        if (amount == 0) return false;

        uint256 extensionAmount = _fromAssetToExtensionAmount(asset, amount);
        if (extensionAmount == 0) return false;

        uint256 effectiveAmount = _fromExtensionToAssetAmount(asset, extensionAmount);
        return assetCap(asset) >= (assetBalanceOf(asset) + effectiveAmount);
    }

    /// @inheritdoc IMultiMint
    function isAllowedToUnwrap(uint256 amount) external view returns (bool) {
        return amount != 0 && _pyusdxBacking() >= amount;
    }

    /// @inheritdoc IMultiMint
    function isReplaceAssetWhitelistEnabled() external view returns (bool) {
        return _getMultiMintStorage().replaceAssetWhitelist.length() != 0;
    }

    /// @inheritdoc IMultiMint
    function getReplaceAssetWhitelist() external view returns (address[] memory) {
        return _getMultiMintStorage().replaceAssetWhitelist.values();
    }

    /// @inheritdoc IMultiMint
    function isAllowedToReplaceAsset(address caller, address asset, uint256 amount) external view returns (bool) {
        if (amount == 0 || !isAllowedAsset(asset) || !_isCallerAllowedToReplaceAsset(caller)) return false;

        uint256 assetAmount = _fromExtensionToAssetAmount(asset, amount);
        return assetAmount != 0 && assetBalanceOf(asset) >= assetAmount;
    }

    /* ============ Hooks ============ */

    /// @dev   Hook called before wrapping `asset` into extension's tokens.
    /// @param asset     Address of the asset being deposited.
    /// @param account   The account initiating the wrap.
    /// @param recipient The address that will receive extension tokens.
    /// @param amount    The amount of `asset` being deposited.
    function _beforeWrap(address asset, address account, address recipient, uint256 amount) internal view virtual {
        if (!isAllowedToWrap(asset, amount)) revert AssetCapReached(asset);

        super._beforeWrap(account, recipient, amount);
    }

    /// @dev   Hook called before unwrapping extension tokens for PYUSDX.
    ///        Adds PYUSDX backing check before the inherited pause+freeze
    ///        checks.
    /// @param account The account from which tokens are burned.
    /// @param amount  The amount of extension tokens to unwrap.
    function _beforeUnwrap(address account, uint256 amount) internal view virtual override {
        _revertIfInsufficientPYUSDXBacking(amount);

        super._beforeUnwrap(account, amount);
    }

    /* ============ Internal Interactive Functions ============ */

    /// @dev   Mints extension tokens by pulling `asset` from `msg.sender`.
    ///        Reverts on fee-on-transfer tokens or if the asset cap is reached.
    ///        For assets with more decimals than the extension, only the
    ///        non-dust portion is pulled; any dust is left with `msg.sender`
    ///        so that `assetBalance == totalAssets * factor` always holds.
    /// @param asset     Address of the asset to deposit.
    /// @param account   The original caller (resolved via swap facility).
    /// @param recipient Address that will receive the extension tokens.
    /// @param amount    Amount of `asset` tokens to deposit (in asset decimals).
    function _wrapAsset(address asset, address account, address recipient, uint256 amount) internal virtual {
        _revertIfInvalidAsset(asset);
        _revertIfZeroAccount(recipient);
        _revertIfZeroAmount(amount);

        // Convert to extension decimals and revert if it truncates to zero.
        uint256 extensionAmount = _fromAssetToExtensionAmount(asset, amount);
        _revertIfZeroAmount(extensionAmount);

        // Round amount down to the largest non-dust multiple of factor. For
        // assets with decimals <= 6 this equals `amount`; for higher decimals
        // it discards the truncating-division dust so the asset/extension
        // accounting stays exact across repeated wraps.
        uint256 effectiveAmount = _fromExtensionToAssetAmount(asset, extensionAmount);

        // Checks asset cap + pause + freeze via 4-arg hook.
        _beforeWrap(asset, account, recipient, effectiveAmount);

        uint256 assetBalanceBefore = IERC20Metadata(asset).balanceOf(address(this));

        // Pull only the non-dust portion from caller.
        IERC20Metadata(asset).safeTransferFrom(msg.sender, address(this), effectiveAmount);

        // Fee-on-transfer detection.
        uint256 amountReceived = IERC20Metadata(asset).balanceOf(address(this)) - assetBalanceBefore;

        if (amountReceived < effectiveAmount) {
            revert InsufficientAssetReceived(asset, effectiveAmount, amountReceived);
        }

        MultiMintStorage storage $ = _getMultiMintStorage();

        // Update non-PYUSDX asset backing.
        $.assets[asset].balance += UIntMath.safe240(effectiveAmount);
        $.totalAssets += extensionAmount;

        _mint(recipient, extensionAmount);

        emit AssetWrapped(asset, effectiveAmount, recipient, extensionAmount);
    }

    /// @dev   Pulls PYUSDX from `msg.sender` and sends `asset` from reserves to `recipient`.
    /// @param asset     Address of the asset to receive from reserves.
    /// @param recipient Address that will receive the `asset` tokens.
    /// @param amount    Amount of PYUSDX to deposit (in PYUSDX decimals).
    function _replaceAsset(address asset, address recipient, uint256 amount) internal virtual {
        _requireNotPaused();

        _revertIfInvalidAsset(asset);
        if (!isAllowedAsset(asset)) revert AssetNotAllowed(asset);

        address caller = ISwapFacility(msg.sender).msgSender();
        if (!_isCallerAllowedToReplaceAsset(caller)) revert CallerNotAllowed(caller);

        _revertIfZeroAccount(recipient);
        _revertIfZeroAmount(amount);

        // Convert PYUSDX amount to asset decimals and revert if truncates to zero.
        uint256 assetAmount = _fromExtensionToAssetAmount(asset, amount);

        _revertIfZeroAmount(assetAmount);
        _revertIfInsufficientAssetBacking(asset, assetAmount);

        MultiMintStorage storage $ = _getMultiMintStorage();

        // Update non-PYUSDX asset backing.
        $.assets[asset].balance -= UIntMath.safe240(assetAmount);
        $.totalAssets -= amount;

        // Pull PYUSDX from caller.
        IERC20(pyusdx).transferFrom(msg.sender, address(this), amount);

        // Send alt-asset to recipient.
        IERC20Metadata(asset).safeTransfer(recipient, assetAmount);

        emit AssetReplaced(asset, assetAmount, recipient, amount);
    }

    /// @dev   Adds or removes `caller` from the replaceAsset whitelist.
    ///        Emits `ReplaceAssetWhitelistCallerSet` only when state actually changes.
    /// @param caller  The caller to add or remove.
    /// @param allowed True to add, false to remove.
    function _setReplaceAssetWhitelistCaller(address caller, bool allowed) internal {
        _revertIfZeroAccount(caller);

        EnumerableSet.AddressSet storage whitelist = _getMultiMintStorage().replaceAssetWhitelist;
        bool changed = allowed ? whitelist.add(caller) : whitelist.remove(caller);

        if (!changed) return;

        emit ReplaceAssetWhitelistCallerSet(caller, allowed);
    }

    /* ============ Internal View Functions ============ */

    /// @dev Returns the excess PYUSDX balance that is not backing extension tokens.
    function _excess() internal view virtual override returns (uint256) {
        uint256 pyusdxBalance = _pyusdxBalanceOf(address(this));
        uint256 pyusdxBacking = _pyusdxBacking();

        unchecked {
            return pyusdxBalance > pyusdxBacking ? pyusdxBalance - pyusdxBacking : 0;
        }
    }

    /// @dev Returns the current supply of PYUSDX backing the extension token excluding yield and donation amounts.
    function _pyusdxBacking() internal view returns (uint256) {
        uint256 totalAssets_ = totalAssets();
        uint256 totalSupply_ = totalSupply();

        unchecked {
            return totalSupply_ > totalAssets_ ? totalSupply_ - totalAssets_ : 0;
        }
    }

    /// @dev    Returns true if `caller` passes the whitelist gate.
    /// @param  caller The address to check.
    /// @return True if the whitelist is disabled or `caller` is whitelisted.
    function _isCallerAllowedToReplaceAsset(address caller) internal view returns (bool) {
        EnumerableSet.AddressSet storage whitelist = _getMultiMintStorage().replaceAssetWhitelist;

        return whitelist.length() == 0 || whitelist.contains(caller);
    }

    /// @dev   Reverts if `asset` is address(0) or PYUSDX.
    /// @param asset Address of the asset to validate.
    function _revertIfInvalidAsset(address asset) internal view {
        if (asset == address(0) || asset == pyusdx) revert InvalidAsset(asset);
    }

    /// @dev   Reverts if PYUSDX backing is insufficient for `amount`.
    /// @param amount Amount of PYUSDX required.
    function _revertIfInsufficientPYUSDXBacking(uint256 amount) internal view {
        uint256 backing_ = _pyusdxBacking();
        if (amount > backing_) revert InsufficientPYUSDXBacking(amount, backing_);
    }

    /// @dev   Reverts if the extension holds less than `amount` of `asset`.
    /// @param asset  Address of the asset.
    /// @param amount Amount of `asset` required (in asset decimals).
    function _revertIfInsufficientAssetBacking(address asset, uint256 amount) internal view {
        uint256 assetBacking_ = assetBalanceOf(asset);
        if (amount > assetBacking_) revert InsufficientAssetBacking(asset, amount, assetBacking_);
    }

    /// @dev    Converts `amount` from asset decimals to extension decimals.
    /// @param  asset  Address of the asset.
    /// @param  amount Amount in asset decimals.
    /// @return Amount in extension decimals.
    function _fromAssetToExtensionAmount(address asset, uint256 amount) internal view returns (uint256) {
        return _convertAmounts(assetDecimals(asset), PYUSDX_DECIMALS, amount);
    }

    /// @dev    Converts `amount` from extension decimals to asset decimals.
    /// @param  asset  Address of the asset.
    /// @param  amount Amount in extension decimals.
    /// @return Amount in asset decimals.
    function _fromExtensionToAssetAmount(address asset, uint256 amount) internal view returns (uint256) {
        return _convertAmounts(PYUSDX_DECIMALS, assetDecimals(asset), amount);
    }

    /* ============ Internal Pure Functions ============ */

    /// @dev    Converts `amount` between decimal representations.
    /// @param  fromDecimals Decimals of the input amount.
    /// @param  toDecimals   Decimals of the output amount.
    /// @param  amount       The amount to convert.
    /// @return The converted amount.
    function _convertAmounts(uint8 fromDecimals, uint8 toDecimals, uint256 amount) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;

        return
            fromDecimals > toDecimals
                ? amount / (10 ** (fromDecimals - toDecimals))
                : amount * (10 ** (toDecimals - fromDecimals));
    }
}
