// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { PYUSDX } from "../../src/PYUSDX.sol";

/// @title PYUSDX Harness
/// @notice Test harness that exposes internal state and functions for testing
contract PYUSDXHarness is PYUSDX {
    /// @notice Constructs the harness with the same parameters as PYUSDX
    constructor() PYUSDX() {}

    /// @notice Sets the earning principal for an account
    /// @param account The account to configure
    /// @param principal The principal amount to set
    function setEarningPrincipal(address account, uint112 principal) external {
        _getPYUSDXStorage().accounts[account].earningPrincipal = principal;
    }

    /// @notice Sets the total supply directly
    /// @param supply The total supply to set
    function setTotalSupply(uint256 supply) external {
        _getPYUSDXStorage().totalSupply = supply;
    }

    /// @notice Sets an account's balance directly
    /// @param account The account to configure
    /// @param balance The balance to set
    function setBalance(address account, uint256 balance) external {
        _getPYUSDXStorage().accounts[account].balance = balance;
    }

    /// @notice Gets the internal storage structure for an account
    /// @param account The account to query
    /// @return earnerRate The earner rate (0 = not earning)
    /// @return feeRate The fee rate
    /// @return claimRecipient The claim recipient
    function getAccountStorage(
        address account
    ) external view returns (uint16 earnerRate, uint16 feeRate, address claimRecipient) {
        Account memory accountData = _getPYUSDXStorage().accounts[account];
        return (accountData.earnerRate, accountData.feeRate, accountData.claimRecipient);
    }

    /// @notice Expose internal _addEarningAmount for testing
    function addEarningAmount(address account, uint256 amount) external {
        PYUSDXStorage storage $ = _getPYUSDXStorage();
        _addEarningAmount($, account, amount);
    }

    /// @notice Expose internal _addNonEarningAmount for testing
    function addNonEarningAmount(address account, uint256 amount) external {
        PYUSDXStorage storage $ = _getPYUSDXStorage();
        _addNonEarningAmount($, account, amount);
    }

    /// @notice Set the per-account lastIndex directly for testing
    /// @param account The account to configure
    /// @param newIndex The index value to set
    function setAccountLastIndex(address account, uint128 newIndex) external {
        _getPYUSDXStorage().accounts[account].lastIndex = newIndex;
        _getPYUSDXStorage().accounts[account].lastUpdateTimestamp = uint40(block.timestamp);
    }

    /// @notice Set the per-account earner rate directly for testing
    /// @param account The account to configure
    /// @param newRateBps The rate in basis points
    function setAccountRateBps(address account, uint16 newRateBps) external {
        _getPYUSDXStorage().accounts[account].earnerRate = newRateBps;
    }

    /// @notice Expose internal _getPrincipalAmountRoundedDown for testing.
    function getPrincipalAmountRoundedDown(uint256 presentAmount, uint128 index) external pure returns (uint112) {
        return _getPrincipalAmountRoundedDown(presentAmount, index);
    }

    /// @notice Expose internal _getPrincipalAmountRoundedUp for testing.
    function getPrincipalAmountRoundedUp(uint256 presentAmount, uint128 index) external pure returns (uint112) {
        return _getPrincipalAmountRoundedUp(presentAmount, index);
    }

    /// @notice Sets rate-limit storage directly for edge-case testing.
    function setRateLimitState(
        address issuer,
        uint128 capacity,
        uint128 refillPerSecond,
        uint128 remainingAmount,
        uint40 lastRefillTime
    ) external {
        Bucket storage bucket = _getRateLimiterStorage().issuerBuckets[issuer];

        bucket.capacity = capacity;
        bucket.refillPerSecond = refillPerSecond;
        bucket.remainingAmount = remainingAmount;
        bucket.lastRefillTime = lastRefillTime;
    }
}
