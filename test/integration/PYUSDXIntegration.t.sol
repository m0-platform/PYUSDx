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

    /* ============ Freeze + _claimFor(forFreeze=true) Integration ============ */

    function testIntegration_freeze_whilePaused_forceTransfer() public {
        uint256 initialBalance = 1000e6;
        _mintPYUSDX(alice, initialBalance);

        // Enable earning with 10% fee, bob as claim recipient
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(alice, 500, 1000, bob);

        // Warp to accrue yield
        vm.warp(block.timestamp + 365 days);

        (uint256 yieldWithFee, , ) = pyusdx.accruedYieldAndFeeOf(alice);
        assertGt(yieldWithFee, 0);

        uint256 expectedTotal = initialBalance + yieldWithFee;

        // Pause the contract
        vm.prank(pauser);
        pyusdx.pause();

        // Freeze while paused — _claimFor skips _transfer, yield materialized on alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));
        assertEq(pyusdx.balanceOf(alice), expectedTotal);

        // forceTransfer the full balance (principal + yield) to carol
        uint256 carolBalanceBefore = pyusdx.balanceOf(carol);

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, carol, expectedTotal);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(carol), carolBalanceBefore + expectedTotal);
    }

    function testIntegration_freeze_frozenRecipient_forceTransfer() public {
        uint256 initialBalance = 1000e6;
        _mintPYUSDX(alice, initialBalance);

        // Enable earning with 10% fee, bob as claim recipient
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(alice, 500, 1000, bob);

        // Warp to accrue yield
        vm.warp(block.timestamp + 365 days);

        (uint256 yieldWithFee, , ) = pyusdx.accruedYieldAndFeeOf(alice);
        assertGt(yieldWithFee, 0);

        uint256 expectedTotal = initialBalance + yieldWithFee;

        // Freeze bob (the claim recipient) first
        vm.prank(freezeManager);
        pyusdx.freeze(bob);

        assertTrue(pyusdx.isFrozen(bob));

        // Freeze alice — _claimFor skips _transfer to frozen bob, all yield stays on alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));
        assertEq(pyusdx.balanceOf(alice), expectedTotal);

        // forceTransfer the full balance (principal + yield) to carol
        uint256 carolBalanceBefore = pyusdx.balanceOf(carol);

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, carol, expectedTotal);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(carol), carolBalanceBefore + expectedTotal);
    }

    function testIntegration_freezeAccounts_batch_yieldMaterialized() public {
        uint256 initialBalance = 1000e6;

        // Mint to alice and carol
        _mintPYUSDX(alice, initialBalance);
        _mintPYUSDX(carol, initialBalance);

        // Alice: earner with fee and claim recipient (bob)
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(alice, 500, 1000, bob);

        // Carol: earner with no fee, no claim recipient
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(carol, 500, 0, address(0));

        // Warp to accrue yield
        vm.warp(block.timestamp + 365 days);

        (uint256 aliceYieldWithFee, , ) = pyusdx.accruedYieldAndFeeOf(alice);
        uint256 carolYield = pyusdx.accruedYieldOf(carol);

        assertGt(aliceYieldWithFee, 0);
        assertGt(carolYield, 0);

        uint256 aliceExpectedTotal = initialBalance + aliceYieldWithFee;
        uint256 carolExpectedTotal = initialBalance + carolYield;

        // Batch freeze both accounts
        address[] memory accountsToFreeze = new address[](2);
        accountsToFreeze[0] = alice;
        accountsToFreeze[1] = carol;

        vm.prank(freezeManager);
        pyusdx.freezeAccounts(accountsToFreeze);

        assertTrue(pyusdx.isFrozen(alice));
        assertTrue(pyusdx.isFrozen(carol));

        // Verify yield materialized on each account (no routing to recipients/fee)
        assertEq(pyusdx.balanceOf(alice), aliceExpectedTotal);
        assertEq(pyusdx.balanceOf(carol), carolExpectedTotal);

        // Earning should be stopped for both
        assertFalse(pyusdx.isEarning(alice));
        assertFalse(pyusdx.isEarning(carol));

        // forceTransfer from both frozen accounts to david
        uint256 davidBalanceBefore = pyusdx.balanceOf(david);

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, david, aliceExpectedTotal);

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(carol, david, carolExpectedTotal);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(carol), 0);
        assertEq(pyusdx.balanceOf(david), davidBalanceBefore + aliceExpectedTotal + carolExpectedTotal);
    }
}
