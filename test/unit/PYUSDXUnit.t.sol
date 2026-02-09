// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/m-extensions/src/components/freezable/IFreezable.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";
import { PausableUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXUnitTests is PYUSDXBaseUnitTest {
    uint256 public constant MINT_AMOUNT = 100e6; // 100 PYUSDX (6 decimals)
    uint256 public constant BURN_AMOUNT = 50e6; // 50 PYUSDX (6 decimals)

    /* ============ mint ============ */

    function test_mint_revertIfCallerNotMinterGateway() public {
        vm.expectRevert(IPYUSDX.NotMinterGateway.selector);

        vm.prank(alice);
        pyusdx.mint(bob, MINT_AMOUNT);
    }

    function test_mint_revertIfPaused() public {
        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        minterGateway.mint(alice, MINT_AMOUNT);
    }

    function test_mint_revertIfZeroAmount() public {
        vm.expectRevert(IPYUSDX.ZeroAmount.selector);

        minterGateway.mint(alice, 0);
    }

    function test_mint_revertIfZeroAccount() public {
        vm.expectRevert(IPYUSDX.ZeroAccount.selector);

        minterGateway.mint(address(0), MINT_AMOUNT);
    }

    function test_mint_revertIfAccountFrozen() public {
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        minterGateway.mint(alice, MINT_AMOUNT);
    }

    function test_mint_nonEarningAccount() public {
        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();

        assertFalse(pyusdx.isEarning(alice));

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, MINT_AMOUNT);

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + MINT_AMOUNT);
        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningSupplyBefore + uint240(MINT_AMOUNT));
        assertEq(pyusdx.totalEarningSupply(), 0);
        assertEq(pyusdx.totalEarningPrincipal(), 0);
    }

    function test_mint_earningAccount() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        assertTrue(pyusdx.isEarning(alice));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();
        uint128 indexBefore = pyusdx.currentIndex();

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, MINT_AMOUNT);

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + MINT_AMOUNT);
        assertEq(pyusdx.totalNonEarningSupply(), 0);

        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexBefore);
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore + expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipal);
    }

    function testFuzz_mint_earningAccount(uint256 amount) public {
        uint256 boundedAmount = bound(amount, 1, uint256(type(uint112).max) - 1);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + boundedAmount);

        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
    }

    function test_mint_earningAccount_withIndexGrowth() public {
        vm.prank(rateManager);
        pyusdx.setRate(500); // 5% APY

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint128 indexBefore = pyusdx.currentIndex();

        vm.warp(365 days);

        uint128 indexAfterWarp = pyusdx.currentIndex();
        assertTrue(indexAfterWarp > indexBefore);

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 indexAfterMint = pyusdx.currentIndex();
        assertTrue(indexAfterMint >= indexAfterWarp);
    }

    function test_mint_maxSafeAmount_nonEarning() public {
        // The maximum safe amount is limited by the principal calculation overflow
        // Principal = presentAmount * PRECISION / index
        // To avoid uint112 overflow (>= check), presentAmount must be < type(uint112).max when index >= PRECISION
        uint112 maxPrincipal = type(uint112).max;
        uint240 maxSafeAmount = uint240(maxPrincipal) - 1; // -1 because check uses >=

        minterGateway.mint(alice, uint256(maxSafeAmount));

        assertEq(pyusdx.balanceOf(alice), uint256(maxSafeAmount));
        assertEq(pyusdx.totalNonEarningSupply(), maxSafeAmount);
    }

    function test_mint_revertIfOverflowsPrincipalOfTotalSupply_nonEarning() public {
        // Mint near the maximum safe amount first
        uint112 maxPrincipal = type(uint112).max;
        uint240 maxSafeAmount = uint240(maxPrincipal) - 1; // -1 because check uses >=

        minterGateway.mint(alice, uint256(maxSafeAmount));

        // Now try to mint more - should revert
        vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        minterGateway.mint(bob, 1);
    }

    function test_mint_revertIfOverflowsPrincipalOfTotalSupply_earning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set total earning principal near max
        uint112 maxPrincipal = type(uint112).max;
        pyusdx.setTotalEarningPrincipal(maxPrincipal - 1);

        // Try to mint - should revert due to principal overflow
        vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        minterGateway.mint(alice, 1);
    }

    function test_mint_overflow_edgeCase() public {
        // Test the boundary where totalNonEarningSupply is near maximum safe amount
        uint112 maxPrincipal = type(uint112).max;
        uint240 maxSafeAmount = uint240(maxPrincipal) - 1; // -1 because check uses >=

        minterGateway.mint(alice, uint256(maxSafeAmount));

        assertEq(pyusdx.totalNonEarningSupply(), maxSafeAmount);

        // Trying to mint even 1 more should revert
        vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        minterGateway.mint(alice, 1);
    }

    function test_mint_nonEarningToEarning_transition() public {
        // Mint to alice as non-earning
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Set alice as earning
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        assertTrue(pyusdx.isEarning(alice));

        // Mint again - should now go to earning balance
        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);

        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
    }

    function test_mint_earningToNonEarning_transition() public {
        // Set alice as earning first
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Mint to alice as earning
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();
        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexBefore);

        assertEq(principalBefore, expectedPrincipal);

        // Set alice as non-earning
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, address(0), 0, address(0));

        assertFalse(pyusdx.isEarning(alice));

        // Principal should be reset to 0 when transitioning to non-earning
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Mint again - should now go to non-earning balance
        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
    }

    /* ============ burn ============ */

    function test_burn_revertIfCallerNotMinterGateway() public {
        vm.expectRevert(IPYUSDX.NotMinterGateway.selector);

        vm.prank(alice);
        pyusdx.burn(bob, BURN_AMOUNT);
    }

    function test_burn_revertIfPaused() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        minterGateway.burn(alice, BURN_AMOUNT);
    }

    function test_burn_revertIfZeroAmount() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.expectRevert(IPYUSDX.ZeroAmount.selector);

        minterGateway.burn(alice, 0);
    }

    function test_burn_revertIfAccountFrozen() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        minterGateway.burn(alice, BURN_AMOUNT);
    }

    function test_burn_revertIfInsufficientBalance() public {
        minterGateway.mint(alice, 100e6);

        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, 100e6, 101e6));

        minterGateway.burn(alice, 101e6);
    }

    function test_burn_nonEarningAccount() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();

        assertFalse(pyusdx.isEarning(alice));

        vm.expectEmit();
        emit IERC20.Transfer(alice, address(0), BURN_AMOUNT);

        minterGateway.burn(alice, BURN_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore - BURN_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore - BURN_AMOUNT);
        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningSupplyBefore - uint240(BURN_AMOUNT));
        assertEq(pyusdx.totalEarningSupply(), 0);
        assertEq(pyusdx.totalEarningPrincipal(), 0);
    }

    function test_burn_earningAccount() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        assertTrue(pyusdx.isEarning(alice));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        vm.expectEmit();
        emit IERC20.Transfer(alice, address(0), BURN_AMOUNT);

        minterGateway.burn(alice, BURN_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore - BURN_AMOUNT);
        assertEq(pyusdx.totalNonEarningSupply(), 0);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexBefore);
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore - expectedPrincipalSubtracted);

        uint112 expectedPrincipalAfter = principalBefore - expectedPrincipalSubtracted;
        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
    }

    function testFuzz_burn_earningAccount(uint256 amount) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, 1e15); // Reasonable bound to avoid overflow

        // Mint enough to cover the burn
        minterGateway.mint(alice, 1e18);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.burn(alice, boundedAmount);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(boundedAmount, indexBefore);
        uint112 expectedPrincipalAfter = principalBefore - expectedPrincipalSubtracted;
        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
    }

    function test_burn_earningAccount_withIndexGrowth() public {
        vm.prank(rateManager);
        pyusdx.setRate(500); // 5% APY

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 indexBefore = pyusdx.currentIndex();

        vm.warp(365 days);

        uint128 indexAfterWarp = pyusdx.currentIndex();
        assertTrue(indexAfterWarp > indexBefore);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        uint128 indexAfterBurn = pyusdx.currentIndex();
        assertTrue(indexAfterBurn >= indexAfterWarp);

        // Principal was subtracted using indexAfterWarp (before updateIndex)
        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexAfterWarp);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipalSubtracted);
    }

    function test_burn_fullBalance() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 fullBalance = pyusdx.balanceOf(alice);

        minterGateway.burn(alice, fullBalance);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.totalSupply(), 0);
    }

    function test_burn_fullBalance_earning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 fullBalance = pyusdx.balanceOf(alice);

        minterGateway.burn(alice, fullBalance);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertEq(pyusdx.totalEarningPrincipal(), 0);
    }

    function test_burn_earningAccount_principalRoundedUp() public {
        vm.prank(rateManager);
        pyusdx.setRate(1000); // 10% APY

        vm.warp(365 days);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 index = pyusdx.currentIndex();
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        uint112 principalSubtracted = principalBefore - pyusdx.earningPrincipalOf(alice);

        // Calculate both rounded down and up
        uint112 principalRoundedDown = _getExpectedPrincipal(BURN_AMOUNT, index);
        uint112 principalRoundedUp = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, index);

        // Verify we used rounded up (protocol-favoring)
        assertEq(principalSubtracted, principalRoundedUp);
        assertTrue(principalSubtracted >= principalRoundedDown);
    }

    function test_burn_nonEarningToEarning_transition() public {
        // Mint as non-earning
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Set alice as earning
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        assertTrue(pyusdx.isEarning(alice));

        // Mint again as earning
        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);

        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);

        // Now burn - should burn from earning balance (entire balance is earning now)
        uint112 principalBeforeBurn = pyusdx.earningPrincipalOf(alice);
        uint128 indexBeforeBurn = pyusdx.currentIndex();

        minterGateway.burn(alice, BURN_AMOUNT);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexBeforeBurn);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBeforeBurn - expectedPrincipalSubtracted);
    }

    function test_burn_earningAccount_principalUnderflowProtection() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Manually set earning principal to a low value to test underflow protection
        pyusdx.setEarningPrincipal(alice, 100);
        pyusdx.setTotalEarningPrincipal(100);

        // Burn amount that would require more principal than available
        // This should NOT revert - instead min112 caps the subtraction
        minterGateway.burn(alice, BURN_AMOUNT);

        // Principal should be capped at 0, not underflow
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertEq(pyusdx.totalEarningPrincipal(), 0);

        // Balance should still decrease
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT - BURN_AMOUNT);
    }
}
