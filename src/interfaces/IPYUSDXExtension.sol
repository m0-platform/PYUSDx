// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20Extended } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20Extended.sol";

/**
 * @title  PYUSDX Extension interface extending Extended ERC20.
 * @author M0 Labs
 */
interface IPYUSDXExtension is IERC20Extended {
    /* ============ Custom Errors ============ */

    /**
     * @notice Emitted when there is insufficient balance to decrement from `account`.
     * @param  account The account with insufficient balance.
     * @param  balance The balance of the account.
     * @param  amount  The amount to decrement.
     */
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    /// @notice Emitted in constructor if PYUSDX is 0x0.
    error ZeroPYUSDX();

    /// @notice Emitted when `otherExtension` does not share the same PYUSDX underlying.
    error InvalidExtension(address otherExtension);

    /* ============ Events ============ */

    /// @notice Emitted when tokens are swapped from one extension to another via `wrapFrom`.
    event SwappedFrom(address indexed otherExtension, address indexed account, uint256 amount);

    /* ============ Interactive Functions ============ */

    /**
     * @notice Wraps `amount` PYUSDX from the caller into extension token for `recipient`.
     * @dev    Pulls PYUSDX from `msg.sender` via `transferFrom`.
     * @param  recipient The account receiving the minted extension token.
     * @param  amount    The amount of extension token minted.
     */
    function wrap(address recipient, uint256 amount) external;

    /**
     * @notice Unwraps `amount` extension token from the caller back into PYUSDX.
     * @dev    Burns extension tokens from `msg.sender` and transfers PYUSDX to `msg.sender`.
     * @param  amount The amount of extension token burned.
     */
    function unwrap(uint256 amount) external;

    /**
     * @notice Atomically swaps `amount` of another extension's tokens for this extension's tokens.
     * @dev    Validates that `otherExtension` is non-zero and shares the same PYUSDX underlying,
     *         then pulls `otherExtension` tokens from `msg.sender`, unwraps them into PYUSDX,
     *         and wraps the PYUSDX into this extension for `msg.sender`.
     *         The actual amount minted is based on the PYUSDX balance change (balance-diff),
     *         which may be less than `amount` if the source extension's unwrap delivers less.
     *         Protected by a reentrancy guard since it calls into untrusted external contracts.
     *         Emits a {SwappedFrom} event on success.
     * @param  otherExtension The source extension to swap from.
     * @param  amount         The amount to swap.
     */
    function wrapFrom(address otherExtension, uint256 amount) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The address of the PYUSDX token contract.
    function pyusdx() external view returns (address);
}
