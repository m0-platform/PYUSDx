// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { RateLimiter } from "../../src/abstract/RateLimiter.sol";

/// @title RateLimiterHarness
/// @notice Exposes internal functions of RateLimiter for testing.
contract RateLimiterHarness is RateLimiter {
    constructor() {
        _disableInitializers();
    }

    function initialize(address rateLimitManager) external initializer {
        __RateLimiter_init(rateLimitManager);
    }

    /// @dev Exposes _enforceRateLimit for testing.
    function enforceRateLimit(address issuer, uint256 amount) external {
        _enforceRateLimit(issuer, amount);
    }

    /// @dev Sets bucket state directly for edge-case testing.
    function setBucketState(
        address issuer,
        uint256 capacity,
        uint256 refillPerSecond,
        uint256 remainingAmount,
        uint40 lastRefillTime
    ) external {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        Bucket storage bucket = $.issuerBuckets[issuer];

        bucket.capacity = capacity;
        bucket.refillPerSecond = refillPerSecond;
        bucket.remainingAmount = remainingAmount;
        bucket.lastRefillTime = lastRefillTime;
    }

    /// @dev Gets bucket state for testing assertions.
    function getBucketState(
        address issuer
    )
        external
        view
        returns (uint256 capacity, uint256 refillPerSecond, uint256 remainingAmount, uint40 lastRefillTime)
    {
        RateLimiterStorage storage $ = _getRateLimiterStorage();
        Bucket storage bucket = $.issuerBuckets[issuer];

        capacity = bucket.capacity;
        refillPerSecond = bucket.refillPerSecond;
        remainingAmount = bucket.remainingAmount;
        lastRefillTime = bucket.lastRefillTime;
    }
}
