// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Test } from "../../lib/evm-m-extensions/lib/forge-std/src/Test.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IRateLimiter } from "../../src/abstract/interfaces/IRateLimiter.sol";

import { RateLimiterHarness } from "../harness/RateLimiterHarness.sol";

contract RateLimiterTests is Test {
    RateLimiterHarness public limiter;
    address public limiterProxy;

    address public manager = makeAddr("manager");
    address public admin = makeAddr("admin");
    address public issuer = makeAddr("issuer");
    address public alice = makeAddr("alice");

    function setUp() public {
        limiterProxy = UnsafeUpgrades.deployTransparentProxy(address(new RateLimiterHarness()), admin, "");
        limiter = RateLimiterHarness(limiterProxy);

        limiter.initialize(manager);
    }

    /* ============ Constructor ============ */

    function test_initialize_revertIfZeroManager() public {
        address implementation = address(new RateLimiterHarness());
        RateLimiterHarness newLimiter = RateLimiterHarness(
            UnsafeUpgrades.deployTransparentProxy(implementation, admin, "")
        );

        vm.expectRevert(IRateLimiter.ZeroRateLimitManager.selector);
        newLimiter.initialize(address(0));
    }

    function test_initialize() public {
        assertEq(limiter.RATE_LIMIT_MANAGER_ROLE(), keccak256("RATE_LIMIT_MANAGER_ROLE"));
        assertTrue(limiter.hasRole(limiter.RATE_LIMIT_MANAGER_ROLE(), manager));
    }

    /* ============ setRateLimit ============ */

    function test_setRateLimit_revertIfNotManager() public {
        vm.expectRevert();
        limiter.setRateLimit(issuer, 100e6, 1, true);
    }

    function test_setRateLimit_initialSetup() public {
        vm.expectEmit();
        emit IRateLimiter.RateLimitSet(issuer, 100e6, 10e6, true);

        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 10e6, true);

        (uint128 capacity, uint128 refillPerSecond) = limiter.getRateLimitConfig(issuer);

        assertEq(capacity, 100e6);
        assertEq(refillPerSecond, 10e6);
        assertEq(limiter.getRemainingAmount(issuer), 100e6);
    }

    function test_setRateLimit_updateKeepsRefilledAmount() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 10e6, true); // 10e6 per second

        // Consume some
        limiter.enforceRateLimit(issuer, 50e6);
        assertEq(limiter.getRemainingAmount(issuer), 50e6);

        // Time passes, refill occurs
        vm.warp(block.timestamp + 3);

        // Update with new capacity
        vm.prank(manager);
        limiter.setRateLimit(issuer, 200e6, 5e6, true);

        // Should have 50e6 + 3*10e6 = 80e6, capped at new capacity 200e6
        assertEq(limiter.getRemainingAmount(issuer), 80e6);

        (uint128 capacity, uint128 refillPerSecond) = limiter.getRateLimitConfig(issuer);

        assertEq(capacity, 200e6);
        assertEq(refillPerSecond, 5e6);
    }

    function test_setRateLimit_updateCapsAtNewCapacity() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 10e6, true); // 10e6 per second

        // Consume some
        limiter.enforceRateLimit(issuer, 50e6);

        // Time passes, would refill more than new capacity
        vm.warp(block.timestamp + 10);

        // Update with smaller capacity
        vm.prank(manager);
        limiter.setRateLimit(issuer, 30e6, 5e6, true);

        // 50e6 + 10*10e6 = 150e6, capped at new capacity 30e6
        assertEq(limiter.getRemainingAmount(issuer), 30e6);
    }

    function test_setRateLimit_remove() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 10, true);

        vm.expectEmit(address(limiter));
        emit IRateLimiter.RateLimitSet(issuer, 0, 0, false);

        vm.prank(manager);
        limiter.setRateLimit(issuer, 0, 0, false);

        // Unconfigured issuer returns unlimited
        (uint128 capacity, uint128 refillPerSecond) = limiter.getRateLimitConfig(issuer);

        assertEq(capacity, type(uint128).max);
        assertEq(refillPerSecond, 0);
        assertEq(limiter.getRemainingAmount(issuer), type(uint128).max);
    }

    function test_setRateLimit_remove_revertIfNonZeroCapacity() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 10, true);

        vm.expectRevert(
            abi.encodeWithSelector(IRateLimiter.InvalidRateLimitRemoval.selector, uint128(50e6), uint128(0))
        );

        vm.prank(manager);
        limiter.setRateLimit(issuer, 50e6, 0, false);
    }

    function test_setRateLimit_remove_revertIfNonZeroRefillPerSecond() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 10, true);

        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.InvalidRateLimitRemoval.selector, uint128(0), uint128(5)));

        vm.prank(manager);
        limiter.setRateLimit(issuer, 0, 5, false);
    }

    function test_setRateLimit_zeroRefillPerSecond() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 0, true);

        (uint128 capacity, uint128 refillPerSecond) = limiter.getRateLimitConfig(issuer);

        assertEq(capacity, 100e6);
        assertEq(refillPerSecond, 0);
        assertEq(limiter.getRemainingAmount(issuer), 100e6);
    }

    /* ============ getRateLimitConfig ============ */

    function test_getRateLimitConfig_unconfiguredIssuer() public {
        (uint128 capacity, uint128 refillPerSecond) = limiter.getRateLimitConfig(makeAddr("unknown"));

        assertEq(capacity, type(uint128).max);
        assertEq(refillPerSecond, 0);
    }

    /* ============ getRemainingAmount ============ */

    function test_getRemainingAmount_unconfiguredIssuer() public {
        assertEq(limiter.getRemainingAmount(makeAddr("unknown")), type(uint128).max);
    }

    function test_getRemainingAmount_noRefill() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 0, true);

        limiter.enforceRateLimit(issuer, 30e6);
        assertEq(limiter.getRemainingAmount(issuer), 70e6);

        // Time passes but no refill
        vm.warp(block.timestamp + 1000);
        assertEq(limiter.getRemainingAmount(issuer), 70e6);
    }

    function test_getRemainingAmount_withRefill() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 5e6, true); // 5e6 per second

        limiter.enforceRateLimit(issuer, 50e6);
        assertEq(limiter.getRemainingAmount(issuer), 50e6);

        // 10 seconds pass, refill = 10 * 5e6 = 50e6
        vm.warp(block.timestamp + 10);
        assertEq(limiter.getRemainingAmount(issuer), 100e6); // Capped at capacity
    }

    function test_getRemainingAmount_refillCapsAtCapacity() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 1000e6, true); // 1000e6 per second

        limiter.enforceRateLimit(issuer, 99e6);
        assertEq(limiter.getRemainingAmount(issuer), 1e6);

        // 1 second passes, would refill 1000, but capped at 100
        vm.warp(block.timestamp + 1);
        assertEq(limiter.getRemainingAmount(issuer), 100e6);
    }

    function test_getRemainingAmount_overflowCapsAtCapacity() public {
        // Set up bucket with values that would cause overflow
        limiter.setBucketState(issuer, 100e6, type(uint128).max, 1, uint40(block.timestamp));

        vm.warp(block.timestamp + 1);

        // remaining + refillPerSecond * elapsed would overflow, should cap at capacity
        assertEq(limiter.getRemainingAmount(issuer), 100e6);
    }

    /* ============ enforceRateLimit ============ */

    function test_enforceRateLimit_unconfiguredIssuer() public {
        // Should not revert for unconfigured issuer
        limiter.enforceRateLimit(makeAddr("unknown"), 1e18);
    }

    function test_enforceRateLimit_withinLimit() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 0, true);

        limiter.enforceRateLimit(issuer, 50e6);
        assertEq(limiter.getRemainingAmount(issuer), 50e6);
    }

    function test_enforceRateLimit_exceedsLimit() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 0, true);

        vm.expectRevert(
            abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, uint128(150e6), uint128(100e6))
        );
        limiter.enforceRateLimit(issuer, 150e6);
    }

    function test_enforceRateLimit_updatesLastRefillTime() public {
        vm.warp(block.timestamp + 1000);

        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 10e6, true);

        (, , , uint40 lastRefillTime) = limiter.getBucketState(issuer);
        assertEq(lastRefillTime, 1001);

        // Warp forward, lastRefillTime should update
        vm.warp(block.timestamp + 5);

        limiter.enforceRateLimit(issuer, 10e6);

        (, , , lastRefillTime) = limiter.getBucketState(issuer);
        assertEq(lastRefillTime, 1006);

        // Warp again and check that refill is calculated from new lastRefillTime
        vm.warp(block.timestamp + 5);

        // 90e6 + 5*10e6 = 140e6, capped at 100e6
        assertEq(limiter.getRemainingAmount(issuer), 100e6);
    }

    function test_enforceRateLimit_multipleConsumptions() public {
        vm.prank(manager);
        limiter.setRateLimit(issuer, 100e6, 0, true);

        limiter.enforceRateLimit(issuer, 30e6);
        assertEq(limiter.getRemainingAmount(issuer), 70e6);

        limiter.enforceRateLimit(issuer, 20e6);
        assertEq(limiter.getRemainingAmount(issuer), 50e6);

        limiter.enforceRateLimit(issuer, 50e6);
        assertEq(limiter.getRemainingAmount(issuer), 0e6);

        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, uint128(1), uint128(0)));
        limiter.enforceRateLimit(issuer, 1);
    }
}
