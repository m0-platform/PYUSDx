// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IPYUSDXFaucet } from "./interfaces/IPYUSDXFaucet.sol";

/// @title  PYUSDXFaucet
/// @author M0 Labs
/// @notice A permissionless, pre-funded faucet for distributing PYUSDx on Testnet.
contract PYUSDXFaucet is IPYUSDXFaucet {
    /* ============ Constants ============ */

    /// @inheritdoc IPYUSDXFaucet
    uint256 public constant AMOUNT = 100e6;

    /* ============ State Variables ============ */

    /// @inheritdoc IPYUSDXFaucet
    address public immutable pyusdx;

    /* ============ Constructor ============ */

    /// @notice Constructs the PYUSDXFaucet.
    /// @param  pyusdx_ The address of the PYUSDx token to distribute.
    constructor(address pyusdx_) {
        if (pyusdx_ == address(0)) revert ZeroPYUSDX();

        pyusdx = pyusdx_;
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IPYUSDXFaucet
    function requestPYUSDX(address recipient) external {
        uint256 balance = IERC20(pyusdx).balanceOf(address(this));

        if (balance < AMOUNT) revert InsufficientFaucetBalance(AMOUNT, balance);

        emit Requested(recipient, AMOUNT);

        IERC20(pyusdx).transfer(recipient, AMOUNT);
    }
}
