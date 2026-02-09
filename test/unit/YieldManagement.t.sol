// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { PausableUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { IFreezable } from "../../lib/m-extensions/src/components/freezable/IFreezable.sol";
import { IndexingMath } from "../../lib/m-extensions/lib/common/src/libs/IndexingMath.sol";

import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";
import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract YieldManagementTest is PYUSDXBaseUnitTest {
    event Transfer(address indexed from, address indexed to, uint256 value);

    /* ============ accruedYieldOf ============ */

    function test_accruedYieldOf_nonEarner() public view {
        uint240 yield = pyusdx.accruedYieldOf(alice);
        assertEq(yield, 0, "Non-earner should have 0 accrued yield");
    }

    function test_accruedYieldOf_earner() public {
        // Set a rate so index grows over time
        vm.prank(rateManager);
        pyusdx.setRate(500);

        // Mint tokens to alice first (as non-earner)
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        // Set up alice as an earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        // Warp time to accrue yield
        vm.warp(block.timestamp + 365 days);

        // Calculate expected yield
        uint128 index = pyusdx.currentIndex();
        uint112 principal = pyusdx.earningPrincipalOf(alice);
        uint240 expectedBalanceWithYield = IndexingMath.getPresentAmountRoundedDown(principal, index);
        uint240 expectedYield = expectedBalanceWithYield > uint240(balance)
            ? expectedBalanceWithYield - uint240(balance)
            : 0;

        // Verify yield calculation
        uint240 actualYield = pyusdx.accruedYieldOf(alice);
        assertEq(actualYield, expectedYield, "Accrued yield should match expected");
        assertGt(actualYield, 0, "Should have positive yield after time passes");
    }

    /* ============ balanceWithYieldOf ============ */

    function test_balanceWithYieldOf() public {
        // Set a rate so index grows over time
        vm.prank(rateManager);
        pyusdx.setRate(500);

        // Mint tokens to alice first (as non-earner)
        minterGateway.mint(alice, 1000e6);

        // Set up alice as an earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.warp(block.timestamp + 365 days);

        uint256 balanceWithYield = pyusdx.balanceWithYieldOf(alice);
        uint256 expectedBalance = pyusdx.balanceOf(alice) + pyusdx.accruedYieldOf(alice);

        assertEq(balanceWithYield, expectedBalance, "balanceWithYieldOf should equal balance + accruedYield");
    }

    /* ============ claimFor ============ */

    function test_claimFor_happyPath() public {
        vm.prank(rateManager);
        pyusdx.setRate(500);

        // Mint tokens to alice first (as non-earner)
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        // Set up alice as an earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.warp(block.timestamp + 365 days);

        uint240 expectedYield = pyusdx.accruedYieldOf(alice);
        assertGt(expectedYield, 0, "Should have yield to claim");

        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 balanceBefore = pyusdx.balanceOf(alice);

        vm.expectEmit();
        emit IPYUSDX.Claimed(alice, alice, expectedYield);

        vm.expectEmit();
        emit Transfer(address(0), alice, expectedYield);

        uint240 claimed = pyusdx.claimFor(alice);

        assertEq(claimed, expectedYield, "Should return claimed yield");
        // Note: totalSupply doesn't change because yield was already included in totalEarningSupply (calculated from principal * index)
        assertEq(
            pyusdx.totalSupply(),
            totalSupplyBefore,
            "Total supply should remain unchanged (yield already in totalEarningSupply)"
        );
        assertEq(pyusdx.balanceOf(alice), balanceBefore + expectedYield, "balanceOf should increase by yield");
        assertEq(pyusdx.accruedYieldOf(alice), 0, "Accrued yield should be 0 after claim");
    }

    function test_claimFor_revert_whenPaused() public {
        // Mint tokens to alice first (as non-earner)
        minterGateway.mint(alice, 1000e6);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        pyusdx.claimFor(alice);
    }

    function test_claimFor_revert_whenFrozen() public {
        // Mint tokens to alice first (as non-earner)
        minterGateway.mint(alice, 1000e6);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        pyusdx.claimFor(alice);
    }
}
