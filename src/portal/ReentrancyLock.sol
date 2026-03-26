// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.34;

/// @title  ReentrancyLock contract.
/// @author Uniswap Labs. Modified from https://github.com/Uniswap/v4-periphery/blob/main/src/base/ReentrancyLock.sol
/// @notice A transient reentrancy lock, that stores the caller's address as the lock
abstract contract ReentrancyLock {
    error ContractLocked();

    address internal transient _locker;

    modifier whenNotLocked() {
        if (_locker != address(0)) revert ContractLocked();
        _locker = msg.sender;
        _;
        _locker = address(0);
    }
}
