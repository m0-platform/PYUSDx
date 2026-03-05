// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { PYUSDX } from "../../src/PYUSDX.sol";

/// @title PYUSDX Harness
/// @notice Test harness that exposes internal state and functions for testing
contract PYUSDXHarness is PYUSDX {
    /// @notice Constructs the harness with the same parameters as PYUSDX
    constructor() PYUSDX() {}

    /// @notice Sets account info directly (bypassing normal checks)
    /// @param account The account to configure
    /// @param earnerRate The earner rate in basis points (0 = not earning)
    /// @param feeRate The fee rate (basis points)
    /// @param claimRecipient The claim recipient address
    function setAccountInfoDirect(address account, uint32 earnerRate, uint16 feeRate, address claimRecipient) external {
        Account storage existing = _getPYUSDXStorageLocation().accounts[account];
        bool willEarn = earnerRate > 0;
        // Initialize lastIndex to EXP_SCALED_ONE when enabling earning for a new account
        uint128 lastIndex_ = willEarn
            ? (existing.lastIndex == 0 ? uint128(EXP_SCALED_ONE) : existing.lastIndex)
            : uint128(0);
        uint40 lastUpdateTimestamp_ = willEarn
            ? (existing.lastUpdateTimestamp == 0 ? uint40(block.timestamp) : existing.lastUpdateTimestamp)
            : uint40(0);
        _getPYUSDXStorageLocation().accounts[account] = Account({
            balance: existing.balance,
            lastIndex: lastIndex_,
            lastUpdateTimestamp: lastUpdateTimestamp_,
            earnerRate: earnerRate,
            claimRecipient: claimRecipient,
            earningPrincipal: willEarn ? existing.earningPrincipal : uint112(0),
            feeRate: feeRate
        });

        emit AccountInfoUpdated(account, earnerRate, feeRate, claimRecipient);
    }

    /// @notice Sets the earning principal for an account
    /// @param account The account to configure
    /// @param principal The principal amount to set
    function setEarningPrincipal(address account, uint112 principal) external {
        _getPYUSDXStorageLocation().accounts[account].earningPrincipal = principal;
    }

    /// @notice Sets the total supply directly
    /// @param supply The total supply to set
    function setTotalSupply(uint256 supply) external {
        _getPYUSDXStorageLocation().totalSupply = supply;
    }

    /// @notice Sets an account's balance directly
    /// @param account The account to configure
    /// @param balance The balance to set
    function setBalance(address account, uint256 balance) external {
        _getPYUSDXStorageLocation().accounts[account].balance = balance;
    }

    /// @notice Gets the internal storage structure for an account
    /// @param account The account to query
    /// @return earnerRate The earner rate (0 = not earning)
    /// @return feeRate The fee rate
    /// @return claimRecipient The claim recipient
    function getAccountStorage(
        address account
    ) external view returns (uint32 earnerRate, uint16 feeRate, address claimRecipient) {
        Account memory accountData = _getPYUSDXStorageLocation().accounts[account];
        return (accountData.earnerRate, accountData.feeRate, accountData.claimRecipient);
    }

    /// @notice Expose internal _addEarningAmount for testing
    function addEarningAmount(address account, uint256 amount) external {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        _addEarningAmount($, account, amount);
    }

    /// @notice Expose internal _addNonEarningAmount for testing
    function addNonEarningAmount(address account, uint256 amount) external {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        _addNonEarningAmount($, account, amount);
    }

    /// @notice Set the per-account lastIndex directly for testing
    /// @param account The account to configure
    /// @param newIndex The index value to set
    function setAccountLastIndex(address account, uint128 newIndex) external {
        _getPYUSDXStorageLocation().accounts[account].lastIndex = newIndex;
        _getPYUSDXStorageLocation().accounts[account].lastUpdateTimestamp = uint40(block.timestamp);
    }

    /// @notice Set the per-account earner rate directly for testing
    /// @param account The account to configure
    /// @param newRateBps The rate in basis points
    function setAccountRateBps(address account, uint32 newRateBps) external {
        _getPYUSDXStorageLocation().accounts[account].earnerRate = newRateBps;
    }
}
