// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UIntMath } from "../../lib/evm-m-extensions/lib/common/src/libs/UIntMath.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";

import { IRateLimiter } from "../../src/abstract/interfaces/IRateLimiter.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXFuzzTests is PYUSDXBaseUnitTest {
    uint256 constant MINT_AMOUNT = 100e6; // 100 PYUSDX
    uint256 constant BURN_AMOUNT = 50e6; // 50 PYUSDX

    /* ============ Fuzz: mint ============ */

    function testFuzz_mint_nonEarningAccount(uint256 amount) public {
        uint256 boundedAmount = bound(amount, 1, type(uint240).max);

        uint256 totalSupplyBefore = pyusdx.totalSupply();

        issuerGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), boundedAmount);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + boundedAmount);
    }

    function testFuzz_mint_earningAccount(uint256 amount, uint128 index) public {
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(alice, 500, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, uint256(type(uint240).max) + 1);
        uint128 boundedIndex = uint128(bound(index, 1e12, 1e18)); // From 1x to 1,000,000x index

        uint256 totalSupplyBefore = pyusdx.totalSupply();

        pyusdx.setAccountLastIndex(alice, boundedIndex);

        // Get the actual current index used by the contract (includes continuous compounding)
        uint128 actualIndex = pyusdx.currentIndexOf(alice);

        // Skip cases where our test calculations would overflow (not contract behavior)
        vm.assume(boundedAmount <= type(uint256).max / PRECISION);

        bool amountExceedsUInt240 = boundedAmount > type(uint240).max;

        // Calculate principal safely
        uint256 amountPrincipal = (boundedAmount * PRECISION) / actualIndex;

        bool wouldOverflowPrincipal = amountPrincipal > type(uint112).max;

        // Check reverts in the same order as the contract would encounter them
        if (amountExceedsUInt240) {
            vm.expectRevert(UIntMath.InvalidUInt240.selector);
        } else if (wouldOverflowPrincipal) {
            vm.expectRevert(UIntMath.InvalidUInt112.selector);
        }

        issuerGateway.mint(alice, boundedAmount);

        if (!amountExceedsUInt240 && !wouldOverflowPrincipal) {
            uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(boundedAmount), actualIndex);
            assertEq(pyusdx.balanceOf(alice), boundedAmount);
            assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipal);
            assertEq(pyusdx.totalSupply(), totalSupplyBefore + boundedAmount);
        }
    }

    function testFuzz_rateLimit_refillStaysWithinCapacity(
        uint128 capacity,
        uint128 bucketRemaining,
        uint256 mintAmount,
        uint128 refillPerSecond,
        uint40 currentTime,
        uint40 timeSinceLastRefill,
        uint40 elapsedAfterMint
    ) public {
        uint128 boundedCapacity = uint128(bound(capacity, 1, type(uint128).max));
        uint128 boundedBucketRemaining = uint128(bound(bucketRemaining, 0, boundedCapacity));
        uint256 boundedMintAmount = bound(mintAmount, 0, type(uint128).max);
        uint128 boundedRefillPerSecond = uint128(bound(refillPerSecond, 1, type(uint128).max));

        // Bound currentTime to reasonable range, then constrain other time values
        uint40 boundedCurrentTime = uint40(bound(currentTime, 1, type(uint40).max));
        uint40 boundedTimeSinceLastRefill = uint40(bound(timeSinceLastRefill, 0, boundedCurrentTime - 1));
        uint40 boundedElapsedAfterMint = uint40(bound(elapsedAfterMint, 0, type(uint40).max - boundedCurrentTime));

        vm.warp(boundedCurrentTime);

        pyusdx.setRateLimitState(
            address(issuerGateway),
            boundedCapacity,
            boundedRefillPerSecond,
            boundedBucketRemaining,
            boundedCurrentTime - boundedTimeSinceLastRefill
        );

        // Calculate available amount after refill (caps at capacity)
        uint128 available = pyusdx.getRemainingAmount(address(issuerGateway));

        bool isZeroAmount = boundedMintAmount == 0;
        bool exceedsRateLimit = boundedMintAmount > available;

        if (isZeroAmount) {
            vm.expectRevert(IPYUSDX.ZeroAmount.selector);
        } else if (exceedsRateLimit) {
            vm.expectRevert(
                abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, boundedMintAmount, available)
            );
        }

        issuerGateway.mint(alice, boundedMintAmount);

        // Only test refill behavior if mint succeeded
        if (!exceedsRateLimit && !isZeroAmount) {
            vm.warp(block.timestamp + boundedElapsedAfterMint);

            uint128 availableAfterMint = pyusdx.getRemainingAmount(address(issuerGateway));

            assertLe(availableAfterMint, boundedCapacity);
        }
    }

    function testFuzz_rateLimit_zeroRefillConsumesCapacity(uint128 capacity, uint128 amount, uint40 elapsed) public {
        uint128 boundedCapacity = uint128(bound(capacity, 1, type(uint128).max));
        uint128 boundedAmount = uint128(bound(amount, 1, boundedCapacity));
        uint40 boundedElapsed = uint40(bound(elapsed, 1, type(uint40).max));

        vm.prank(rateLimitManager);
        pyusdx.setRateLimit(address(issuerGateway), boundedCapacity, 0, true);

        assertEq(pyusdx.getRemainingAmount(address(issuerGateway)), boundedCapacity);

        issuerGateway.mint(alice, boundedAmount);
        assertEq(pyusdx.getRemainingAmount(address(issuerGateway)), boundedCapacity - boundedAmount);

        // Time passes but no refill (zero refillPerSecond)
        vm.warp(block.timestamp + boundedElapsed);
        assertEq(pyusdx.getRemainingAmount(address(issuerGateway)), boundedCapacity - boundedAmount);
    }

    /* ============ Fuzz: burn ============ */

    function testFuzz_burn_nonEarningAccount(uint256 mintAmount, uint256 burnAmount) public {
        burnAmount = bound(burnAmount, 1, type(uint240).max);
        mintAmount = bound(mintAmount, 1, type(uint240).max);
        issuerGateway.mint(alice, mintAmount);

        bool wouldExceedBalance = burnAmount > mintAmount;

        if (wouldExceedBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, mintAmount, burnAmount)
            );
        }

        issuerGateway.burn(alice, burnAmount);

        if (!wouldExceedBalance) {
            assertEq(pyusdx.balanceOf(alice), mintAmount - burnAmount);
            assertEq(pyusdx.totalSupply(), mintAmount - burnAmount);
        }
    }

    /* ============ Fuzz: burn ============ */

    function testFuzz_burn_earningAccount(uint256 mintAmount, uint256 burnAmount, uint128 index) public {
        mintAmount = bound(mintAmount, 1, type(uint240).max);
        burnAmount = bound(burnAmount, 1, type(uint240).max);

        uint128 boundedIndex = uint128(bound(index, 1e12, 1e15)); // From 1x to 1,000x index

        vm.prank(earnerManager);
        pyusdx.setAccountInfo(alice, 500, 0, address(0));

        pyusdx.setAccountLastIndex(alice, boundedIndex);

        // Skip if mint would overflow principal (uint112)
        uint128 actualIndex = pyusdx.currentIndexOf(alice);
        vm.assume(mintAmount <= type(uint256).max / 1e12);
        vm.assume((uint256(mintAmount) * 1e12) / actualIndex <= type(uint112).max);

        issuerGateway.mint(alice, mintAmount);

        // Get state before burn
        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        bool wouldExceedBalance = burnAmount > balanceBefore;

        // Balance check happens before uint240 cast in the contract
        if (wouldExceedBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, balanceBefore, burnAmount)
            );
        }

        issuerGateway.burn(alice, burnAmount);

        // Verify state when no revert
        if (!wouldExceedBalance) {
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
            issuerGateway.mint(alice, boundedAmount);
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

            pyusdx.setAccountInfo(alice, 500, 0, address(0));
            pyusdx.setAccountInfo(bob, 500, 0, address(0));

            vm.stopPrank();

            pyusdx.setAccountLastIndex(alice, boundedIndex);
            pyusdx.setAccountLastIndex(bob, boundedIndex);

            issuerGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            // Check for principal overflow when adding to recipient
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 actualIndex = pyusdx.currentIndexOf(alice);
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
            pyusdx.setAccountInfo(bob, 500, 0, address(0));

            pyusdx.setAccountLastIndex(bob, boundedIndex);

            issuerGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            // Check for principal overflow when adding to earning recipient
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 actualIndex = pyusdx.currentIndexOf(bob);
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
        } else if (boundedPath == 3) {
            // E -> N
            vm.prank(earnerManager);
            pyusdx.setAccountInfo(alice, 500, 0, address(0));

            pyusdx.setAccountLastIndex(alice, boundedIndex);

            issuerGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            if (!amountExceedsUInt240 && wouldExceedBalance) {
                vm.expectRevert(
                    abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, aliceBalance, boundedAmount)
                );
            }

            uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
            uint128 actualIndex = pyusdx.currentIndexOf(alice);

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

            pyusdx.setAccountInfo(alice, 500, 100, address(0));
            pyusdx.setAccountInfo(bob, 500, 100, address(0));

            vm.stopPrank();

            pyusdx.setAccountLastIndex(alice, boundedIndex);
            pyusdx.setAccountLastIndex(bob, boundedIndex);

            issuerGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            // Check for principal overflow when adding to recipient
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 actualIndex = pyusdx.currentIndexOf(alice);
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

            pyusdx.setAccountInfo(alice, 500, 100, address(0));
            pyusdx.setAccountInfo(bob, 500, 500, address(0));

            vm.stopPrank();

            pyusdx.setAccountLastIndex(alice, boundedIndex);
            pyusdx.setAccountLastIndex(bob, boundedIndex);

            issuerGateway.mint(alice, boundedAmount);
            uint256 aliceBalance = pyusdx.balanceOf(alice);
            bool wouldExceedBalance = boundedAmount > aliceBalance;

            // Check for principal overflow when adding to recipient
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 actualIndex = pyusdx.currentIndexOf(alice);
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
            issuerGateway.mint(alice, boundedAmount);
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

    /* ============ Fuzz: setAccountInfo pause invariant ============ */

    // Invariant under pause: calling `setAccountInfo` with arbitrary earner configs and target
    // configs must not revert, and `totalSupply` must grow by exactly the pre-call `yieldWithFee`
    // — the earner keeps the full materialized amount; routing and fee hops are skipped.
    function testFuzz_setAccountInfo_whenPaused_supplyDeltaEqualsYield(
        uint256 mintAmount,
        uint32 earnerRate,
        uint16 feeRate,
        uint40 elapsed,
        uint8 targetPath,
        bool customRecipient
    ) public {
        mintAmount = bound(mintAmount, 1e6, 1e18);
        uint32 boundedEarnerRate = uint32(bound(earnerRate, 1, MAX_FEE_RATE));
        uint16 boundedFeeRate = uint16(bound(feeRate, 0, MAX_FEE_RATE));
        uint40 boundedElapsed = uint40(bound(elapsed, 1 days, 365 days));
        uint8 boundedPath = uint8(bound(targetPath, 0, 2)); // 0=disable, 1=update rate, 2=update recipient

        address initialRecipient = customRecipient ? bob : address(0);

        issuerGateway.mint(alice, mintAmount);

        vm.prank(earnerManager);
        pyusdx.setAccountInfo(alice, boundedEarnerRate, boundedFeeRate, initialRecipient);
        pyusdx.setAccountRateBps(alice, boundedEarnerRate);

        vm.warp(block.timestamp + boundedElapsed);

        (uint256 yieldWithFee, , ) = pyusdx.accruedYieldAndFeeOf(alice);

        uint256 supplyBefore = pyusdx.totalSupply();
        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);

        vm.prank(pauser);
        pyusdx.pause();

        vm.prank(earnerManager);
        if (boundedPath == 0) {
            pyusdx.setAccountInfo(alice, 0, 0, address(0));
            assertFalse(pyusdx.isEarning(alice));
        } else if (boundedPath == 1) {
            uint32 newRate = boundedEarnerRate == MAX_FEE_RATE ? 1 : boundedEarnerRate + 1;
            pyusdx.setAccountInfo(alice, newRate, boundedFeeRate, initialRecipient);
            (uint32 postRate, , ) = pyusdx.getAccountEarningInfo(alice);
            assertEq(postRate, newRate);
        } else {
            address newRecipient = initialRecipient == address(0) ? carol : address(0);
            pyusdx.setAccountInfo(alice, boundedEarnerRate, boundedFeeRate, newRecipient);
            // Read raw storage — `getAccountEarningInfo` collapses `address(0)` → `account`.
            (, , address storedRecipient) = pyusdx.getAccountStorage(alice);
            assertEq(storedRecipient, newRecipient);
        }

        assertEq(pyusdx.totalSupply(), supplyBefore + yieldWithFee, "supply grows by pre-call yieldWithFee");
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore + yieldWithFee, "earner keeps full yield");
    }
}
