// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IFreezable } from "../../lib/m-extensions/src/components/freezable/IFreezable.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";
import { PausableUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXIntegrationTests is PYUSDXBaseUnitTest {
    uint256 public constant MINT_AMOUNT = 100e6; // 100 PYUSDX
    uint256 public constant BURN_AMOUNT = 50e6; // 50 PYUSDX

    /* ============ Mint + Freeze Integration ============ */

    function testIntegration_mintThenFreezeThenMintReverts() public {
        // Mint to alice
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);

        // Freeze alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);
        assertTrue(pyusdx.isFrozen(alice));

        // Try to mint again - should revert
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        minterGateway.mint(alice, MINT_AMOUNT);
    }

    function testIntegration_freezeThenUnfreezeThenMint() public {
        // Freeze alice first
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Mint should fail
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        minterGateway.mint(alice, MINT_AMOUNT);

        // Unfreeze alice
        vm.prank(freezeManager);
        pyusdx.unfreeze(alice);
        assertFalse(pyusdx.isFrozen(alice));

        // Now mint should succeed
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
    }

    /* ============ Mint + Pause Integration ============ */

    function testIntegration_pauseThenMintReverts() public {
        // Pause the contract
        vm.prank(pauser);
        pyusdx.pause();

        // Mint should revert
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minterGateway.mint(alice, MINT_AMOUNT);

        // Unpause
        vm.prank(pauser);
        pyusdx.unpause();

        // Mint should now succeed
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
    }

    /* ============ Multi-User Integration ============ */

    function testIntegration_mintToMultipleAccounts() public {
        uint256 totalMinted = 0;

        // Mint to multiple accounts
        minterGateway.mint(alice, MINT_AMOUNT);
        totalMinted += MINT_AMOUNT;

        minterGateway.mint(bob, MINT_AMOUNT * 2);
        totalMinted += MINT_AMOUNT * 2;

        minterGateway.mint(carol, MINT_AMOUNT * 3);
        totalMinted += MINT_AMOUNT * 3;

        minterGateway.mint(david, MINT_AMOUNT * 4);
        totalMinted += MINT_AMOUNT * 4;

        // Verify all balances
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), MINT_AMOUNT * 2);
        assertEq(pyusdx.balanceOf(carol), MINT_AMOUNT * 3);
        assertEq(pyusdx.balanceOf(david), MINT_AMOUNT * 4);

        // Verify totals
        assertEq(pyusdx.totalSupply(), totalMinted);
    }

    /* ============ Large Scale Integration ============ */

    function testIntegration_manySequentialMints() public {
        uint256 totalAmount = 0;
        uint256 numMints = 100;

        for (uint256 i = 0; i < numMints; i++) {
            uint256 mintAmount = (i + 1) * 1000;
            minterGateway.mint(alice, mintAmount);
            totalAmount += mintAmount;
        }

        assertEq(pyusdx.balanceOf(alice), totalAmount);
        assertEq(pyusdx.totalSupply(), totalAmount);
    }

    /* ============ Edge Case Integration ============ */

    function testIntegration_mintToSameAccountAcrossTime() public {
        uint256 balanceBefore;
        uint256 mintedTotal;

        for (uint256 i = 0; i < 10; i++) {
            balanceBefore = pyusdx.balanceOf(alice);

            vm.warp(i * 30 days); // Warp 30 days at a time

            minterGateway.mint(alice, MINT_AMOUNT);
            mintedTotal += MINT_AMOUNT;

            assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        }

        assertEq(pyusdx.balanceOf(alice), mintedTotal);
    }

    /* ============ Burn + Freeze Integration ============ */

    function testIntegration_burnThenFreezeThenBurnReverts() public {
        minterGateway.mint(alice, MINT_AMOUNT * 2);
        minterGateway.burn(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);

        // Freeze alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);
        assertTrue(pyusdx.isFrozen(alice));

        // Second burn should revert
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        minterGateway.burn(alice, MINT_AMOUNT);
    }

    function testIntegration_freezeThenBurnReverts() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        // Freeze alice first
        vm.prank(freezeManager);
        pyusdx.freeze(alice);
        assertTrue(pyusdx.isFrozen(alice));

        // Burn should revert
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        minterGateway.burn(alice, MINT_AMOUNT);
    }

    function testIntegration_freezeThenUnfreezeThenBurn() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        // Freeze alice first
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Burn should fail
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        minterGateway.burn(alice, MINT_AMOUNT);

        // Unfreeze alice
        vm.prank(freezeManager);
        pyusdx.unfreeze(alice);
        assertFalse(pyusdx.isFrozen(alice));

        // Now burn should succeed
        minterGateway.burn(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), 0);
    }

    /* ============ Burn + Pause Integration ============ */

    function testIntegration_pauseThenBurnReverts() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        // Pause the contract
        vm.prank(pauser);
        pyusdx.pause();

        // Burn should revert
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minterGateway.burn(alice, MINT_AMOUNT);

        // Unpause
        vm.prank(pauser);
        pyusdx.unpause();

        // Burn should now succeed
        minterGateway.burn(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), 0);
    }

    /* ============ Burn + Rate Manager Integration ============ */

    function testIntegration_burnWithIndexGrowth() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(1000));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Warp forward to grow index
        vm.warp(365 days);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        assertTrue(principalBefore > 0);

        // Burn triggers index update
        minterGateway.burn(alice, BURN_AMOUNT);

        assertTrue(pyusdx.earningPrincipalOf(alice) < principalBefore);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT - BURN_AMOUNT);
    }

    /* ============ Multi-User Burn Integration ============ */

    function testIntegration_mintBurnMultipleAccounts() public {
        // Mint to multiple accounts
        minterGateway.mint(alice, MINT_AMOUNT);
        minterGateway.mint(bob, MINT_AMOUNT * 2);
        minterGateway.mint(carol, MINT_AMOUNT * 3);

        uint256 totalSupply = pyusdx.totalSupply();
        assertEq(totalSupply, MINT_AMOUNT * 6);

        // Verify all balances
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), MINT_AMOUNT * 2);
        assertEq(pyusdx.balanceOf(carol), MINT_AMOUNT * 3);

        // Burn from multiple accounts
        minterGateway.burn(alice, MINT_AMOUNT);
        minterGateway.burn(bob, MINT_AMOUNT * 2);
        minterGateway.burn(carol, MINT_AMOUNT * 3);

        // Verify all balances are zero
        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(bob), 0);
        assertEq(pyusdx.balanceOf(carol), 0);
        assertEq(pyusdx.totalSupply(), 0);
    }

    /* ============ Mint/Burn Cycle Integration ============ */

    function testIntegration_mintThenBurn() public {
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        // Mint
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + MINT_AMOUNT);

        // Burn
        minterGateway.burn(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function testIntegration_mintBurnEarningWithYield() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(1000));

        minterGateway.mint(alice, MINT_AMOUNT);
        uint112 principalAfterMint = pyusdx.earningPrincipalOf(alice);

        vm.warp(365 days);

        minterGateway.burn(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), 0);

        assertTrue(pyusdx.earningPrincipalOf(alice) != 0);
        assertTrue(pyusdx.earningPrincipalOf(alice) < principalAfterMint);
    }

    function testIntegration_partialBurnFullBurn() public {
        minterGateway.mint(alice, MINT_AMOUNT * 10);

        // Partial burn
        minterGateway.burn(alice, MINT_AMOUNT * 3);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT * 7);

        // Full burn
        minterGateway.burn(alice, MINT_AMOUNT * 7);
        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.totalSupply(), 0);
    }

    /* ============ Large Scale Burn Integration ============ */

    function testIntegration_manySequentialBurns() public {
        uint256 numBurns = 100;
        uint256 totalAmount = 0;

        // Calculate total amount needed
        for (uint256 i = 0; i < numBurns; i++) {
            totalAmount += (i + 1) * 1000;
        }

        // Mint total amount first
        minterGateway.mint(alice, totalAmount);
        assertEq(pyusdx.balanceOf(alice), totalAmount);

        // Burn in sequence
        for (uint256 i = 0; i < numBurns; i++) {
            minterGateway.burn(alice, (i + 1) * 1000);
        }

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.totalSupply(), 0);
    }

    /* ============ Burn with Index Changes Integration ============ */

    function testIntegration_burnWithMultipleIndexUpdates() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        // Initial mint
        minterGateway.mint(alice, MINT_AMOUNT);

        // Multiple index updates via operations over time
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(30 days);
            minterGateway.mint(alice, MINT_AMOUNT);
        }

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        assertTrue(balanceBefore > 0);

        // Final burn
        minterGateway.burn(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore - MINT_AMOUNT);

        // Principal tracking remains consistent
        assertTrue(pyusdx.earningPrincipalOf(alice) > 0);
    }

    /* ============ Per-Earner Yield Lifecycle Integration ============ */

    function testIntegration_perEarnerYieldLifecycle() public {
        // Mint to alice
        uint256 initialBalance = 1000e6;
        minterGateway.mint(alice, initialBalance);
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
