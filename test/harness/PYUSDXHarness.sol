// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { PYUSDX } from "../../src/PYUSDX.sol";

/// @title PYUSDX Harness
/// @notice Test harness that exposes internal state and functions for testing
contract PYUSDXHarness is PYUSDX {
    /// @notice Constructs the harness with the same parameters as PYUSDX
    constructor(address minterGateway_, address pyusd_) PYUSDX(minterGateway_, pyusd_) {}

    /// @notice Sets earning details for an account directly (bypassing normal checks)
    /// @param account The account to configure
    /// @param isEarning Whether the account is earning
    /// @param earnerManager The earner manager for the account
    /// @param feeRate The fee rate (basis points)
    /// @param claimRecipient The claim recipient address
    function setEarningDetails(
        address account,
        bool isEarning,
        address earnerManager,
        uint16 feeRate,
        address claimRecipient
    ) external {
        _getPYUSDXStorageLocation().accounts[account] = Account({
            earnerManager: isEarning ? earnerManager : address(0),
            balance: _getPYUSDXStorageLocation().accounts[account].balance,
            isEarning: isEarning,
            earningPrincipal: isEarning ? _getPYUSDXStorageLocation().accounts[account].earningPrincipal : uint112(0),
            feeRate: feeRate,
            claimRecipient: claimRecipient
        });

        emit EarningDetailsSet(account, isEarning, earnerManager, feeRate, claimRecipient);
    }

    /// @notice Sets the earning principal for an account
    /// @param account The account to configure
    /// @param principal The principal amount to set
    function setEarningPrincipal(address account, uint112 principal) external {
        _getPYUSDXStorageLocation().accounts[account].earningPrincipal = principal;
    }

    /// @notice Sets the total earning principal directly
    /// @param principal The total earning principal to set
    function setTotalEarningPrincipal(uint112 principal) external {
        _getPYUSDXStorageLocation().totalEarningPrincipal = principal;
    }

    /// @notice Sets the total non-earning supply directly
    /// @param supply The total non-earning supply to set
    function setTotalNonEarningSupply(uint240 supply) external {
        _getPYUSDXStorageLocation().totalNonEarningSupply = supply;
    }

    /// @notice Sets an account's balance directly
    /// @param account The account to configure
    /// @param balance The balance to set
    function setBalance(address account, uint240 balance) external {
        _getPYUSDXStorageLocation().accounts[account].balance = balance;
    }

    /// @notice Gets the internal storage structure for an account
    /// @param account The account to query
    /// @return isEarning Whether the account is earning
    /// @return earnerManager The earner manager for the account
    /// @return feeRate The fee rate
    /// @return claimRecipient The claim recipient
    function getAccountStorage(
        address account
    ) external view returns (bool isEarning, address earnerManager, uint16 feeRate, address claimRecipient) {
        Account memory accountData = _getPYUSDXStorageLocation().accounts[account];
        return (accountData.isEarning, accountData.earnerManager, accountData.feeRate, accountData.claimRecipient);
    }

    /// @notice Expose internal _addEarningAmount for testing
    function addEarningAmount(address account, uint240 amount, uint128 index) external {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        _addEarningAmount($, account, amount, index);
    }

    /// @notice Expose internal _addNonEarningAmount for testing
    function addNonEarningAmount(address account, uint240 amount) external {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        _addNonEarningAmount($, account, amount);
    }
}
