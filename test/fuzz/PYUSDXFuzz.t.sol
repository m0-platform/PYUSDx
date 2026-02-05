// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXFuzzTests is PYUSDXBaseUnitTest {
    uint256 constant MINT_AMOUNT = 100e6; // 100 PYUSDX
    uint256 constant BURN_AMOUNT = 50e6; // 50 PYUSDX

    /* ============ Fuzz: Non-Earning Account ============ */

    // TODO: improve fuzz tests by passing an index value
    function testFuzz_Mint_nonEarningAccount(uint256 amount) public {
        // Bound amount and use vm.assume to filter out values that would overflow
        uint256 boundedAmount = bound(amount, 1, type(uint240).max);
        vm.assume(_canSafelyMint(boundedAmount));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();

        minterGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + boundedAmount);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + boundedAmount);
        assertEq(pyusdx.totalNonEarningSupply(), uint256(totalNonEarningSupplyBefore) + boundedAmount);
    }

    function testFuzz_Mint_nonEarningAccount_address(uint256 amount, address recipient) public {
        // Bound amount and use vm.assume to filter out values that would overflow
        uint256 boundedAmount = bound(amount, 1, type(uint240).max);

        // Exclude zero address and already used addresses
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(pyusdx));
        vm.assume(recipient != address(minterGateway));
        vm.assume(_canSafelyMint(boundedAmount));

        uint256 balanceBefore = pyusdx.balanceOf(recipient);

        minterGateway.mint(recipient, boundedAmount);

        assertEq(pyusdx.balanceOf(recipient), balanceBefore + boundedAmount);
    }

    function testFuzz_Mint_revertsWhenAmountTooLarge() public {
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();

        // Calculate amount that would overflow uint240
        if (totalNonEarningSupplyBefore == type(uint240).max) {
            // Already at max, any amount > 0 overflows safe240 conversion
            vm.expectRevert(); // InvalidUInt240
            minterGateway.mint(alice, 1);
        } else {
            uint256 overflowAmount = uint256(type(uint240).max) - uint256(totalNonEarningSupplyBefore) + 1;

            vm.expectRevert(); // InvalidUInt240
            minterGateway.mint(alice, overflowAmount);
        }
    }

    /* ============ Fuzz: Revert Conditions ============ */

    function testFuzz_Mint_revertIfZeroAmount(uint256 amount) public {
        // Only test with amount == 0
        if (amount != 0) return;

        vm.expectRevert(IPYUSDX.ZeroAmount.selector);
        minterGateway.mint(alice, amount);
    }

    function testFuzz_Mint_revertIfZeroRecipient(address recipient) public {
        // Only test with zero address
        if (recipient != address(0)) return;

        vm.expectRevert(IPYUSDX.ZeroRecipient.selector);
        minterGateway.mint(recipient, MINT_AMOUNT);
    }

    /* ============ Fuzz: Multiple Mints ============ */

    function testFuzz_Mint_multipleSequential(uint256 amount1, uint256 amount2, uint256 amount3) public {
        // Bound amounts and use vm.assume to filter out overflow values
        amount1 = bound(amount1, 1, type(uint112).max);
        vm.assume(_canSafelyMint(amount1));

        minterGateway.mint(alice, amount1);

        amount2 = bound(amount2, 1, type(uint112).max);
        vm.assume(_canSafelyMint(amount2));

        minterGateway.mint(alice, amount2);

        amount3 = bound(amount3, 1, type(uint112).max);
        vm.assume(_canSafelyMint(amount3));

        minterGateway.mint(alice, amount3);

        // Final assertion
        assertEq(pyusdx.balanceOf(alice), amount1 + amount2 + amount3);
    }

    /* ============ Fuzz: Earning Account ============ */

    function testFuzz_Mint_earningAccount(uint256 amount) public {
        // Set up alice as an earning account
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Bound amount and use vm.assume to filter out values that would overflow
        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        vm.assume(_canSafelyMint(boundedAmount));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + boundedAmount);
        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
    }

    /* ============ Helper Functions ============ */

    /// @dev Check if minting amount would overflow the principal calculation
    function _canSafelyMint(uint256 amount) internal view returns (bool) {
        uint128 index = pyusdx.currentIndex();
        uint112 totalEarningPrincipal = pyusdx.totalEarningPrincipal();
        uint240 totalNonEarningSupply = pyusdx.totalNonEarningSupply();

        // Check the overflow conditions from mint()
        if (uint256(totalNonEarningSupply) + amount > type(uint240).max) {
            return false;
        }

        // Check principal overflow: totalEarningPrincipal + ceil((totalNonEarningSupply + amount) * PRECISION / index) < type(uint112).max
        // Simplified check: ensure we have room for the new principal
        uint256 maxNewPrincipal = uint256(type(uint112).max) - 1; // -1 for safety margin
        uint256 maxNewSupply = ((maxNewPrincipal * index) / PRECISION);

        return uint256(totalNonEarningSupply) + amount <= maxNewSupply;
    }

    /* ============ Fuzz: Burn Non-Earning Account ============ */

    // TODO: improve fuzz tests by passing mintAmount and burnAmount capped to type(uint240).max
    function testFuzz_burn_nonEarningAccount(uint256 amount) public {
        uint256 boundedAmount = bound(amount, 1, 1e15); // Reasonable bound to avoid overflow

        // Mint enough balance first (more than boundedAmount)
        minterGateway.mint(alice, 1e18);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();

        minterGateway.burn(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore - boundedAmount);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore - boundedAmount);
        assertEq(pyusdx.totalNonEarningSupply(), uint256(totalNonEarningSupplyBefore) - boundedAmount);
    }

    /* ============ Fuzz: Burn Earning Account ============ */

    // TODO: improve fuzz tests by passing index value
    function testFuzz_burn_earningAccount(uint256 amount) public {
        // Set up alice as an earning account
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, 1e13); // Reasonable bound to avoid overflow

        // Mint enough balance first
        minterGateway.mint(alice, 1e16);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.burn(alice, boundedAmount);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(boundedAmount, indexBefore);
        uint112 expectedPrincipalAfter = principalBefore - expectedPrincipalSubtracted;
        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
    }
}
