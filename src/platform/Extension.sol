// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { ERC20ExtendedUpgradeable } from "../../lib/evm-m-extensions/lib/common/src/ERC20ExtendedUpgradeable.sol";

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { StorageSlot } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol";

import { Freezable } from "../../lib/evm-m-extensions/src/components/freezable/Freezable.sol";
import { Pausable } from "../../lib/evm-m-extensions/src/components/pausable/Pausable.sol";

import { IExtension } from "./interfaces/IExtension.sol";
import { IExtensionBeacon } from "./interfaces/IExtensionBeacon.sol";
import { ISwapFacility } from "../swap/interfaces/ISwapFacility.sol";

/// @title  Extension
/// @notice Upgradeable ERC20 base contract for wrapping PYUSDX into a branded extension token.
/// @author M0 Labs
abstract contract Extension is IExtension, ERC20ExtendedUpgradeable, Freezable, Pausable {
    /* ============ Constants ============ */

    /// @dev ERC-1967 beacon storage slot (shared with ExtensionBeaconProxy).
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// @dev Storage location for the extension type (shared with ExtensionBeaconProxy).
    ///      keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXExtensionType")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _EXTENSION_TYPE_STORAGE_LOCATION =
        0x50809f8892663c0bc92e8283fda4cb9143fb961da9c4bc5652b13b5c450bbc00;

    /// @dev Storage location for the pinned implementation version (shared with ExtensionBeaconProxy).
    ///      keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXPinnedVersion")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _PINNED_VERSION_STORAGE_LOCATION =
        0xfec66d3fc30888a287564007fecbbfaf6a964b972d5e0e57e4d8faceddbe2b00;

    /* ============ Variables ============ */

    /// @notice Role required to call `pinVersion`.
    bytes32 public constant VERSION_MANAGER_ROLE = keccak256("VERSION_MANAGER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtension
    address public immutable pyusdx;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtension
    address public immutable swapFacility;

    /* ============ Modifiers ============ */

    modifier onlySwapFacility() {
        if (msg.sender != swapFacility) revert NotSwapFacility();
        _;
    }

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Constructs Extension Implementation contract.
    /// @dev    Sets immutable storage.
    /// @param  pyusdx_       The address of the PYUSDX token.
    /// @param  swapFacility_ The address of the swap facility.
    constructor(address pyusdx_, address swapFacility_) {
        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDX();
        if ((swapFacility = swapFacility_) == address(0)) revert ZeroSwapFacility();

        _disableInitializers();
    }

    /* ============ Initializer ============ */

    /// @notice Initializes the generic PYUSDX extension token.
    /// @param  name           The name of the token.
    /// @param  symbol         The symbol of the token.
    /// @param  freezeManager  The address of the freeze manager.
    /// @param  pauser         The address of the pauser.
    function __Extension_init(
        string memory name,
        string memory symbol,
        address freezeManager,
        address pauser
    ) internal onlyInitializing {
        __ERC20ExtendedUpgradeable_init(name, symbol, 6);
        __Freezable_init(freezeManager);
        __Pausable_init(pauser);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IExtension
    function wrap(address recipient, uint256 amount) external onlySwapFacility {
        _wrap(ISwapFacility(msg.sender).msgSender(), recipient, amount);
    }

    /// @inheritdoc IExtension
    function unwrap(uint256 amount) external onlySwapFacility {
        _unwrap(ISwapFacility(msg.sender).msgSender(), amount);
    }

    /// @inheritdoc IExtension
    function pinVersion(uint256 version) external onlyRole(VERSION_MANAGER_ROLE) {
        if (version != 0) {
            address beacon = StorageSlot.getAddressSlot(_BEACON_SLOT).value;
            IExtensionBeacon.ExtensionType extensionType = IExtensionBeacon.ExtensionType(
                StorageSlot.getUint256Slot(_EXTENSION_TYPE_STORAGE_LOCATION).value
            );

            // NOTE: This call is purely for validation — it reverts with `NoImplementationRegistered`
            //       if the version does not exist in the beacon.
            IExtensionBeacon(beacon).implementation(extensionType, version);
        }

        StorageSlot.getUint256Slot(_PINNED_VERSION_STORAGE_LOCATION).value = version;

        emit VersionPinned(version);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IERC20
    function balanceOf(address account) public view virtual returns (uint256);

    /// @inheritdoc IExtension
    function pinnedVersion() external view returns (uint256) {
        return StorageSlot.getUint256Slot(_PINNED_VERSION_STORAGE_LOCATION).value;
    }

    /* ============ Hooks For Internal Interactive Functions ============ */

    /// @dev   Hook called before approval of PYUSDX Extension token.
    /// @param account The sender's address.
    /// @param spender The spender address.
    function _beforeApprove(address account, address spender, uint256 /* amount */) internal view virtual {
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();
        _revertIfFrozen($, account);
        _revertIfFrozen($, spender);
    }

    /// @dev   Hook called before wrapping PYUSDX into PYUSDX Extension token.
    /// @param account   The account from which PYUSDX is deposited.
    /// @param recipient The account receiving the minted PYUSDX Extension token.
    function _beforeWrap(address account, address recipient, uint256 /* amount */) internal view virtual {
        _requireNotPaused();

        FreezableStorageStruct storage $ = _getFreezableStorageLocation();
        _revertIfFrozen($, account);
        _revertIfFrozen($, recipient);
    }

    /// @dev   Hook called before unwrapping PYUSDX Extension token.
    /// @param account The original caller (resolved via swap facility).
    function _beforeUnwrap(address account, uint256 /* amount */) internal view virtual {
        _requireNotPaused();

        _revertIfFrozen(_getFreezableStorageLocation(), account);
    }

    /// @dev   Hook called before transferring PYUSDX Extension token.
    /// @param sender    The sender's address.
    /// @param recipient The recipient's address.
    function _beforeTransfer(address sender, address recipient, uint256 /* amount */) internal view virtual {
        _requireNotPaused();

        FreezableStorageStruct storage $ = _getFreezableStorageLocation();
        _revertIfFrozen($, msg.sender);
        _revertIfFrozen($, sender);
        _revertIfFrozen($, recipient);
    }

    /* ============ Internal Interactive Functions ============ */

    /// @dev   Approve `spender` to spend `amount` of tokens from `account`.
    /// @param account The address approving the allowance.
    /// @param spender The address approved to spend the tokens.
    /// @param amount  The amount of tokens being approved for spending.
    function _approve(address account, address spender, uint256 amount) internal override {
        _beforeApprove(account, spender, amount);
        super._approve(account, spender, amount);
    }

    /// @dev   Wraps `amount` PYUSDX from `account` into extension token for `recipient`.
    /// @param account   The original caller (resolved via swap facility).
    /// @param recipient The account receiving the minted extension token.
    /// @param amount    The amount of PYUSDX deposited.
    function _wrap(address account, address recipient, uint256 amount) internal {
        _revertIfZeroAccount(recipient);
        _revertIfZeroAmount(amount);

        _beforeWrap(account, recipient, amount);

        IERC20(pyusdx).transferFrom(msg.sender, address(this), amount);

        _mint(recipient, amount);
    }

    /// @dev   Unwraps `amount` extension token from `account` into PYUSDX.
    /// @param account The original caller (resolved via swap facility).
    /// @param amount  The amount of extension token burned.
    function _unwrap(address account, uint256 amount) internal {
        _revertIfZeroAmount(amount);
        _revertIfInsufficientBalance(msg.sender, amount);

        _beforeUnwrap(account, amount);

        _burn(msg.sender, amount);

        IERC20(pyusdx).transfer(msg.sender, amount);
    }

    /// @dev   Mints `amount` tokens to `recipient`.
    /// @param recipient The address to which the tokens will be minted.
    /// @param amount    The amount of tokens to mint.
    function _mint(address recipient, uint256 amount) internal virtual;

    /// @dev   Burns `amount` tokens from `account`.
    /// @param account The address from which the tokens will be burned.
    /// @param amount  The amount of tokens to burn.
    function _burn(address account, uint256 amount) internal virtual;

    /// @dev   Internal balance update function that needs to be implemented by the inheriting contract.
    /// @param sender    The sender's address.
    /// @param recipient The recipient's address.
    /// @param amount    The amount to be transferred.
    function _update(address sender, address recipient, uint256 amount) internal virtual;

    /// @dev   Internal ERC20 transfer function.
    /// @param sender    The sender's address.
    /// @param recipient The recipient's address.
    /// @param amount    The amount to be transferred.
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        _revertIfZeroAccount(recipient);

        _beforeTransfer(sender, recipient, amount);

        emit Transfer(sender, recipient, amount);

        if (amount == 0) return;

        _revertIfInsufficientBalance(sender, amount);

        _update(sender, recipient, amount);
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev    Returns the PYUSDX balance of `account`.
    /// @param  account The account being queried.
    /// @return balance The PYUSDX balance of the account.
    function _pyusdxBalanceOf(address account) internal view returns (uint256) {
        return IERC20(pyusdx).balanceOf(account);
    }

    /// @dev   Reverts if `recipient` is address(0).
    /// @param recipient Address of a recipient.
    function _revertIfZeroAccount(address recipient) internal pure {
        if (recipient == address(0)) revert ZeroAccount();
    }

    /// @dev   Reverts if `amount` is equal to 0.
    /// @param amount Amount of token.
    function _revertIfZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /// @dev   Reverts if `account` balance is below `amount`.
    /// @param account Address of an account.
    /// @param amount  Amount to transfer or burn.
    function _revertIfInsufficientBalance(address account, uint256 amount) internal view {
        uint256 balance = balanceOf(account);

        if (balance < amount) revert InsufficientBalance(account, balance, amount);
    }
}
