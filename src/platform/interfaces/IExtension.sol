// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { IERC20Extended } from "../../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20Extended.sol";

/// @title  PYUSDX Extension interface extending Extended ERC20.
/// @author M0 Labs
interface IExtension is IERC20Extended {
    /* ============ Custom Errors ============ */

    /// @notice Emitted when there is insufficient balance to decrement from `account`.
    /// @param  account The account with insufficient balance.
    /// @param  balance The balance of the account.
    /// @param  amount  The amount to decrement.
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    /// @notice Emitted when the account is address(0).
    error ZeroAccount();

    /// @notice Emitted when the amount is 0.
    error ZeroAmount();

    /// @notice Emitted in constructor if PYUSDX is 0x0.
    error ZeroPYUSDX();

    /// @notice Emitted in constructor if swap facility is 0x0.
    error ZeroSwapFacility();

    /// @notice Emitted when the caller is not the swap facility.
    error NotSwapFacility();

    /// @notice Emitted when attempting to unpin a proxy that is not pinned.
    error NotPinned();

    /// @notice Emitted when pinning to version 0.
    error ZeroVersion();

    /* ============ Interactive Functions ============ */

    /// @notice Wraps `amount` PYUSDX from the caller into extension token for `recipient`.
    /// @dev    Pulls PYUSDX from `msg.sender` via `transferFrom`. Only callable by the swap facility.
    /// @param  recipient The account receiving the minted extension token.
    /// @param  amount    The amount of extension token minted.
    function wrap(address recipient, uint256 amount) external;

    /// @notice Unwraps `amount` extension token from the caller back into PYUSDX.
    /// @dev    Burns extension tokens from `msg.sender` and transfers PYUSDX to `msg.sender`.
    ///         Only callable by the swap facility.
    /// @param  amount The amount of extension token burned.
    function unwrap(uint256 amount) external;

    /// @notice Pins this proxy to a specific implementation version.
    /// @dev    Only callable by an address with VERSION_MANAGER_ROLE.
    /// @param  version The version number to pin to (must be > 0).
    function pinVersion(uint256 version) external;

    /// @notice Unpins this proxy, restoring beacon-follows-latest behavior.
    /// @dev    Only callable by an address with VERSION_MANAGER_ROLE.
    function unpinVersion() external;

    /* ============ View/Pure Functions ============ */

    /// @notice The address of the PYUSDX token contract.
    function pyusdx() external view returns (address);

    /// @notice The address of the swap facility contract.
    function swapFacility() external view returns (address);

    /// @notice Returns the origin beacon address (set at construction, never changes).
    /// @return The origin beacon address.
    function originBeacon() external view returns (address);

    /// @notice Returns whether the proxy is currently pinned to a specific implementation.
    /// @return True if pinned, false if following the beacon's latest.
    function isPinned() external view returns (bool);

    /// @notice Returns the pinned implementation address, or address(0) if not pinned.
    /// @return The pinned implementation address.
    function pinnedImplementation() external view returns (address);

    /// @notice Role required to call `pinVersion` / `unpinVersion`.
    function VERSION_MANAGER_ROLE() external view returns (bytes32);
}
