// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IFreezable } from "../../lib/m-extensions/src/components/freezable/IFreezable.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";
import { PausableUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXIntegrationTests is PYUSDXBaseUnitTest {
    uint256 public constant MINT_AMOUNT = 100e6; // 100 PYUSDX

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

    /* ============ Mint + Rate Manager Integration ============ */

    function testIntegration_setRateThenMint() public {
        // Set a yield rate
        vm.prank(rateManager);
        pyusdx.setRate(500); // 5% APY

        assertEq(pyusdx.rate(), 500);

        // Mint should still work
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);

        // Index should have been updated
        uint128 index = pyusdx.currentIndex();
        assertTrue(index >= 1e12);
    }

    function testIntegration_mintWithIndexGrowth() public {
        // Set a yield rate
        vm.prank(rateManager);
        pyusdx.setRate(1000); // 10% APY

        uint128 indexBefore = pyusdx.currentIndex();
        assertEq(indexBefore, 1e12);

        // Warp forward to grow index
        vm.warp(365 days);

        // Mint triggers index update
        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 indexAfter = pyusdx.currentIndex();
        assertTrue(indexAfter > indexBefore);
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
        assertEq(pyusdx.totalNonEarningSupply(), uint240(totalMinted));
    }

    /* ============ Role-Based Integration ============ */

    function testIntegration_freezeManagerCanFreezeMidMint() public {
        // Start minting to alice
        minterGateway.mint(alice, MINT_AMOUNT);

        // Freeze manager freezes alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Second mint should fail
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        minterGateway.mint(alice, MINT_AMOUNT);
    }

    function testIntegration_pauserCanPauseMidMint() public {
        // Start minting
        minterGateway.mint(alice, MINT_AMOUNT);

        // Pauser pauses contract
        vm.prank(pauser);
        pyusdx.pause();

        // Second mint should fail
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        minterGateway.mint(alice, MINT_AMOUNT);
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
        assertEq(pyusdx.totalNonEarningSupply(), uint240(totalAmount));
    }

    /* ============ Edge Case Integration ============ */

    function testIntegration_mintToSameAccountAcrossTime() public {
        // Set a rate so index can grow
        vm.prank(rateManager);
        pyusdx.setRate(500);

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
}
