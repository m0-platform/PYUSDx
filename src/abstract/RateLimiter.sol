// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Math } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IRateLimiter } from "./interfaces/IRateLimiter.sol";

/// @notice ERC-7201 namespaced storage layout for token-bucket mint rate limiting.
abstract contract RateLimiterStorageLayout {
    struct Bucket {
        uint256 capacity; // Slot 0: Config
        uint256 refillPerSecond; // Slot 1: Config
        uint256 remainingAmount; // Slot 2: State (frequently updated)
        uint40 lastRefillTime; // Slot 3 (216 bits unused), good until year 36,812
    }

    /// @custom:storage-location erc7201:M0.storage.RateLimiter
    struct RateLimiterStorage {
        mapping(address issuer => Bucket) issuerBuckets;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.RateLimiter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _RATE_LIMITER_STORAGE_LOCATION =
        0xc562a0e1896fd38c0f41afa7c978cf8f41d7fa854ad2693d24bd9854180da900;

    function _getRateLimiterStorage() internal pure returns (RateLimiterStorage storage $) {
        assembly {
            $.slot := _RATE_LIMITER_STORAGE_LOCATION
        }
    }
}

/// @title  RateLimiter
/// @notice Generic token-bucket limiter mixin with access control.
abstract contract RateLimiter is IRateLimiter, RateLimiterStorageLayout, AccessControlUpgradeable {
    /* ============ Constants ============ */

    /// @inheritdoc IRateLimiter
    bytes32 public constant RATE_LIMITER_ROLE = keccak256("RATE_LIMITER_ROLE");

    /* ============ Initializer ============ */

    /// @dev   Initializes the rate limiter with a rate limit manager.
    /// @param rateLimitManager The address that will receive RATE_LIMITER_ROLE.
    function __RateLimiter_init(address rateLimitManager) internal onlyInitializing {
        if (rateLimitManager == address(0)) revert ZeroRateLimitManager();
        _grantRole(RATE_LIMITER_ROLE, rateLimitManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IRateLimiter
    function setRateLimit(
        address issuer,
        uint256 capacity,
        uint256 refillPerSecond,
        bool enabled
    ) external onlyRole(RATE_LIMITER_ROLE) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        Bucket storage bucket = $.issuerBuckets[issuer];

        emit RateLimitSet(issuer, capacity, refillPerSecond, enabled);

        if (!enabled) {
            if (capacity != 0 || refillPerSecond != 0) revert InvalidRateLimitRemoval(capacity, refillPerSecond);

            delete $.issuerBuckets[issuer];

            return;
        }

        // NOTE: Start with full bucket on first setup. Otherwise, calculate refilled amount and cap to new capacity.
        bucket.remainingAmount = bucket.lastRefillTime == 0
            ? capacity
            : Math.min(
                _calculateRemainingAmount(
                    bucket.remainingAmount,
                    bucket.capacity,
                    bucket.lastRefillTime,
                    bucket.refillPerSecond
                ),
                capacity
            );

        bucket.capacity = capacity;
        bucket.refillPerSecond = refillPerSecond;
        bucket.lastRefillTime = uint40(block.timestamp);
    }

    /* ============ External View Functions ============ */

    /// @inheritdoc IRateLimiter
    function getRateLimitConfig(address issuer) external view returns (uint256 capacity, uint256 refillPerSecond) {
        Bucket storage bucket = _getRateLimiterStorage().issuerBuckets[issuer];

        // NOTE: Unconfigured issuers have unlimited capacity
        if (bucket.lastRefillTime == 0) return (type(uint256).max, 0);

        return (bucket.capacity, bucket.refillPerSecond);
    }

    /// @inheritdoc IRateLimiter
    function getRemainingAmount(address issuer) external view returns (uint256) {
        Bucket storage bucket = _getRateLimiterStorage().issuerBuckets[issuer];

        // NOTE: Unconfigured issuers have unlimited capacity
        if (bucket.lastRefillTime == 0) return type(uint256).max;

        return
            _calculateRemainingAmount(
                bucket.remainingAmount,
                bucket.capacity,
                bucket.lastRefillTime,
                bucket.refillPerSecond
            );
    }

    /* ============ Internal Functions ============ */

    /// @dev    Enforces the rate limit, reverting if amount exceeds available capacity.
    /// @param  issuer Issuer key.
    /// @param  amount The amount to check.
    function _enforceRateLimit(address issuer, uint256 amount) internal {
        Bucket storage bucket = _getRateLimiterStorage().issuerBuckets[issuer];

        // NOTE: Unconfigured issuers have unlimited capacity
        if (bucket.lastRefillTime == 0) return;

        uint256 remainingAmount = _calculateRemainingAmount(
            bucket.remainingAmount,
            bucket.capacity,
            bucket.lastRefillTime,
            bucket.refillPerSecond
        );

        if (amount > remainingAmount) revert RateLimitExceeded(amount, remainingAmount);

        bucket.remainingAmount = remainingAmount - amount;
        bucket.lastRefillTime = uint40(block.timestamp);
    }

    /// @dev    Calculates the remaining amount after refill, capping at capacity on overflow.
    /// @param  remaining       Current remaining amount.
    /// @param  capacity        Maximum bucket capacity.
    /// @param  lastRefillTime  Timestamp of the last refill.
    /// @param  refillPerSecond Refill rate per second.
    /// @return The remaining amount after refill (capped at capacity).
    function _calculateRemainingAmount(
        uint256 remaining,
        uint256 capacity,
        uint40 lastRefillTime,
        uint256 refillPerSecond
    ) internal view returns (uint256) {
        // NOTE: No refill if rate is 0
        if (refillPerSecond == 0) return remaining;

        uint256 elapsed;

        // NOTE: `lastRefillTime` is always set from `block.timestamp`, so
        //       `block.timestamp >= lastRefillTime` and subtraction cannot underflow.
        unchecked {
            elapsed = uint40(block.timestamp) - lastRefillTime;
        }

        // NOTE: remaining(t) = min(capacity, remaining(t-1) + (t - t-1) * refillPerSecond)
        (bool mulOk, uint256 refillAmount) = Math.tryMul(elapsed, refillPerSecond);
        (bool addOk, uint256 total) = Math.tryAdd(remaining, refillAmount);

        return (!mulOk || !addOk) ? capacity : Math.min(total, capacity);
    }
}
