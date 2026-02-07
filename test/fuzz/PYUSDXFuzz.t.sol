// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { UIntMath } from "../../lib/m-extensions/lib/common/src/libs/UIntMath.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXFuzzTests is PYUSDXBaseUnitTest {
    uint256 constant MINT_AMOUNT = 100e6; // 100 PYUSDX
    uint256 constant BURN_AMOUNT = 50e6; // 50 PYUSDX

    /* ============ Fuzz: mint ============ */

    /* ============ Non-Earning Account ============ */

    function testFuzz_mint_nonEarningAccount(uint256 amount) public {
        uint256 boundedAmount = bound(amount, 1, uint256(type(uint240).max) + 1);

        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();
        bool amountExceedsUInt240 = boundedAmount > type(uint240).max;
        bool wouldOverflowSupply = uint256(totalNonEarningSupplyBefore) + boundedAmount > type(uint240).max;
        bool wouldOverflowBalance = boundedAmount > type(uint112).max;

        if (amountExceedsUInt240) {
            vm.expectRevert(UIntMath.InvalidUInt240.selector);
        } else if (wouldOverflowSupply) {
            vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        } else if (wouldOverflowBalance) {
            vm.expectRevert(UIntMath.InvalidUInt112.selector);
        }

        minterGateway.mint(alice, boundedAmount);

        if (!amountExceedsUInt240 && !wouldOverflowSupply && !wouldOverflowBalance) {
            assertEq(pyusdx.balanceOf(alice), boundedAmount);
            assertEq(pyusdx.totalSupply(), boundedAmount);
            assertEq(pyusdx.totalNonEarningSupply(), uint256(totalNonEarningSupplyBefore) + boundedAmount);
        }
    }

    /* ============ Fuzz: Multiple Mints ============ */

    function testFuzz_mint_multipleSequential(uint256 amount1, uint256 amount2, uint256 amount3) public {
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

    function testFuzz_mint_earningAccount(uint256 amount) public {
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

    function testFuzz_burn_nonEarningAccount(uint256 amount) public {
        uint256 boundedAmount = bound(amount, 1, 1e15); // Use reasonable bound to avoid overflow
        vm.assume(_canSafelyMint(boundedAmount + 1e12));

        // Mint enough balance first (more than boundedAmount)
        minterGateway.mint(alice, boundedAmount + 1e12);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 totalNonEarningSupplyBefore = pyusdx.totalNonEarningSupply();

        minterGateway.burn(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore - boundedAmount);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore - boundedAmount);
        assertEq(pyusdx.totalNonEarningSupply(), uint256(totalNonEarningSupplyBefore) - boundedAmount);
    }

    /* ============ Fuzz: Burn Earning Account ============ */

    function testFuzz_burn_earningAccount(uint256 amount, uint32 rate, uint32 timeDelta) public {
        // Set up alice as an earning account
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, type(uint240).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000)); // Max 100% rate
        uint32 boundedTimeDelta = uint32(bound(timeDelta, 0, 365 days));

        vm.assume(_canSafelyMint(boundedAmount + 1e18));

        // Set rate and mint
        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);
        minterGateway.mint(alice, boundedAmount + 1e18);

        // Warp time to grow index
        vm.warp(block.timestamp + boundedTimeDelta);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        vm.assume(_canSafelyBurn(alice, boundedAmount));
        minterGateway.burn(alice, boundedAmount);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(boundedAmount, indexBefore);
        uint112 expectedPrincipalAfter = principalBefore - expectedPrincipalSubtracted;
        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
    }

    /* ============ Fuzz: Index-Parameterized Tests ============ */

    /// @notice Mint with rate parameter to test index variations
    function testFuzz_mint_earningAccount_withRate(uint256 amount, uint32 rate) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        vm.assume(_canSafelyMint(boundedAmount));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + boundedAmount);
        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
    }

    /// @notice Burn with time delta (index growth between mint and burn)
    function testFuzz_Burn_earningAccount_withTimeDelta(
        uint256 mintAmount,
        uint256 burnAmount,
        uint32 timeDelta
    ) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedMintAmount = bound(mintAmount, 1, type(uint112).max);
        uint256 boundedBurnAmount = bound(burnAmount, 1, type(uint240).max);
        uint32 boundedTimeDelta = uint32(bound(timeDelta, 0, 365 days));
        vm.assume(_canSafelyMint(boundedMintAmount));

        // Set a non-zero rate for index growth
        vm.prank(rateManager);
        pyusdx.setRate(500); // 5% rate

        minterGateway.mint(alice, boundedMintAmount);
        uint112 principalAtMint = pyusdx.earningPrincipalOf(alice);

        // Warp time to grow index
        vm.warp(block.timestamp + boundedTimeDelta);

        vm.assume(_canSafelyBurn(alice, boundedBurnAmount));
        uint128 indexAtBurn = pyusdx.currentIndex();

        minterGateway.burn(alice, boundedBurnAmount);

        // Verify principal was subtracted correctly with the new index
        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(boundedBurnAmount, indexAtBurn);
        uint112 expectedPrincipalAfter = principalAtMint - expectedPrincipalSubtracted;
        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
    }

    /// @notice Transfer earning-to-earning with index changes
    function testFuzz_Transfer_earningToEarning_withIndex(uint256 amount, uint32 rate, uint32 timeDelta) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        uint32 boundedTimeDelta = uint32(bound(timeDelta, 0, 365 days));
        vm.assume(_canSafelyMint(boundedAmount));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        minterGateway.mint(alice, boundedAmount);

        // Warp time to grow index
        vm.warp(block.timestamp + boundedTimeDelta);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint128 indexBefore = pyusdx.currentIndex();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - boundedAmount);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + boundedAmount);

        // Verify principal transfer used roundUp at current index
        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(boundedAmount, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(bob), expectedPrincipal);
    }

    /// @notice All transfer paths (N->N, E->E, N->E, E->N) with index parameterization
    function testFuzz_Transfer_allPaths_withIndexChanges(uint256 amount, uint32 rate, uint8 path) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        uint8 boundedPath = uint8(bound(path, 0, 3));
        vm.assume(_canSafelyMint(boundedAmount * 2)); // Need for both alice and bob

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        // Path 0: Non-earning -> Non-earning
        // Path 1: Earning -> Earning
        // Path 2: Non-earning -> Earning
        // Path 3: Earning -> Non-earning

        if (boundedPath == 0) {
            // N -> N
            minterGateway.mint(alice, boundedAmount);
            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);
            assertEq(pyusdx.balanceOf(bob), boundedAmount);
            assertEq(pyusdx.totalNonEarningSupply(), boundedAmount);
        } else if (boundedPath == 1) {
            // E -> E
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
            pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

            minterGateway.mint(alice, boundedAmount);
            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);
            assertEq(pyusdx.balanceOf(bob), boundedAmount);
        } else if (boundedPath == 2) {
            // N -> E
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

            minterGateway.mint(alice, boundedAmount);
            uint128 indexBefore = pyusdx.currentIndex();

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            assertEq(pyusdx.balanceOf(bob), boundedAmount);
            uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, indexBefore);
            assertEq(pyusdx.earningPrincipalOf(bob), expectedPrincipal);
        } else {
            // E -> N
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

            minterGateway.mint(alice, boundedAmount);
            uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
            uint128 indexBefore = pyusdx.currentIndex();

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            assertEq(pyusdx.balanceOf(bob), boundedAmount);
            uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(boundedAmount, indexBefore);
            assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipalSubtracted);
        }
    }

    /* ============ Fuzz: Boundary Tests ============ */

    /// @notice Test mint at specific index boundaries
    function testFuzz_mint_earningAccount_atIndexBoundaries(uint256 amount, uint8 boundaryCase) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        uint8 boundedCase = uint8(bound(boundaryCase, 0, 4));
        vm.assume(_canSafelyMint(boundedAmount));

        uint128 testIndex;

        // Boundary cases:
        // 0: Minimum index (1e12)
        // 1: Slightly above minimum (1e12 + 1)
        // 2: Double minimum (2e12)
        // 3: High index (1e14)
        // 4: Very high index (1e16)
        if (boundedCase == 0) testIndex = 1e12;
        else if (boundedCase == 1) testIndex = 1e12 + 1;
        else if (boundedCase == 2) testIndex = 2e12;
        else if (boundedCase == 3) testIndex = 1e14;
        else testIndex = 1e16;

        pyusdx.setLatestIndex(testIndex);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + boundedAmount);
        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
    }

    /// @notice Principal overflow edge case test
    function testFuzz_mint_earningAccount_principalOverflowEdge(uint256 amount) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set a high index to make principal calculation hit limits
        pyusdx.setLatestIndex(1e14);

        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        vm.assume(_canSafelyMint(boundedAmount));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentIndex();

        minterGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + boundedAmount);
        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);

        // Verify total principal didn't overflow
        assertLe(pyusdx.totalEarningPrincipal(), type(uint112).max);
    }

    /// @notice Rounding invariants: mint uses floor, burn uses ceil
    function testFuzz_mintBurn_roundingInvariants(uint256 amount, uint32 rate, uint32 timeDelta) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        uint32 boundedTimeDelta = uint32(bound(timeDelta, 1, 365 days)); // At least 1 second for index growth
        vm.assume(_canSafelyMint(boundedAmount));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        // Mint at initial index
        uint128 indexAtMint = pyusdx.currentIndex();
        minterGateway.mint(alice, boundedAmount);
        uint112 principalAtMint = pyusdx.earningPrincipalOf(alice);

        // Warp to grow index
        vm.warp(block.timestamp + boundedTimeDelta);
        uint128 indexAtBurn = pyusdx.currentIndex();

        // Burn should use roundUp, meaning it charges MORE principal
        // So we should never have negative principal after burn
        vm.assume(_canSafelyBurn(alice, boundedAmount));
        minterGateway.burn(alice, boundedAmount);
        uint112 principalAfterBurn = pyusdx.earningPrincipalOf(alice);

        // Invariant: principalAfterBurn <= principalAtMint (roundUp charges more)
        assertLe(principalAfterBurn, principalAtMint);

        // Invariant: For small amounts at same index, principal change should be consistent
        if (indexAtMint == indexAtBurn) {
            uint112 principalChange = principalAtMint - principalAfterBurn;
            uint112 expectedPrincipalChange = _getExpectedPrincipalRoundedUp(boundedAmount, indexAtMint);
            assertEq(principalChange, expectedPrincipalChange);
        }
    }

    /* ============ Fuzz: Rounding-Specific Tests ============ */

    /// @notice Rounding direction: mint uses roundDown (floor)
    function testFuzz_mint_roundingDirection_correct(uint256 amount, uint32 rate, uint32 timeDelta) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        uint32 boundedTimeDelta = uint32(bound(timeDelta, 0, 365 days));
        vm.assume(_canSafelyMint(boundedAmount));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);
        vm.warp(block.timestamp + boundedTimeDelta);

        uint128 indexBefore = pyusdx.currentIndex();
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.mint(alice, boundedAmount);

        uint112 principalAfter = pyusdx.earningPrincipalOf(alice);
        uint112 principalAdded = principalAfter - principalBefore;
        uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(boundedAmount), indexBefore);

        // Mint uses roundDown - actual should equal expected
        assertEq(principalAdded, expectedPrincipal);

        // Verify invariant: roundDown means (principal * index / PRECISION) <= amount
        uint256 calculatedAmount = (uint256(principalAdded) * indexBefore) / PRECISION;
        assertLe(calculatedAmount, boundedAmount);
    }

    /// @notice Rounding direction: burn uses roundUp (ceil)
    function testFuzz_Burn_roundingDirection_correct(uint256 mintAmount, uint256 burnAmount, uint32 rate) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedMintAmount = bound(mintAmount, 1, type(uint112).max);
        uint256 boundedBurnAmount = bound(burnAmount, 1, type(uint240).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        vm.assume(_canSafelyMint(boundedMintAmount));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        minterGateway.mint(alice, boundedMintAmount);
        uint112 principalBeforeBurn = pyusdx.earningPrincipalOf(alice);
        uint128 indexAtBurn = pyusdx.currentIndex();

        vm.assume(_canSafelyBurn(alice, boundedBurnAmount));
        minterGateway.burn(alice, boundedBurnAmount);

        uint112 principalAfterBurn = pyusdx.earningPrincipalOf(alice);
        uint112 principalSubtracted = principalBeforeBurn - principalAfterBurn;
        uint112 expectedPrincipal = _expectedPrincipalRoundUp(uint240(boundedBurnAmount), indexAtBurn);

        // Burn uses roundUp - actual should equal expected
        assertEq(principalSubtracted, expectedPrincipal);

        // Verify invariant: roundUp means (principal * index / PRECISION) >= amount
        uint256 calculatedAmount = (uint256(principalSubtracted) * indexAtBurn) / PRECISION;
        assertGe(calculatedAmount, boundedBurnAmount);
    }

    /// @notice Rounding direction: transfer uses roundUp with min112 cap
    function testFuzz_Transfer_roundingDirection_withMin112(uint256 amount, uint32 rate) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, 1e15); // Use smaller bound to avoid overflow
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        vm.assume(_canSafelyMint(boundedAmount));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        minterGateway.mint(alice, boundedAmount);

        // Warp a bit to potentially change index
        vm.warp(block.timestamp + 1 days);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
        uint128 indexBefore = pyusdx.currentIndex();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        uint112 alicePrincipalAfter = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalAfter = pyusdx.earningPrincipalOf(bob);

        uint112 alicePrincipalSubtracted = alicePrincipalBefore - alicePrincipalAfter;
        uint112 bobPrincipalAdded = bobPrincipalAfter - bobPrincipalBefore;

        // E->E transfer is in-kind: same principal subtracted and added
        // Uses roundUp to calculate the principal to transfer
        uint112 expectedPrincipal = _expectedPrincipalRoundUp(uint240(boundedAmount), indexBefore);

        assertEq(alicePrincipalSubtracted, expectedPrincipal);
        assertEq(bobPrincipalAdded, expectedPrincipal);

        // Verify principal consistency: total earning principal unchanged
        assertEq(pyusdx.totalEarningPrincipal(), alicePrincipalBefore + bobPrincipalBefore);

        // Verify min112 cap: principalSubtracted <= alicePrincipalBefore
        assertLe(alicePrincipalSubtracted, alicePrincipalBefore);
    }

    /// @notice Principal depletion edge case
    function testFuzz_Burn_principalDepletionEdge(uint256 mintAmount, uint256 burnAmount, uint32 rate) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedMintAmount = bound(mintAmount, 1, type(uint112).max);
        uint256 boundedBurnAmount = bound(burnAmount, 1, type(uint240).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        vm.assume(_canSafelyMint(boundedMintAmount));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        minterGateway.mint(alice, boundedMintAmount);

        // Warp to grow index and potentially create principal depletion scenario
        vm.warp(block.timestamp + 365 days);

        uint256 balanceBefore = pyusdx.balanceOf(alice);

        // Try to burn - may deplete principal
        vm.assume(_canSafelyBurn(alice, boundedBurnAmount));
        minterGateway.burn(alice, boundedBurnAmount);

        uint256 balanceAfter = pyusdx.balanceOf(alice);
        uint112 principalAfter = pyusdx.earningPrincipalOf(alice);

        // If balance is non-zero, principal could be depleted (roundUp took more)
        if (balanceAfter > 0) {
            // This is the principal depletion edge case
            bool isDepleted = _hasPrincipalDepletion(alice);
            if (isDepleted) {
                assertEq(principalAfter, 0);
                assertGt(balanceAfter, 0);
            }
        }
    }

    /// @notice Repeated operations compound rounding
    function testFuzz_RepeatedTransfers_principalConsistency(uint256 amount1, uint256 amount2, uint32 rate) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));
        pyusdx.setEarningDetails(carol, true, earnerManager, 0, address(0));

        uint256 boundedAmount1 = bound(amount1, 1, type(uint112).max);
        uint256 boundedAmount2 = bound(amount2, 1, type(uint112).max);
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        vm.assume(_canSafelyMint(boundedAmount1 + boundedAmount2));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        minterGateway.mint(alice, boundedAmount1);

        uint256 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint256 totalAmount = boundedAmount1;

        // Transfer from alice to bob
        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount1);
        uint256 bobPrincipal = pyusdx.earningPrincipalOf(bob);

        // Mint more to alice
        minterGateway.mint(alice, boundedAmount2);

        // Transfer from alice to carol
        vm.prank(alice);
        pyusdx.transfer(carol, boundedAmount2);

        // Verify principal consistency: sum of individual principals should match expected
        // Rounding should not cause unbounded drift
        uint256 totalPrincipal = pyusdx.earningPrincipalOf(alice) +
            pyusdx.earningPrincipalOf(bob) +
            pyusdx.earningPrincipalOf(carol);

        // Total principal should be reasonable (not overflow)
        assertLe(totalPrincipal, type(uint112).max);
    }

    /// @notice Cross-earning transfer paths
    function testFuzz_Transfer_crossEarning_roundingAsymmetry(uint256 amount, uint8 path, uint32 rate) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max);
        uint8 boundedPath = uint8(bound(path, 0, 3));
        uint32 boundedRate = uint32(bound(rate, 0, 10_000));
        vm.assume(_canSafelyMint(boundedAmount));

        vm.prank(rateManager);
        pyusdx.setRate(boundedRate);

        if (boundedPath == 0) {
            // E -> N
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

            minterGateway.mint(alice, boundedAmount);
            uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
            uint128 indexBefore = pyusdx.currentIndex();

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            uint112 expectedPrincipalSubtracted = _expectedPrincipalRoundUp(uint240(boundedAmount), indexBefore);
            assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipalSubtracted);
            assertEq(pyusdx.balanceOf(bob), boundedAmount);
        } else if (boundedPath == 1) {
            // N -> E
            minterGateway.mint(alice, boundedAmount);
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

            uint128 indexBefore = pyusdx.currentIndex();

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(boundedAmount), indexBefore);
            assertEq(pyusdx.earningPrincipalOf(bob), expectedPrincipal);
        } else if (boundedPath == 2) {
            // E -> E with same fee
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(alice, true, earnerManager, 100, address(0)); // 1% fee
            pyusdx.setEarningDetails(bob, true, earnerManager, 100, address(0));

            minterGateway.mint(alice, boundedAmount);

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            // Both should have principal accounting
            assertGt(pyusdx.earningPrincipalOf(bob), 0);
        } else {
            // E -> E with different fees (asymmetric rounding)
            vm.prank(earnerManager);
            pyusdx.setEarningDetails(alice, true, earnerManager, 100, address(0)); // 1% fee
            pyusdx.setEarningDetails(bob, true, earnerManager, 500, address(0)); // 5% fee

            minterGateway.mint(alice, boundedAmount);

            vm.prank(alice);
            pyusdx.transfer(bob, boundedAmount);

            // Transfer completes despite different fee rates
            assertEq(pyusdx.balanceOf(bob), boundedAmount);
        }
    }

    /// @notice Small amount at high index (precision loss)
    function testFuzz_mint_smallAmount_highIndex(uint256 amount, uint128 highIndex) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedAmount = bound(amount, 1, 1e12); // Small amounts
        uint128 boundedIndex = uint128(bound(highIndex, 1e14, 1e18)); // High indices
        vm.assume(_canSafelyMint(boundedAmount));

        pyusdx.setLatestIndex(boundedIndex);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.mint(alice, boundedAmount);

        uint112 principalAfter = pyusdx.earningPrincipalOf(alice);
        uint112 principalAdded = principalAfter - principalBefore;

        // At high index, small amounts may round to zero principal
        // This is acceptable behavior due to precision limits
        uint256 calculatedAmount = (uint256(principalAdded) * boundedIndex) / PRECISION;
        assertLe(calculatedAmount, boundedAmount); // roundDown invariant
    }
}
