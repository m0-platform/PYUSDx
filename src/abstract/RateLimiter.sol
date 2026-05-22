// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { Math } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { UIntMath } from "../../lib/evm-m-extensions/lib/common/src/libs/UIntMath.sol";

import { IRateLimiter } from "./interfaces/IRateLimiter.sol";

/// @notice ERC-7201 namespaced storage layout for token-bucket mint rate limiting.
abstract contract RateLimiterStorageLayout {
    struct Bucket {
        uint128 capacity; // --------┐ Slot 0: Config
        uint128 refillPerSecond; // -┘
        uint128 remainingAmount; // -┐ Slot 1: State (frequently updated)
        uint40 lastRefillTime; // ---┘ good until year 36,812
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
    bytes32 public constant RATE_LIMIT_MANAGER_ROLE = keccak256("RATE_LIMIT_MANAGER_ROLE");

    /* ============ Initializer ============ */

    /// @dev   Initializes the rate limiter with a rate limit manager.
    /// @param rateLimitManager The address that will receive RATE_LIMIT_MANAGER_ROLE.
    function __RateLimiter_init(address rateLimitManager) internal onlyInitializing {
        if (rateLimitManager == address(0)) revert ZeroRateLimitManager();

        _grantRole(RATE_LIMIT_MANAGER_ROLE, rateLimitManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IRateLimiter
    function setRateLimit(
        address issuer,
        uint128 capacity,
        uint128 refillPerSecond,
        bool enabled
    ) external onlyRole(RATE_LIMIT_MANAGER_ROLE) {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        Bucket storage bucket = $.issuerBuckets[issuer];

        emit RateLimitSet(issuer, capacity, refillPerSecond, enabled);

        if (!enabled) {
            if (capacity != 0 || refillPerSecond != 0) revert InvalidRateLimitRemoval(capacity, refillPerSecond);

            delete $.issuerBuckets[issuer];

            return;
        }

        if (capacity == 0) revert InvalidRateLimitConfig();

        // NOTE: Start with a full bucket only on first setup (lastRefillTime == 0), i.e. a never-configured
        //       issuer or one after removal. Otherwise carry over the time-adjusted remaining amount,
        //       capped to the new capacity.
        bucket.remainingAmount = bucket.lastRefillTime == 0
            ? capacity
            : uint128(
                Math.min(
                    _calculateRemainingAmount(
                        bucket.remainingAmount,
                        bucket.capacity,
                        bucket.lastRefillTime,
                        bucket.refillPerSecond
                    ),
                    capacity
                )
            );

        bucket.capacity = capacity;
        bucket.refillPerSecond = refillPerSecond;
        bucket.lastRefillTime = uint40(block.timestamp);
    }

    /* ============ External View Functions ============ */

    /// @inheritdoc IRateLimiter
    function getRateLimitConfig(address issuer) external view returns (uint128 capacity, uint128 refillPerSecond) {
        Bucket storage bucket = _getRateLimiterStorage().issuerBuckets[issuer];

        // NOTE: Unconfigured issuers have zero capacity.
        if (bucket.lastRefillTime == 0) return (0, 0);

        return (bucket.capacity, bucket.refillPerSecond);
    }

    /// @inheritdoc IRateLimiter
    function getRemainingAmount(address issuer) external view returns (uint128) {
        Bucket storage bucket = _getRateLimiterStorage().issuerBuckets[issuer];

        // NOTE: Unconfigured issuers have zero capacity.
        if (bucket.lastRefillTime == 0) return 0;

        return
            _calculateRemainingAmount(
                bucket.remainingAmount,
                bucket.capacity,
                bucket.lastRefillTime,
                bucket.refillPerSecond
            );
    }

    /* ============ Internal Functions ============ */

    /// @dev   Enforces the rate limit, reverting if amount exceeds available capacity.
    /// @param issuer Issuer key.
    /// @param amount The amount to check.
    function _enforceRateLimit(address issuer, uint256 amount) internal {
        Bucket storage bucket = _getRateLimiterStorage().issuerBuckets[issuer];

        if (bucket.lastRefillTime == 0) revert RateLimitNotConfigured(issuer);

        uint128 amount_ = UIntMath.safe128(amount);
        uint128 remainingAmount = _calculateRemainingAmount(
            bucket.remainingAmount,
            bucket.capacity,
            bucket.lastRefillTime,
            bucket.refillPerSecond
        );

        if (amount_ > remainingAmount) revert RateLimitExceeded(amount_, remainingAmount);

        unchecked {
            bucket.remainingAmount = remainingAmount - amount_;
        }

        bucket.lastRefillTime = uint40(block.timestamp);
    }

    /// @dev    Calculates the remaining amount after refill, capping at capacity on overflow.
    /// @param  remaining       Current remaining amount.
    /// @param  capacity        Maximum bucket capacity.
    /// @param  lastRefillTime  Timestamp of the last refill.
    /// @param  refillPerSecond Refill rate per second.
    /// @return The remaining amount after refill (capped at capacity).
    function _calculateRemainingAmount(
        uint128 remaining,
        uint128 capacity,
        uint40 lastRefillTime,
        uint128 refillPerSecond
    ) internal view returns (uint128) {
        // NOTE: No refill if rate is 0
        if (refillPerSecond == 0) return remaining;

        uint256 elapsed;

        // NOTE: `lastRefillTime` is always set from `block.timestamp`, so
        //       `block.timestamp >= lastRefillTime` and subtraction cannot underflow.
        unchecked {
            elapsed = uint40(block.timestamp) - lastRefillTime;
        }

        // NOTE: remaining(t) = min(capacity, remaining(t-1) + (t - t-1) * refillPerSecond)
        // Cannot overflow uint256: elapsed ≤ 2^40, refillPerSecond ≤ 2^128, remaining ≤ 2^128.
        uint256 total;
        unchecked {
            total = remaining + elapsed * refillPerSecond;
        }

        return uint128(Math.min(total, capacity));
    }
}
