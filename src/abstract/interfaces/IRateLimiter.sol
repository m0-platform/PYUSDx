// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  IRateLimiter
/// @notice Interface for token-bucket rate limiting functionality.
interface IRateLimiter {
    /* ============ Errors ============ */

    /// @notice Reverted when a mint would exceed the available rate limit.
    /// @param  requested Amount requested.
    /// @param  available Amount available in bucket.
    error RateLimitExceeded(uint256 requested, uint256 available);

    /// @notice Reverted when removing config with non-zero params.
    /// @param  capacity        Invalid non-zero capacity.
    /// @param  refillPerSecond Invalid non-zero refill rate.
    error InvalidRateLimitRemoval(uint256 capacity, uint256 refillPerSecond);

    /// @notice Reverted when rate limit manager is the zero address.
    error ZeroRateLimitManager();

    /* ============ Events ============ */

    /// @notice Emitted when issuer mint rate-limit params are updated.
    /// @param  issuer          Address of the issuer.
    /// @param  capacity        Maximum bucket capacity.
    /// @param  refillPerSecond Refill rate per second.
    /// @param  enabled         True when configured/updated, false when removed.
    event RateLimitSet(address indexed issuer, uint256 capacity, uint256 refillPerSecond, bool enabled);

    /* ============ Interactive Functions ============ */

    /// @notice Sets/removes issuer mint rate-limit configuration.
    /// @dev    MUST only be callable by RATE_LIMITER_ROLE.
    /// @param  issuer          Address of the issuer.
    /// @param  capacity        Maximum bucket capacity.
    /// @param  refillPerSecond Refill rate per second. Set to 0 for a one-time mint cap with no refill.
    /// @param  enabled         True to configure/update. False to remove (requires zero capacity/refillPerSecond).
    function setRateLimit(address issuer, uint256 capacity, uint256 refillPerSecond, bool enabled) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can set rate limits.
    function RATE_LIMIT_MANAGER_ROLE() external view returns (bytes32);

    /// @notice Returns issuer rate-limit config.
    /// @param  issuer          Address of the issuer.
    /// @return capacity        Maximum bucket capacity.
    /// @return refillPerSecond Refill rate per second.
    function getRateLimitConfig(address issuer) external view returns (uint256 capacity, uint256 refillPerSecond);

    /// @notice Returns currently available amount in issuer mint bucket (after virtual refill).
    /// @param  issuer Address of the issuer.
    /// @return The remaining amount in the bucket.
    function getRemainingAmount(address issuer) external view returns (uint256);
}
