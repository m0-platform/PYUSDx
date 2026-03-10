// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPYUSDX } from "../../src/IPYUSDX.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

/// @title PYUSDX Invariant Tests
/// @notice Invariant tests for PYUSDX
contract PYUSDXInvariants is PYUSDXBaseUnitTest {
    /* ============ Invariant: Total Supply >= Sum of Balances ============ */

    function inv_totalSupplyGeSumOfBalances() public view {
        uint256 sumOfBalances = pyusdx.balanceOf(alice) +
            pyusdx.balanceOf(bob) +
            pyusdx.balanceOf(carol) +
            pyusdx.balanceOf(david);

        assertTrue(pyusdx.totalSupply() >= sumOfBalances, "totalSupply < sum of balances");
    }

    /* ============ Invariant: Non-Earning Principal Zero ============ */

    function inv_nonEarningPrincipalZero() public view {
        // For accounts that are not earning, earningPrincipal should be 0
        address[] memory testAccounts = new address[](4);
        testAccounts[0] = alice;
        testAccounts[1] = bob;
        testAccounts[2] = carol;
        testAccounts[3] = david;

        for (uint256 i = 0; i < testAccounts.length; i++) {
            (uint32 earnerRate_, , ) = pyusdx.getAccountEarningInfo(testAccounts[i]);
            if (earnerRate_ == 0) {
                assertEq(pyusdx.earningPrincipalOf(testAccounts[i]), 0, "Non-earning account has non-zero principal");
            }
        }
    }

    /* ============ Invariant: Balance Never Exceeds Total Supply ============ */

    function inv_balanceNeverExceedsTotalSupply() public view {
        uint256 totalBalance = pyusdx.balanceOf(alice) +
            pyusdx.balanceOf(bob) +
            pyusdx.balanceOf(carol) +
            pyusdx.balanceOf(david);

        assertTrue(totalBalance <= pyusdx.totalSupply(), "Sum of balances exceeds totalSupply");
    }

    /* ============ Invariant: Earning Balance >= Principal ============ */

    function inv_earningBalanceGePrincipal() public view {
        // For earning accounts, balance should be >= earningPrincipal
        // (balance grows with yield, principal stays constant)

        address[] memory testAccounts = new address[](4);
        testAccounts[0] = alice;
        testAccounts[1] = bob;
        testAccounts[2] = carol;
        testAccounts[3] = david;

        for (uint256 i = 0; i < testAccounts.length; i++) {
            (uint32 earnerRate_, , ) = pyusdx.getAccountEarningInfo(testAccounts[i]);
            if (earnerRate_ > 0) {
                uint256 balance = pyusdx.balanceOf(testAccounts[i]);
                uint112 principal = pyusdx.earningPrincipalOf(testAccounts[i]);

                assertTrue(balance >= principal, "Earning balance less than principal");
            }
        }
    }

    /* ============ Invariant Handlers ============ */

    // TODO: improve invariant testing by adding more handlers for different state-changing actions
    function inv_mintPreservesTotalSupply() public {
        uint256 amount = 100e6; // Fixed amount for invariant testing

        uint256 totalSupplyBefore = pyusdx.totalSupply();

        // Mint to non-earning account
        minterGateway.mint(alice, amount);

        // Check invariants still hold
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + amount, "Total supply increased by amount");

        inv_totalSupplyGeSumOfBalances();
    }
}
