// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

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
        pyusdx.setAccountInfo(alice, 500, 1000, bob);

        assertTrue(pyusdx.isEarning(alice));

        // Warp and verify yield accrued
        vm.warp(block.timestamp + 365 days);
        (uint256 yieldWithFee, uint256 expectedFee, uint256 expectedNetYield) = pyusdx.accruedYieldAndFeeOf(alice);
        assertGt(yieldWithFee, 0);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 earnerManagerBalanceBefore = pyusdx.balanceOf(earnerManager);

        pyusdx.claimFor(alice);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + expectedNetYield);
        assertEq(pyusdx.balanceOf(earnerManager), earnerManagerBalanceBefore + expectedFee);

        // Change rate to 10% by updating account info
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(alice, 1000, 1000, bob);

        // Warp, verify new yield accrued, claim again
        vm.warp(block.timestamp + 365 days);
        uint256 secondYield = pyusdx.accruedYieldOf(alice);
        assertGt(secondYield, 0);

        pyusdx.claimFor(alice);
        assertEq(pyusdx.accruedYieldOf(alice), 0);

        // Disable earning
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(alice, 0, 0, address(0));

        // Verify final state
        assertFalse(pyusdx.isEarning(alice));
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertGt(pyusdx.balanceOf(alice), 0);
    }
}
