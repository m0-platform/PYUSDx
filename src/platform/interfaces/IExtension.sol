// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

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

    /* ============ View/Pure Functions ============ */

    /// @notice The address of the PYUSDX token contract.
    function pyusdx() external view returns (address);

    /// @notice The address of the swap facility contract.
    function swapFacility() external view returns (address);
}
