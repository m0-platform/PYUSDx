// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

/// @title  IPYUSDXFaucet
/// @author M0 Labs
/// @notice Interface for a permissionless, pre-funded PYUSDx faucet for Testnet.
interface IPYUSDXFaucet {
    /* ============ Events ============ */

    /// @notice Emitted when PYUSDx is sent from the faucet.
    /// @param  recipient The account that received the PYUSDx.
    /// @param  amount    The amount of PYUSDx sent.
    event Requested(address indexed recipient, uint256 amount);

    /* ============ Custom Errors ============ */

    /// @notice Thrown when the PYUSDx address is the zero address.
    error ZeroPYUSDX();

    /// @notice Thrown when the faucet does not hold enough PYUSDx to fulfill the request.
    /// @param  requested The amount required to fulfill the request.
    /// @param  available The amount currently held by the faucet.
    error InsufficientFaucetBalance(uint256 requested, uint256 available);

    /* ============ Interactive Functions ============ */

    /// @notice Sends a fixed amount of PYUSDx to a recipient.
    /// @param  recipient The address to receive the PYUSDx.
    function requestPYUSDX(address recipient) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The fixed amount of PYUSDx sent per request.
    function AMOUNT() external view returns (uint256);

    /// @notice The address of the PYUSDx token distributed by the faucet.
    function pyusdx() external view returns (address);
}
