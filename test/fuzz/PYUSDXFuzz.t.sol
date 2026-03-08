// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import { console } from "../../lib/forge-std/src/console.sol";
import { UIntMath } from "../../lib/evm-m-extensions/lib/common/src/libs/UIntMath.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXFuzzTests is PYUSDXBaseUnitTest {
    uint256 constant MINT_AMOUNT = 100e6; // 100 PYUSDX
    uint256 constant BURN_AMOUNT = 50e6; // 50 PYUSDX

    /* ============ Fuzz: mint ============ */

    function testFuzz_mint_nonEarningAccount(uint256 amount) public {
        uint256 boundedAmount = bound(amount, 1, uint256(type(uint240).max) + 1);

        uint256 totalSupplyBefore = pyusdx.totalSupply();

        bool amountExceedsUInt240 = boundedAmount > type(uint240).max;

        bool wouldOverflowSupply = totalSupplyBefore + boundedAmount > type(uint240).max;

        if (amountExceedsUInt240) {
            vm.expectRevert(UIntMath.InvalidUInt240.selector);
        } else if (wouldOverflowSupply) {
            vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        }

        minterGateway.mint(alice, boundedAmount);

        if (!amountExceedsUInt240 && !wouldOverflowSupply) {
            assertEq(pyusdx.balanceOf(alice), boundedAmount);
            assertEq(pyusdx.totalSupply(), totalSupplyBefore + boundedAmount);
        }
    }

    function testFuzz_mint_earningAccount(uint256 amount, uint128 index) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, uint256(type(uint240).max) + 1);
        uint128 boundedIndex = uint128(bound(index, 1e12, 1e18)); // From 1x to 1,000,000x index

        uint256 totalSupplyBefore = pyusdx.totalSupply();

        pyusdx.setAccountLastIndex(alice, boundedIndex);

        // Get the actual current index used by the contract (includes continuous compounding)
        uint128 actualIndex = pyusdx.currentAccountIndex(alice);

        // Skip cases where our test calculations would overflow (not contract behavior)
        vm.assume(boundedAmount <= type(uint256).max / PRECISION);

        bool amountExceedsUInt240 = boundedAmount > type(uint240).max;

        // Calculate principal safely
        uint256 amountPrincipal = (boundedAmount * PRECISION) / actualIndex;

        bool wouldOverflowPrincipal = amountPrincipal > type(uint112).max;
        bool wouldOverflowSupply = totalSupplyBefore + boundedAmount > type(uint240).max;

        // Check reverts in the same order as the contract would encounter them
        if (amountExceedsUInt240) {
            vm.expectRevert(UIntMath.InvalidUInt240.selector);
        } else if (wouldOverflowSupply) {
            vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        } else if (wouldOverflowPrincipal) {
            vm.expectRevert(UIntMath.InvalidUInt112.selector);
        }

        minterGateway.mint(alice, boundedAmount);

        if (!amountExceedsUInt240 && !wouldOverflowPrincipal && !wouldOverflowSupply) {
            uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(boundedAmount), actualIndex);
            assertEq(pyusdx.balanceOf(alice), boundedAmount);
            assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipal);
            assertEq(pyusdx.totalSupply(), totalSupplyBefore + boundedAmount);
        }
    }

    /* ============ Fuzz: burn ============ */

    function testFuzz_burn_nonEarningAccount(uint256 mintAmount, uint256 burnAmount) public {
        burnAmount = bound(burnAmount, 1, uint256(type(uint240).max) + 1);
        mintAmount = bound(mintAmount, 1, uint256(type(uint240).max) + 1);
        vm.assume(_canSafelyMint(mintAmount));

        minterGateway.mint(alice, mintAmount);

        bool amountExceedsUInt240 = burnAmount > type(uint240).max;
        bool wouldExceedBalance = burnAmount > mintAmount;

        // Check reverts in the same order as the contract would encounter them
        if (amountExceedsUInt240) {
            vm.expectRevert(UIntMath.InvalidUInt240.selector);
        } else if (wouldExceedBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, mintAmount, burnAmount)
            );
        }

        minterGateway.burn(alice, burnAmount);

        if (!amountExceedsUInt240 && !wouldExceedBalance) {
            assertEq(pyusdx.balanceOf(alice), mintAmount - burnAmount);
            assertEq(pyusdx.totalSupply(), mintAmount - burnAmount);
        }
    }

    /* ============ Fuzz: burn ============ */

    function testFuzz_burn_earningAccount(uint256 mintAmount, uint256 burnAmount, uint128 index) public {
        mintAmount = bound(mintAmount, 1, uint256(type(uint240).max) + 1);
        burnAmount = bound(burnAmount, 1, uint256(type(uint240).max) + 1);

        uint128 boundedIndex = uint128(bound(index, 1e12, 1e15)); // From 1x to 1,000x index

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.assume(_canSafelyMint(mintAmount));

        pyusdx.setAccountLastIndex(alice, boundedIndex);

        // Skip if mint would overflow principal (uint112)
        uint128 actualIndex = pyusdx.currentAccountIndex(alice);
        vm.assume(mintAmount <= type(uint256).max / 1e12);
        vm.assume((uint256(mintAmount) * 1e12) / actualIndex <= type(uint112).max);

        minterGateway.mint(alice, mintAmount);

        // Get state before burn
        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        bool burnExceedsUInt240 = burnAmount > type(uint240).max;
        bool wouldExceedBalance = burnAmount > balanceBefore;

        // Check reverts in the same order as the contract would encounter them
        if (burnExceedsUInt240) {
            vm.expectRevert(UIntMath.InvalidUInt240.selector);
        } else if (wouldExceedBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, balanceBefore, burnAmount)
            );
        }

        minterGateway.burn(alice, burnAmount);

        // Verify state when no revert
        if (!burnExceedsUInt240 && !wouldExceedBalance) {
            uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(burnAmount, actualIndex);

            // Principal being rounded up, it may be greater than the stored principal
            uint112 expectedPrincipalAfter = principalBefore < expectedPrincipalSubtracted
                ? 0
                : principalBefore - expectedPrincipalSubtracted;

            assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
            assertEq(pyusdx.balanceOf(alice), balanceBefore - burnAmount);
        }
    }

    /* ============ Fuzz: transfer ============ */

    function testFuzz_Transfer(uint256 amount, uint128 index, uint8 path) public {
        uint256 boundedAmount = bound(amount, 1, uint256(type(uint240).max) + 1);
        uint128 boundedIndex = uint128(bound(index, 1e12, 1e15)); // From 1x to 1,000x index
        uint8 boundedPath = uint8(bound(path, 0, 7)); // 8 path variations

        vm.assume(_canSafelyMint(boundedAmount * 2)); // Need for both alice and bob

        // Skip if principal would overflow uint112 for earning accounts
        vm.assume(boundedAmount <= type(uint256).max / 1e12);
        vm.assume((boundedAmount * 1e12) / boundedIndex <= type(uint112).max);

        bool amountExceedsUInt240 = boundedAmount > type(uint240).max;

        // Check reverts before executing transfer
        if (amountExceedsUInt240) {
            vm.expectRevert(UIntMath.InvalidUInt240.selector);
        }

        // Paths 0-3: Basic paths
        // Paths 4-7: Fee variation paths

        if (boundedPath == 0) {
            // N -> N
            minterGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            if (!amountExceedsUInt240 && wouldExceedBalance) {
                vm.expectRevert(
                    abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, aliceBalance, boundedAmount)
                );
            }

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            if (!amountExceedsUInt240 && !wouldExceedBalance) {
                assertEq(pyusdx.balanceOf(bob), boundedAmount);
            }
        } else if (boundedPath == 1) {
            // E -> E (0% fee)
            vm.startPrank(earnerManager);

            pyusdx.setEarningDetails(alice, true, 0, address(0));
            pyusdx.setEarningDetails(bob, true, 0, address(0));

            vm.stopPrank();

            pyusdx.setAccountLastIndex(alice, boundedIndex);
            pyusdx.setAccountLastIndex(bob, boundedIndex);

            minterGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            // Check for principal overflow when adding to recipient
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 actualIndex = pyusdx.currentAccountIndex(alice);
            uint256 principalToAdd = _expectedPrincipalRoundUpSafe(boundedAmount, actualIndex);
            bool wouldOverflowPrincipal = bobPrincipalBefore + principalToAdd > type(uint112).max;

            if (!amountExceedsUInt240 && wouldExceedBalance) {
                vm.expectRevert(
                    abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, aliceBalance, boundedAmount)
                );
            } else if (!amountExceedsUInt240 && !wouldExceedBalance && wouldOverflowPrincipal) {
                vm.expectRevert(UIntMath.InvalidUInt112.selector);
            }

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            if (!amountExceedsUInt240 && !wouldExceedBalance && !wouldOverflowPrincipal) {
                assertEq(pyusdx.balanceOf(bob), boundedAmount);
                uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(boundedAmount), actualIndex);
                assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
            }
        } else if (boundedPath == 2) {
            // N -> E
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(bob, true, 0, address(0));

            pyusdx.setAccountLastIndex(bob, boundedIndex);

            minterGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            // Check for principal overflow when adding to earning recipient
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 actualIndex = pyusdx.currentAccountIndex(bob);
            uint256 principalToAdd = _expectedPrincipalRoundUpSafe(boundedAmount, actualIndex);
            bool wouldOverflowPrincipal = bobPrincipalBefore + principalToAdd > type(uint112).max;

            if (!amountExceedsUInt240 && wouldExceedBalance) {
                vm.expectRevert(
                    abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, aliceBalance, boundedAmount)
                );
            } else if (!amountExceedsUInt240 && !wouldExceedBalance && wouldOverflowPrincipal) {
                vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
            }

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            if (!amountExceedsUInt240 && !wouldExceedBalance && !wouldOverflowPrincipal) {
                assertEq(pyusdx.balanceOf(bob), boundedAmount);
                uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(boundedAmount), actualIndex);
                assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
            }
        } else if (boundedPath == 3) {
            // E -> N
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(alice, true, 0, address(0));

            pyusdx.setAccountLastIndex(alice, boundedIndex);

            minterGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            if (!amountExceedsUInt240 && wouldExceedBalance) {
                vm.expectRevert(
                    abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, aliceBalance, boundedAmount)
                );
            }

            uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
            uint128 actualIndex = pyusdx.currentAccountIndex(alice);

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            if (!amountExceedsUInt240 && !wouldExceedBalance) {
                assertEq(pyusdx.balanceOf(bob), boundedAmount);
                uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(boundedAmount, actualIndex);
                uint112 expectedPrincipalAfter = principalBefore < expectedPrincipalSubtracted
                    ? 0
                    : principalBefore - expectedPrincipalSubtracted;
                assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
            }
        } else if (boundedPath == 4) {
            // E -> E with same 1% fee
            vm.startPrank(earnerManager);

            pyusdx.setEarningDetails(alice, true, 100, address(0));
            pyusdx.setEarningDetails(bob, true, 100, address(0));

            vm.stopPrank();

            pyusdx.setAccountLastIndex(alice, boundedIndex);
            pyusdx.setAccountLastIndex(bob, boundedIndex);

            minterGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            // Check for principal overflow when adding to recipient
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 actualIndex = pyusdx.currentAccountIndex(alice);
            uint256 principalToAdd = _expectedPrincipalRoundUpSafe(boundedAmount, actualIndex);
            bool wouldOverflowPrincipal = bobPrincipalBefore + principalToAdd > type(uint112).max;

            if (!amountExceedsUInt240 && wouldExceedBalance) {
                vm.expectRevert(
                    abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, aliceBalance, boundedAmount)
                );
            } else if (!amountExceedsUInt240 && !wouldExceedBalance && wouldOverflowPrincipal) {
                vm.expectRevert(UIntMath.InvalidUInt112.selector);
            }

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            if (!amountExceedsUInt240 && !wouldExceedBalance && !wouldOverflowPrincipal) {
                uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(boundedAmount), actualIndex);
                assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
            }
        } else if (boundedPath == 5) {
            // E -> E with different fees (1% alice, 5% bob)
            vm.startPrank(earnerManager);

            pyusdx.setEarningDetails(alice, true, 100, address(0));
            pyusdx.setEarningDetails(bob, true, 500, address(0));

            vm.stopPrank();

            pyusdx.setAccountLastIndex(alice, boundedIndex);
            pyusdx.setAccountLastIndex(bob, boundedIndex);

            minterGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            // Check for principal overflow when adding to recipient
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 actualIndex = pyusdx.currentAccountIndex(alice);
            uint256 principalToAdd = _expectedPrincipalRoundUpSafe(boundedAmount, actualIndex);
            bool wouldOverflowPrincipal = bobPrincipalBefore + principalToAdd > type(uint112).max;

            if (!amountExceedsUInt240 && wouldExceedBalance) {
                vm.expectRevert(
                    abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, aliceBalance, boundedAmount)
                );
            } else if (!amountExceedsUInt240 && !wouldExceedBalance && wouldOverflowPrincipal) {
                vm.expectRevert(UIntMath.InvalidUInt112.selector);
            }

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            if (!amountExceedsUInt240 && !wouldExceedBalance && !wouldOverflowPrincipal) {
                uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(boundedAmount), actualIndex);
                assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
            }
        } else {
            // Path 6: Extra variation (N -> N basic transfer)
            minterGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            if (!amountExceedsUInt240 && wouldExceedBalance) {
                vm.expectRevert(
                    abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, aliceBalance, boundedAmount)
                );
            }

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            if (!amountExceedsUInt240 && !wouldExceedBalance) {
                assertEq(pyusdx.balanceOf(bob), boundedAmount);
            }
        }
    }

    /* ============ Helper Functions ============ */

    /// @dev Check if minting amount would overflow totalSupply (uint240)
    function _canSafelyMint(uint256 amount) internal view returns (bool) {
        return pyusdx.totalSupply() + amount <= type(uint240).max;
    }
}
