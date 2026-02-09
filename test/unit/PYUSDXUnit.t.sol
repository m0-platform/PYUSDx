// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/m-extensions/src/components/freezable/IFreezable.sol";
import { IForcedTransferable } from "../../lib/m-extensions/src/components/forcedTransferable/IForcedTransferable.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";
import { PausableUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { UIntMath } from "../../lib/m-extensions/lib/common/src/libs/UIntMath.sol";
import { IndexingMath } from "../../lib/m-extensions/lib/common/src/libs/IndexingMath.sol";
import { VmSafe } from "../../lib/m-extensions/lib/forge-std/src/Vm.sol";

import { IContinuousIndexing } from "../../src/interfaces/IContinuousIndexing.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXUnitTests is PYUSDXBaseUnitTest {
    event Transfer(address indexed from, address indexed to, uint256 value);

    uint256 public constant MINT_AMOUNT = 100e6; // 100 PYUSDX (6 decimals)
    uint256 public constant BURN_AMOUNT = 50e6; // 50 PYUSDX (6 decimals)
    uint256 public constant TRANSFER_AMOUNT = 30e6; // 30 PYUSDX (6 decimals)

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

    function testFuzz_mint_earningAccount(uint256 amount, uint128 index, uint32 rate) public {
        uint256 boundedAmount = bound(amount, 1, uint256(type(uint112).max) - 1);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));
        uint32 boundedRate = uint32(bound(rate, 0, MAX_FEE_RATE));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        pyusdx.setLatestIndex(boundedIndex);
        pyusdx.setLatestRate(boundedRate);

        minterGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + boundedAmount);

        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, boundedIndex);
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

    function testFuzz_burn_earningAccount(uint256 amount, uint128 index, uint32 rate) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedMintAmount = bound(amount, 1, uint256(type(uint112).max) - 1);
        uint256 boundedBurnAmount = bound(amount, 1, boundedMintAmount);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));
        uint32 boundedRate = uint32(bound(rate, 0, MAX_FEE_RATE));

        pyusdx.setLatestIndex(boundedIndex);
        pyusdx.setLatestRate(boundedRate);

        minterGateway.mint(alice, boundedMintAmount);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, boundedBurnAmount);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(boundedBurnAmount, boundedIndex);
        uint112 expectedPrincipalAfter = principalBefore -
            UIntMath.min112(principalBefore, expectedPrincipalSubtracted);

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

    /* ============ transfer ============ */

    function test_transfer_revertIfPaused() public {
        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_transfer_revertIfFrozen_sender() public {
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_transfer_revertIfFrozen_recipient() public {
        vm.prank(freezeManager);
        pyusdx.freeze(bob);

        assertTrue(pyusdx.isFrozen(bob));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_transfer_revertIfFrozen_msgSender() public {
        // Approve carol to spend alice's tokens
        vm.prank(alice);
        pyusdx.approve(carol, TRANSFER_AMOUNT);

        vm.prank(freezeManager);
        pyusdx.freeze(carol);

        assertTrue(pyusdx.isFrozen(carol));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, carol));

        // Carol is the msg.sender in transferFrom
        vm.prank(carol);
        pyusdx.transferFrom(alice, bob, TRANSFER_AMOUNT);
    }

    function test_transfer_insufficientBalance() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, MINT_AMOUNT, MINT_AMOUNT + 1)
        );

        vm.prank(alice);
        pyusdx.transfer(bob, MINT_AMOUNT + 1);
    }

    function test_transfer_toZeroAddress() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.expectRevert(IPYUSDX.ZeroAccount.selector);

        vm.prank(alice);
        pyusdx.transfer(address(0), TRANSFER_AMOUNT);
    }

    function test_transfer_nonEarningToNonEarning() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + TRANSFER_AMOUNT);

        // Unchanged totals (in-kind transfer)
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningSupplyBefore);
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore);
    }

    function testFuzz_transfer_nonEarningToNonEarning(uint256 amount) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max - 1);

        minterGateway.mint(alice, boundedAmount);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - boundedAmount);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + boundedAmount);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_transfer_earningToEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();
        uint128 indexBefore = pyusdx.currentIndex();

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + TRANSFER_AMOUNT);

        // Principal transferred (rounded up)
        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);

        // Total earning principal unchanged (in-kind transfer)
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore);
    }

    function test_transfer_earningToEarning_withIndexGrowth() public {
        vm.prank(rateManager);
        pyusdx.setRate(500); // 5% APY

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 indexBefore = pyusdx.currentIndex();

        vm.warp(365 days);

        uint128 indexAfterWarp = pyusdx.currentIndex();
        assertTrue(indexAfterWarp > indexBefore);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        vm.expectEmit();
        emit IContinuousIndexing.IndexUpdated(indexAfterWarp, 500);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Principal calculated using indexAfterWarp (before updateIndex in _transfer)
        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, indexAfterWarp);
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
    }

    function testFuzz_transfer_earningToEarning(uint256 amount, uint128 index, uint32 rate) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max - 1);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));
        uint32 boundedRate = uint32(bound(rate, 0, MAX_FEE_RATE));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        pyusdx.setLatestIndex(boundedIndex);
        pyusdx.setLatestRate(boundedRate);

        minterGateway.mint(alice, boundedAmount);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        uint112 expectedPrincipal = UIntMath.min112(
            alicePrincipalBefore,
            _getExpectedPrincipalRoundedUp(boundedAmount, boundedIndex)
        );

        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore);
    }

    function test_transfer_nonEarningToEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();
        uint128 indexBefore = pyusdx.currentIndex();

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Non-earning supply decreased
        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningSupplyBefore - uint240(TRANSFER_AMOUNT));

        // Earning principal increased (rounded down - protocol-favoring)
        uint112 expectedPrincipal = _getExpectedPrincipal(TRANSFER_AMOUNT, indexBefore);
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore + expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), expectedPrincipal);
    }

    function test_transfer_earningToNonEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();
        uint128 indexBefore = pyusdx.currentIndex();

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Principal subtracted (rounded up - protocol-favoring)
        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipalSubtracted);

        // Totals updated
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningSupplyBefore + uint240(TRANSFER_AMOUNT));
    }

    function testFuzz_transfer_earningToNonEarning(uint256 amount, uint128 index, uint32 rate) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max - 1);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));
        uint32 boundedRate = uint32(bound(rate, 0, MAX_FEE_RATE));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        pyusdx.setLatestIndex(boundedIndex);
        pyusdx.setLatestRate(boundedRate);

        minterGateway.mint(alice, boundedAmount);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        uint112 expectedPrincipalSubtracted = UIntMath.min112(
            alicePrincipalBefore,
            _getExpectedPrincipalRoundedUp(boundedAmount, boundedIndex)
        );

        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningSupplyBefore + uint240(boundedAmount));
    }

    function test_transfer_toSelf() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();

        vm.expectEmit();
        emit IERC20.Transfer(alice, alice, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(alice, TRANSFER_AMOUNT);

        // Balance should be unchanged (subtracting and adding same amount)
        assertEq(pyusdx.balanceOf(alice), balanceBefore);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningSupplyBefore);
    }

    function test_transfer_zeroAmount() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, 0);

        vm.prank(alice);
        pyusdx.transfer(bob, 0);

        // Balances unchanged
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_transfer_fullBalance() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 fullBalance = pyusdx.balanceOf(alice);

        vm.prank(alice);
        pyusdx.transfer(bob, fullBalance);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(bob), fullBalance);
    }

    function test_transfer_fullBalance_earningToEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 fullBalance = pyusdx.balanceOf(alice);
        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);

        vm.prank(alice);
        pyusdx.transfer(bob, fullBalance);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(bob), fullBalance);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // All principal transferred to bob
        assertEq(pyusdx.earningPrincipalOf(bob), alicePrincipalBefore);
    }

    function test_transfer_earningToNonEarning_indexGrowth() public {
        vm.prank(rateManager);
        pyusdx.setRate(1000); // 10% APY

        vm.warp(365 days);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 index = pyusdx.currentIndex();
        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        uint112 principalSubtracted = alicePrincipalBefore - pyusdx.earningPrincipalOf(alice);

        // Calculate both rounded down and up
        uint112 principalRoundedDown = _getExpectedPrincipal(TRANSFER_AMOUNT, index);
        uint112 principalRoundedUp = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, index);

        // Verify we used rounded up (protocol-favoring)
        assertEq(principalSubtracted, principalRoundedUp);
        assertTrue(principalSubtracted >= principalRoundedDown);

        // Total earning principal decreased by rounded up amount
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore - principalRoundedUp);
    }

    function testFuzz_transfer_nonEarningToEarning(uint256 amount, uint128 index, uint32 rate) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max - 1);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));
        uint32 boundedRate = uint32(bound(rate, 0, MAX_FEE_RATE));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        pyusdx.setLatestIndex(boundedIndex);
        pyusdx.setLatestRate(boundedRate);

        minterGateway.mint(alice, boundedAmount);

        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, boundedIndex);

        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningSupplyBefore - uint240(boundedAmount));
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore + expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), expectedPrincipal);
    }

    /* ============ Index Boundary Unit Tests ============ */

    /* ============ 3.1 Index Initialization Tests ============ */

    function test_mint_earningAccount_atInitialIndex() public {
        // Verify index starts at PRECISION (1e12)
        assertEq(pyusdx.currentIndex(), PRECISION);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        // At initial index, principal should equal present amount
        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + MINT_AMOUNT);
        assertEq(pyusdx.currentIndex(), indexBefore); // Index unchanged at 1e12
    }

    function test_transfer_earningToEarning_atInitialIndex() public {
        assertEq(pyusdx.currentIndex(), PRECISION);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
        uint128 indexBefore = pyusdx.currentIndex();

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // At initial index, principal transfer should equal amount transferred
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + TRANSFER_AMOUNT);
        assertEq(pyusdx.currentIndex(), indexBefore);
    }

    function test_burn_earningAccount_atInitialIndex() public {
        assertEq(pyusdx.currentIndex(), PRECISION);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.burn(alice, BURN_AMOUNT);

        // At initial index, principal burned should equal amount burned
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - BURN_AMOUNT);
        assertEq(pyusdx.currentIndex(), indexBefore);
    }

    /* ============ 3.2 Precision Loss Tests ============ */

    function test_mint_earningAccount_smallAmount_highIndex() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set index to a high value (100x PRECISION)
        uint128 highIndex = PRECISION * 100;
        pyusdx.setLatestIndex(highIndex);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Mint small amount at high index
        // Principal = amount * PRECISION / index = amount * 1e12 / (100 * 1e12) = amount / 100
        minterGateway.mint(alice, 100); // 100 PYUSDX

        // At 100x index, 100 tokens should only add 1 principal (rounded down)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + 1);
        assertEq(pyusdx.balanceOf(alice), 100);
    }

    function test_mint_earningAccount_principalRoundsToZero() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set index to very high value
        uint128 veryHighIndex = PRECISION * 1000;
        pyusdx.setLatestIndex(veryHighIndex);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Mint amount that rounds to zero principal
        // Principal = 10 * 1e12 / (1000 * 1e12) = 0.01 -> rounds to 0
        minterGateway.mint(alice, 10);

        // Principal should be unchanged (rounded to zero)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore);
        assertEq(pyusdx.balanceOf(alice), 10);
    }

    function test_transfer_earningToEarning_smallAmount_highIndex() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set index to high value
        uint128 highIndex = PRECISION * 100;
        pyusdx.setLatestIndex(highIndex);

        // Mint enough to get some principal
        minterGateway.mint(alice, 10000);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        // Transfer small amount at high index (using rounded up)
        vm.prank(alice);
        pyusdx.transfer(bob, 100);

        // At 100x index: 100 tokens = 1 principal (rounded up from transfer)
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - 1);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + 1);
    }

    function test_burn_earningAccount_smallAmount_nearZeroPrincipal() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set index to high value (but not too high that principal rounds to zero on mint)
        uint128 highIndex = PRECISION * 100; // 100x index
        pyusdx.setLatestIndex(highIndex);

        // Mint amount that gives small principal: 1e6 * 1e12 / (100 * 1e12) = 10000
        minterGateway.mint(alice, 1e6);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint256 balanceBefore = pyusdx.balanceOf(alice);

        // Verify we got some principal
        assertGt(principalBefore, 0);

        // Burn small amount - principal should round up
        // Principal to burn = 10 * 1e12 / (100 * 1e12) = 0.1 -> rounds up to 1
        minterGateway.burn(alice, 10);

        // Principal should decrease by 1 (rounded up from 0.1)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - 1);
        assertEq(pyusdx.balanceOf(alice), balanceBefore - 10);
    }

    /* ============ 3.3 Extreme Index Tests ============ */

    function test_mint_earningAccount_after10YearsCompounding() public {
        vm.prank(rateManager);
        pyusdx.setRate(500); // 5% APY

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint128 indexBefore = pyusdx.currentIndex();

        // Warp 10 years
        vm.warp(365 days * 10);

        uint128 indexAfter10Years = pyusdx.currentIndex();
        assertTrue(indexAfter10Years > indexBefore);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);

        // Principal should be less than amount at higher index
        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexAfter10Years);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
        assertTrue(expectedPrincipal < MINT_AMOUNT);
    }

    function test_transfer_earningToEarning_after50Years() public {
        vm.prank(rateManager);
        pyusdx.setRate(1000); // 10% APY

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Warp 50 years
        vm.warp(365 days * 50);

        uint128 indexAfter50Years = pyusdx.currentIndex();
        assertTrue(indexAfter50Years > PRECISION);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Principal transferred should be less than amount at high index
        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, indexAfter50Years);

        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
        assertTrue(expectedPrincipal < TRANSFER_AMOUNT);
    }

    function test_burn_earningAccount_after100YearsMaxRate() public {
        vm.prank(rateManager);
        pyusdx.setRate(10000); // 100% APY (max)

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Warp 100 years (extreme compounding)
        vm.warp(365 days * 100);

        uint128 indexAfter100Years = pyusdx.currentIndex();

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        // Principal burned should be much less than amount at extreme index
        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexAfter100Years);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipal);
        assertTrue(expectedPrincipal < BURN_AMOUNT);
    }

    function test_index_growth_capsAtMax() public {
        vm.prank(rateManager);
        pyusdx.setRate(10000); // 100% APY (max)

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Warp far into the future to try to overflow index
        vm.warp(365 days * 1000);

        uint128 extremeIndex = pyusdx.currentIndex();

        // Index should be capped at type(uint128).max via bound128
        assertLe(extremeIndex, type(uint128).max);

        // Mint should still work
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
    }

    /* ============ 3.4 Rate Change Tests ============ */

    function test_mint_earningAccount_withRateChange() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set initial rate
        vm.prank(rateManager);
        pyusdx.setRate(500); // 5%

        // Warp to grow index
        vm.warp(365 days);
        uint128 indexAt5Percent = pyusdx.currentIndex();

        // Change rate
        vm.prank(rateManager);
        pyusdx.setRate(1000); // 10%

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Mint at new rate (index already updated by setRate)
        minterGateway.mint(alice, MINT_AMOUNT);

        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, pyusdx.currentIndex());
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);

        // Index should have grown
        assertTrue(pyusdx.currentIndex() >= indexAt5Percent);
    }

    function test_transfer_earningToEarning_withRateChange() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Set rate and warp
        vm.prank(rateManager);
        pyusdx.setRate(500);
        vm.warp(180 days);

        // Change rate mid-stream
        vm.prank(rateManager);
        pyusdx.setRate(2000); // 20%

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Transfer uses current index (which reflects both rates)
        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, pyusdx.currentIndex());
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
    }

    function test_burn_earningAccount_withRateChange() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Set rate and grow index
        vm.prank(rateManager);
        pyusdx.setRate(1000);
        vm.warp(365 days);

        uint128 indexBeforeRateChange = pyusdx.currentIndex();

        // Change rate to 0%
        vm.prank(rateManager);
        pyusdx.setRate(0);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        // Burn uses index after rate change
        uint128 indexAfterRateChange = pyusdx.currentIndex();
        assertTrue(indexAfterRateChange >= indexBeforeRateChange);

        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexAfterRateChange);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipal);
    }

    /* ============ 3.5 Rounding Invariant Tests ============ */

    function test_invariant_mint_principalMatchesRoundedDown() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Test at various index values
        uint128[4] memory indices = [PRECISION, PRECISION * 10, PRECISION * 100, PRECISION * 1000];

        for (uint256 i = 0; i < indices.length; i++) {
            pyusdx.setLatestIndex(indices[i]);

            uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
            uint128 indexBefore = pyusdx.currentIndex();

            minterGateway.mint(alice, MINT_AMOUNT);

            // Verify principal matches rounded down calculation
            uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(MINT_AMOUNT), indexBefore);
            assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
        }
    }

    function test_invariant_burn_principalMatchesRoundedUp() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Test at various index values
        uint128[4] memory indices = [PRECISION, PRECISION * 10, PRECISION * 100, PRECISION * 1000];

        for (uint256 i = 0; i < indices.length; i++) {
            pyusdx.setLatestIndex(indices[i]);

            minterGateway.mint(alice, MINT_AMOUNT);

            uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
            uint128 indexBefore = pyusdx.currentIndex();

            minterGateway.burn(alice, BURN_AMOUNT);

            // Verify principal subtracted matches rounded up calculation
            uint112 expectedPrincipal = _expectedPrincipalRoundUp(uint240(BURN_AMOUNT), indexBefore);
            assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipal);
        }
    }

    function test_invariant_transfer_principalMatchesRoundedUp() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Test at various index values
        uint128[4] memory indices = [PRECISION, PRECISION * 10, PRECISION * 100, PRECISION * 1000];

        for (uint256 i = 0; i < indices.length; i++) {
            pyusdx.setLatestIndex(indices[i]);

            minterGateway.mint(alice, MINT_AMOUNT);

            uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 indexBefore = pyusdx.currentIndex();

            vm.prank(alice);
            pyusdx.transfer(bob, TRANSFER_AMOUNT);

            // Verify principal transferred matches rounded up calculation
            uint112 expectedPrincipal = _expectedPrincipalRoundUp(uint240(TRANSFER_AMOUNT), indexBefore);
            assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
            assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
        }
    }

    function test_invariant_transfer_crossEarning_principalAsymmetry() public {
        // Test E->N and N->E paths to verify different rounding behavior
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index for visible rounding differences
        pyusdx.setLatestIndex(PRECISION * 100);

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 totalNonEarningBefore = pyusdx.totalNonEarningSupply();
        uint112 totalEarningPrincipalBefore = pyusdx.totalEarningPrincipal();
        uint128 index = pyusdx.currentIndex();

        // E->N transfer: subtract earning principal (rounded up), add non-earning (1:1)
        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Verify E->N uses rounded up for subtraction
        uint112 expectedPrincipalSubtracted = _expectedPrincipalRoundUp(uint240(TRANSFER_AMOUNT), index);
        assertEq(pyusdx.totalEarningPrincipal(), totalEarningPrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.totalNonEarningSupply(), totalNonEarningBefore + uint240(TRANSFER_AMOUNT));

        // Now test N->E with a different scenario
        // Mint to david as non-earning, then set him to earning, then transfer to carol
        minterGateway.mint(david, TRANSFER_AMOUNT);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(carol, true, earnerManager, 0, address(0));

        uint256 davidBalance = pyusdx.balanceOf(david);

        // David (non-earning) transfers to Carol (earning)
        vm.prank(david);
        pyusdx.transfer(carol, davidBalance);

        // N->E: subtract non-earning (1:1), add earning principal (rounded down)
        // Carol should get principal rounded down from the amount
        uint112 expectedPrincipalAdded = _expectedPrincipalRoundDown(uint240(davidBalance), index);
        assertEq(pyusdx.earningPrincipalOf(carol), expectedPrincipalAdded);
    }

    /* ============ Rounding Edge Case Tests ============ */

    /* ============ Principal Depletion Tests ============ */

    function test_burn_earningAccount_depletesPrincipal_nonZeroBalanceRemains() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index so small amounts give tiny principal
        pyusdx.setLatestIndex(PRECISION * 1000);

        // Mint enough to get some principal
        minterGateway.mint(alice, 1000);
        uint112 initialPrincipal = pyusdx.earningPrincipalOf(alice);
        assertTrue(initialPrincipal > 0);

        // Burn most of the balance, leaving some
        // Each burn rounds up principal, so we may drain principal before balance
        minterGateway.burn(alice, 500);

        uint256 balanceAfter = pyusdx.balanceOf(alice);
        uint112 principalAfter = pyusdx.earningPrincipalOf(alice);

        // We may have principal depletion (balance > 0 but principal = 0)
        // This is allowed due to rounding up in burns
        if (balanceAfter > 0 && principalAfter == 0) {
            // Principal depletion detected - this is expected behavior
            assertTrue(_hasPrincipalDepletion(alice));
        } else {
            // No depletion - principal should be consistent with balance at high index
            assertTrue(principalAfter <= initialPrincipal);
        }
    }

    function test_transfer_earningToEarning_depletesPrincipal() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index (100x, not 1000x to get some principal on mint)
        pyusdx.setLatestIndex(PRECISION * 100);

        // Mint small amount: 100 * 1e12 / (100 * 1e12) = 1 principal
        minterGateway.mint(alice, 100);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        assertEq(alicePrincipalBefore, 1); // Exactly 1 principal

        // Transfer at high index - principal subtracted rounds up
        // With 100x index: 100 tokens = 1 principal -> rounds up to 1
        vm.prank(alice);
        pyusdx.transfer(bob, 100);

        // Alice's principal should be 0 (depletion)
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertTrue(pyusdx.balanceOf(alice) == 0); // Full transfer

        // Bob should have received 1 principal (rounded up)
        assertEq(pyusdx.earningPrincipalOf(bob), 1);
        assertEq(pyusdx.balanceOf(bob), 100);
    }

    function test_transfer_crossEarning_depletesPrincipal() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index (100x, not 1000x to get some principal on mint)
        pyusdx.setLatestIndex(PRECISION * 100);

        // Mint small amount that gives small principal: 100 * 1e12 / (100 * 1e12) = 1
        minterGateway.mint(alice, 100);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        assertEq(principalBefore, 1); // Exactly 1 principal

        // Transfer to non-earning bob - E->N: principal subtracted (rounded up), bob gets non-earning 1:1
        vm.prank(alice);
        pyusdx.transfer(bob, 100);

        // Alice's principal should be depleted to 0 (since 100 * 1e12 / (100 * 1e12) = 1, rounded up)
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertEq(pyusdx.balanceOf(alice), 0);

        // Bob should have full balance as non-earning
        assertEq(pyusdx.balanceOf(bob), 100);
        assertEq(pyusdx.earningPrincipalOf(bob), 0);
    }

    /* ============ Repeated Operations Compound Rounding Tests ============ */

    function test_repeatedTransfers_principalConsistency() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(carol, true, earnerManager, 0, address(0));

        // Set high index for visible rounding
        pyusdx.setLatestIndex(PRECISION * 100);

        minterGateway.mint(alice, 1000);
        uint112 aliceInitialPrincipal = pyusdx.earningPrincipalOf(alice);

        // Transfer alice -> bob -> carol
        vm.prank(alice);
        pyusdx.transfer(bob, 500);

        uint112 bobPrincipal = pyusdx.earningPrincipalOf(bob);

        vm.prank(bob);
        pyusdx.transfer(carol, 500);

        uint112 carolPrincipal = pyusdx.earningPrincipalOf(carol);
        uint112 aliceFinalPrincipal = pyusdx.earningPrincipalOf(alice);

        // Total principal should be conserved (in-kind transfers don't change total)
        assertEq(pyusdx.totalEarningPrincipal(), aliceInitialPrincipal);

        // Carol should have received the rounded-up principal from bob
        assertTrue(carolPrincipal > 0);

        // Alice should have less principal
        assertTrue(aliceFinalPrincipal < aliceInitialPrincipal);
    }

    function test_repeatedMintBurn_principalConsistency() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set index
        pyusdx.setLatestIndex(PRECISION * 10);

        uint256 totalMinted = 0;
        uint256 totalBurned = 0;

        // Repeated mint/burn cycles
        for (uint256 i = 0; i < 10; i++) {
            minterGateway.mint(alice, 100);
            totalMinted += 100;

            minterGateway.burn(alice, 50);
            totalBurned += 50;
        }

        uint256 finalBalance = pyusdx.balanceOf(alice);
        uint112 finalPrincipal = pyusdx.earningPrincipalOf(alice);

        // Final balance should match net minted
        assertEq(finalBalance, totalMinted - totalBurned);

        // Principal should be positive (mint adds, burn subtracts)
        assertTrue(finalPrincipal > 0);
    }

    function test_repeatedMintTransfer_principalConsistency() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index
        pyusdx.setLatestIndex(PRECISION * 50);

        // Mint and transfer in cycles
        for (uint256 i = 0; i < 5; i++) {
            minterGateway.mint(alice, 100);

            vm.prank(alice);
            pyusdx.transfer(bob, 100);
        }

        // Bob should have all the balance
        assertEq(pyusdx.balanceOf(bob), 500);
        assertEq(pyusdx.balanceOf(alice), 0);

        // Bob should have some principal (accumulated from transfers)
        uint112 bobPrincipal = pyusdx.earningPrincipalOf(bob);
        assertTrue(bobPrincipal > 0);

        // At 50x index, 500 tokens ≈ 10 principal (rounded up per transfer)
        assertTrue(bobPrincipal >= 5); // At minimum
        assertTrue(bobPrincipal <= 10);
    }

    /* ============ Small Amounts at High Index Tests ============ */

    function test_mint_smallAmount_highIndex_principalRoundsToZero() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set extremely high index
        pyusdx.setLatestIndex(PRECISION * 10000);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Mint tiny amount
        // Principal = 1 * 1e12 / (10000 * 1e12) = 0.0001 -> rounds to 0
        minterGateway.mint(alice, 1);

        // Principal should be unchanged (rounded to zero)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore);
        assertEq(pyusdx.balanceOf(alice), 1);
    }

    function test_burn_smallAmount_highIndex_principalRoundsUp() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index (100x, not 1000x to avoid rounding to zero on mint)
        pyusdx.setLatestIndex(PRECISION * 100);

        // Mint larger amount to get principal: 1e6 * 1e12 / (100 * 1e12) = 10000
        minterGateway.mint(alice, 1e6);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Burn small amount - principal rounds up
        // Principal = 1 * 1e12 / (100 * 1e12) = 0.01 -> rounds up to 1
        minterGateway.burn(alice, 1);

        // Principal should decrease by 1 (rounded up)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - 1);
        assertEq(pyusdx.balanceOf(alice), 1e6 - 1);
    }

    function test_transfer_smallAmount_highIndex_roundingAsymmetry() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index (100x, not 1000x to avoid rounding to zero on mint)
        pyusdx.setLatestIndex(PRECISION * 100);

        // Mint larger amount to get principal: 1e6 * 1e12 / (100 * 1e12) = 10000
        minterGateway.mint(alice, 1e6);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        // Transfer small amount
        vm.prank(alice);
        pyusdx.transfer(bob, 10);

        // Principal should round up: 10 * 1e12 / (100 * 1e12) = 0.1 -> rounds up to 1
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - 1);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + 1);
        assertEq(pyusdx.balanceOf(bob), 10);
    }

    /* ============ Large Amounts at Low Index Tests ============ */

    function test_mint_largeAmount_lowIndex_principalOverflow() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // At low index (PRECISION), principal equals amount
        pyusdx.setLatestIndex(PRECISION);

        // Set total earning principal near max
        uint112 maxPrincipal = type(uint112).max;
        pyusdx.setTotalEarningPrincipal(maxPrincipal - 100);

        // Try to mint large amount - should revert due to overflow
        vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        minterGateway.mint(alice, 100);
    }

    function test_transfer_largeAmount_lowIndex_principalOverflow() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // At low index, principal equals amount
        pyusdx.setLatestIndex(PRECISION);

        // Set bob's principal near max
        pyusdx.setEarningPrincipal(bob, type(uint112).max - 50);

        // Mint and transfer large amount
        minterGateway.mint(alice, 100);

        // Transfer should revert - safe112 prevents overflow
        vm.expectRevert(); // InvalidUInt112
        vm.prank(alice);
        pyusdx.transfer(bob, 100);
    }

    /* ============ min112 Capping Behavior Tests ============ */

    function test_transfer_insufficientPrincipal_min112Caps() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index so transfer needs more principal than available
        pyusdx.setLatestIndex(PRECISION * 1000);

        minterGateway.mint(alice, 100);

        // Manually set alice's principal to very low value
        pyusdx.setEarningPrincipal(alice, 1);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        // Transfer should work - min112 caps at available principal
        vm.prank(alice);
        pyusdx.transfer(bob, 50);

        // Alice's balance should decrease
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - 50);

        // Alice's principal should be 0 (capped via min112)
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Bob should receive the principal (capped at what alice had)
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + 1);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + 50);
    }

    function test_burn_insufficientPrincipal_min112Caps() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index
        pyusdx.setLatestIndex(PRECISION * 1000);

        minterGateway.mint(alice, 100);

        // Manually set alice's principal to very low value
        pyusdx.setEarningPrincipal(alice, 1);
        pyusdx.setTotalEarningPrincipal(1);

        uint256 balanceBefore = pyusdx.balanceOf(alice);

        // Burn should work - min112 caps at available principal
        minterGateway.burn(alice, 50);

        // Balance should decrease
        assertEq(pyusdx.balanceOf(alice), balanceBefore - 50);

        // Principal should be 0 (capped via min112)
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertEq(pyusdx.totalEarningPrincipal(), 0);
    }

    function test_transfer_min112_recipientGetsPrincipal() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index
        pyusdx.setLatestIndex(PRECISION * 1000);

        minterGateway.mint(alice, 100);

        // Set alice's principal low
        pyusdx.setEarningPrincipal(alice, 1);

        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        // Transfer - recipient gets the capped principal
        vm.prank(alice);
        pyusdx.transfer(bob, 50);

        // Bob should receive exactly 1 principal (what alice had, capped by min112)
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + 1);

        // Even though 50 tokens at 1000x index would need more principal,
        // the transfer succeeds with min112 capping
        assertEq(pyusdx.balanceOf(bob), 50);
    }

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

    /* ============ setEarningDetails ============ */

    function test_setEarningDetails_enableEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        (bool isEarning, address manager, uint16 feeRate, address recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(manager, earnerManager);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);
    }

    function test_setEarningDetails_disableEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 0, address(0));

        (bool isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
    }

    function test_setEarningDetails_revert_zeroAccount() public {
        vm.expectRevert(IPYUSDX.ZeroAccount.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(address(0), true, 500, bob);
    }

    function test_setEarningDetails_revert_feeRateTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.FeeRateTooHigh.selector, 10001));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 10001, bob);
    }

    function test_setEarningDetails_revert_invalidDetails() public {
        vm.expectRevert(IPYUSDX.InvalidDetails.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 500, bob);
    }

    function test_setEarningDetails_batch() public {
        address[] memory batchAccounts = new address[](2);
        batchAccounts[0] = alice;
        batchAccounts[1] = bob;

        bool[] memory isEarning = new bool[](2);
        isEarning[0] = true;
        isEarning[1] = true;

        uint16[] memory feeRates = new uint16[](2);
        feeRates[0] = 500;
        feeRates[1] = 1000;

        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = alice;

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(batchAccounts, isEarning, feeRates, recipients);

        assertTrue(pyusdx.isEarning(alice));
        assertTrue(pyusdx.isEarning(bob));
    }

    function test_setEarningDetails_batch_revert_arrayLengthZero() public {
        vm.expectRevert(IPYUSDX.ArrayLengthZero.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(new address[](0), new bool[](0), new uint16[](0), new address[](0));
    }

    function test_setEarningDetails_batch_revert_arrayLengthMismatch() public {
        vm.expectRevert(IForcedTransferable.ArrayLengthMismatch.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(new address[](2), new bool[](1), new uint16[](2), new address[](2));
    }

    function test_setEarningDetails_noop_alreadyDisabled() public {
        // Alice is not earning (default state)
        (bool isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);

        // Calling setEarningDetails with isEarning=false should be a no-op (no event)
        vm.recordLogs();
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 0, address(0));

        // Verify no EarningDetailsSet event was emitted
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], IPYUSDX.EarningDetailsSet.selector);
        }

        // State should remain unchanged
        (isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
    }

    function test_setEarningDetails_noop_sameSettings() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        (bool isEarning, address manager, uint16 feeRate, address recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);

        // Call again with same settings - should be a no-op (no event, no claim)
        vm.recordLogs();
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Verify no EarningDetailsSet event was emitted
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], IPYUSDX.EarningDetailsSet.selector);
        }

        // State should remain unchanged
        (isEarning, manager, feeRate, recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(manager, earnerManager);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);
    }

    function test_setEarningDetails_changedFeeRate_emitsEvent() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Change fee rate - should emit event
        vm.expectEmit();
        emit IPYUSDX.EarningDetailsSet(alice, true, earnerManager, 1000, bob);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        // Verify state updated
        (, , uint16 feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(feeRate, 1000);
    }

    function test_setEarningDetails_changedClaimRecipient_emitsEvent() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        address charlie = makeAddr("charlie");

        // Change claim recipient - should emit event
        vm.expectEmit();
        emit IPYUSDX.EarningDetailsSet(alice, true, earnerManager, 500, charlie);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, charlie);

        // Verify state updated
        (, , , address recipient) = pyusdx.getEarningDetails(alice);
        assertEq(recipient, charlie);
    }

    function test_setEarningDetails_revert_earnerDetailsAlreadySet() public {
        // First earner manager sets earning details for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // A different earner manager tries to modify alice's details
        address otherEarnerManager = makeAddr("otherEarnerManager");
        bytes32 earnerManagerRole = pyusdx.EARNER_MANAGER_ROLE();
        vm.prank(admin);
        pyusdx.grantRole(earnerManagerRole, otherEarnerManager);

        // EarnerDetailsAlreadySet is thrown because alice is managed by a different active earner manager
        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.EarnerDetailsAlreadySet.selector, alice));
        vm.prank(otherEarnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);
    }

    function test_setEarningDetails_sameManagerCanUpdate() public {
        // First earner manager sets earning details for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Same earner manager can update alice's details
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        (, , uint16 feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(feeRate, 1000);
    }

    function test_setEarningDetails_revert_notEarnerManager() public {
        // Random caller without EARNER_MANAGER_ROLE
        address randomCaller = makeAddr("randomCaller");

        vm.expectRevert(IPYUSDX.NotEarnerManager.selector);
        vm.prank(randomCaller);
        pyusdx.setEarningDetails(alice, true, 500, bob);
    }

    function test_setEarningDetails_takeover_whenStoredManagerLostRole() public {
        // First earner manager sets earning details for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Verify earnerManager is stored as alice's manager
        (, address storedManager, , ) = pyusdx.getEarningDetails(alice);
        assertEq(storedManager, earnerManager);

        // Create a new earner manager
        address newEarnerManager = makeAddr("newEarnerManager");
        bytes32 earnerManagerRole = pyusdx.EARNER_MANAGER_ROLE();
        vm.prank(admin);
        pyusdx.grantRole(earnerManagerRole, newEarnerManager);

        // Revoke role from original earner manager
        vm.prank(admin);
        pyusdx.revokeRole(earnerManagerRole, earnerManager);

        // New earner manager can now take over alice's account (stored manager lost role)
        vm.prank(newEarnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        // Verify new manager is now stored
        uint16 feeRate;
        (, storedManager, feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(storedManager, newEarnerManager);
        assertEq(feeRate, 1000);
    }
}
