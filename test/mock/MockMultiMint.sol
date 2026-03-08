// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { ERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IMultiMint } from "../../src/interfaces/IMultiMint.sol";

/**
 * @title MockMultiMint
 * @notice Mock implementation of IMultiMint for testing SwapFacility.
 */
contract MockMultiMint is ERC20, IMultiMint {
    /* ============ Immutable ============ */

    /// @notice PYUSDF token address.
    IERC20 public immutable pyusdx;

    /// @notice SwapFacility address.
    address public immutable swapFacility;

    /* ============ Storage ============ */

    /// @notice Mapping of allowed assets.
    mapping(address asset => bool) public allowedAssets;

    /// @notice Asset balances held by the extension.
    mapping(address asset => uint256) public assetBalances;

    /// @notice Asset caps.
    mapping(address asset => uint256) public assetCaps;

    /// @notice Cached asset decimals.
    mapping(address asset => uint8) public cachedAssetDecimals;

    /// @notice Yield recipient.
    address public override yieldRecipient;

    /// @notice Role hashes.
    bytes32 public constant override ASSET_CAP_MANAGER_ROLE = keccak256("ASSET_CAP_MANAGER_ROLE");
    bytes32 public constant override YIELD_RECIPIENT_MANAGER_ROLE = keccak256("YIELD_RECIPIENT_MANAGER_ROLE");

    /// @notice PYUSDX decimals constant.
    uint8 public constant override PYUSDX_DECIMALS = 6;

    /* ============ Errors ============ */

    error AssetNotAllowed(address asset);

    /* ============ Constructor ============ */

    constructor(
        address pyusdx_,
        address swapFacility_,
        address yieldRecipient_
    ) ERC20("Mock MultiMint Extension", "mmEXT") {
        pyusdx = IERC20(pyusdx_);
        swapFacility = swapFacility_;
        yieldRecipient = yieldRecipient_;
    }

    /* ============ Interactive Functions ============ */

    /**
     * @notice Mint extension tokens by depositing `asset` tokens.
     * @param asset     Address of the asset to deposit.
     * @param recipient Address that will receive the extension tokens.
     * @param amount    Amount of asset tokens to deposit.
     */
    function wrap(address asset, address recipient, uint256 amount) external override {
        if (!allowedAssets[asset]) revert AssetNotAllowed(asset);

        // Transfer asset from caller to this contract.
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Mint extension tokens 1:1 (ignoring decimal conversion for simplicity).
        _mint(recipient, amount);
        assetBalances[asset] += amount;

        emit AssetWrapped(asset, amount, recipient, amount);
    }

    /**
     * @notice Allows depositing PYUSDX to receive `asset` tokens from reserves.
     * @param asset     Address of the asset to receive.
     * @param recipient Address that will receive the `asset` token.
     * @param amount    Amount of PYUSDX to deposit (in PYUSDX decimals).
     */
    function replaceAsset(address asset, address recipient, uint256 amount) external override {
        if (!allowedAssets[asset]) revert AssetNotAllowed(asset);

        // Transfer PYUSDX from caller to this contract.
        pyusdx.transferFrom(msg.sender, address(this), amount);

        // Transfer asset to recipient (assumes 1:1 ratio for simplicity).
        uint256 assetAmount = amount;
        if (assetBalances[asset] < assetAmount) {
            revert InsufficientAssetBacking(asset, assetAmount, assetBalances[asset]);
        }
        assetBalances[asset] -= assetAmount;
        IERC20(asset).transfer(recipient, assetAmount);

        emit AssetReplacedWithPYUSDX(asset, assetAmount, recipient, amount);
    }

    /**
     * @notice Claims accrued yield to the yield recipient.
     */
    function claimYield() external override returns (uint256) {
        uint256 yieldAmount = 0; // Mock: no actual yield.
        emit YieldClaimed(yieldAmount);
        return yieldAmount;
    }

    /**
     * @notice Sets the yield recipient.
     * @param yieldRecipient_ The address of the new yield recipient.
     */
    function setYieldRecipient(address yieldRecipient_) external override {
        yieldRecipient = yieldRecipient_;
        emit YieldRecipientSet(yieldRecipient_);
    }

    /**
     * @notice Sets the asset cap for a given `asset`.
     * @param asset Address of the asset.
     * @param cap   Maximum allowed amount of `asset` that can back the extension.
     */
    function setAssetCap(address asset, uint256 cap) external override {
        assetCaps[asset] = cap;
        emit AssetCapSet(asset, cap);
    }

    /* ============ View Functions ============ */

    /// @notice Gets the cached balance of a given asset held by the extension.
    function assetBalanceOf(address asset) external view override returns (uint256) {
        return assetBalances[asset];
    }

    /// @notice Gets the asset cap for a given asset.
    function assetCap(address asset) external view override returns (uint256) {
        return assetCaps[asset];
    }

    /// @notice Gets the cached decimals of a given asset.
    function assetDecimals(address asset) external view override returns (uint8) {
        return cachedAssetDecimals[asset];
    }

    /// @notice Gets the total non-PYUSDX assets held by the extension.
    function totalAssets() external pure override returns (uint256) {
        return 0; // Mock: simplified.
    }

    /// @notice Checks if an asset is allowed as backing.
    function isAllowedAsset(address asset) external view override returns (bool) {
        return allowedAssets[asset];
    }

    /**
     * @notice Checks if wrapping `amount` of `asset` is allowed.
     */
    function isAllowedToWrap(address asset, uint256 amount) external view override returns (bool) {
        return allowedAssets[asset] && (assetCaps[asset] == 0 || assetBalances[asset] + amount <= assetCaps[asset]);
    }

    /**
     * @notice Checks if unwrapping `amount` of extension tokens is allowed.
     */
    function isAllowedToUnwrap(uint256) external pure override returns (bool) {
        return true; // Mock: always allowed.
    }

    /**
     * @notice Checks if replacing `asset` with PYUSDX is allowed.
     */
    function isAllowedToReplaceAssetWithPYUSDX(address asset, uint256 amount) external view override returns (bool) {
        return allowedAssets[asset] && assetBalances[asset] >= amount;
    }

    /// @notice The amount of pending accrued yield from PYUSDX.
    function yield() external pure override returns (uint256) {
        return 0; // Mock: no yield.
    }

    /* ============ Admin Functions ============ */

    /**
     * @notice Sets whether an asset is allowed.
     * @param asset  Address of the asset.
     * @param allowed Whether the asset is allowed.
     */
    function setAllowedAsset(address asset, bool allowed) external {
        allowedAssets[asset] = allowed;
    }

    /**
     * @notice Sets the cached decimals for an asset.
     * @param asset   Address of the asset.
     * @param decimal Decimals to cache.
     */
    function setAssetDecimals(address asset, uint8 decimal) external {
        cachedAssetDecimals[asset] = decimal;
    }

    /**
     * @notice Sets the asset balance directly (for testing).
     * @param asset  Address of the asset.
     * @param amount Balance to set.
     */
    function setAssetBalance(address asset, uint256 amount) external {
        assetBalances[asset] = amount;
    }

    /* ============ ERC20 Overrides ============ */

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
