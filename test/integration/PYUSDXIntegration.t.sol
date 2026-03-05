// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

contract PYUSDXIntegrationTests is IntegrationForkTest {
    /* ============ Per-Earner Yield Lifecycle Integration ============ */

    function testIntegration_perEarnerYieldLifecycle() public {
        // Mint to alice
        uint256 initialBalance = 1000e6;
        _mintPYUSDX(alice, initialBalance);
        assertEq(pyusdx.balanceOf(alice), initialBalance);

        // Enable earning with 10% fee, bob as claim recipient
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        assertTrue(pyusdx.isEarning(alice));

        // Set rate via public setEarnerRate
        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);

        // Warp and verify yield accrued
        vm.warp(block.timestamp + 365 days);
        uint240 accruedYield = pyusdx.accruedYieldOf(alice);
        assertGt(accruedYield, 0);

        // Claim — verify fee to earnerManager, net yield to bob, alice balance unchanged
        uint240 expectedFee = uint240((uint256(accruedYield) * 1000) / 10_000);
        uint240 expectedNetYield = accruedYield - expectedFee;

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 earnerManagerBalanceBefore = pyusdx.balanceOf(earnerManager);

        pyusdx.claimFor(alice);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + expectedNetYield);
        assertEq(pyusdx.balanceOf(earnerManager), earnerManagerBalanceBefore + expectedFee);

        // Change rate to 10%
        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 1000);

        // Warp, verify new yield accrued, claim again
        vm.warp(block.timestamp + 365 days);
        uint240 secondYield = pyusdx.accruedYieldOf(alice);
        assertGt(secondYield, 0);

        pyusdx.claimFor(alice);
        assertEq(pyusdx.accruedYieldOf(alice), 0);

        // Disable earning
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 0, address(0));

        // Verify final state
        assertFalse(pyusdx.isEarning(alice));
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertGt(pyusdx.balanceOf(alice), 0);
    }
}
