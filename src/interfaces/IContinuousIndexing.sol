// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/**
 * @title Interface for Continuous Indexing
 * @notice Defines events, errors, and functions for continuous yield indexing
 * @author M0 Labs
 */
interface IContinuousIndexing {
    /* ============ Errors ============ */

    /// @notice Thrown when caller lacks RATE_MANAGER_ROLE
    error NotRateManager();

    /// @notice Thrown when rate exceeds maximum (100%)
    error RateTooHigh();

    /// @notice Thrown when the rate manager address is zero.
    error ZeroRateManager();

    /* ============ Events ============ */

    /**
     * @notice Emitted when the yield rate is set
     * @param newRate New annual yield rate in basis points (10000 = 100%)
     */
    event RateSet(uint32 indexed newRate);

    /**
     * @notice Emitted when the yield index is updated
     * @param index The new index value
     * @param rate The current rate in basis points
     */
    event IndexUpdated(uint128 indexed index, uint32 indexed rate);

    /* ============ Interactive Functions ============ */

    /**
     * @notice Updates the index to the current value
     * @return The new index value
     */
    function updateIndex() external returns (uint128);

    /**
     * @notice Sets the annual yield rate
     * @dev Only callable by RATE_MANAGER_ROLE. Rate is in basis points (10000 = 100%).
     * @param newRate New annual yield rate in basis points (0 to 10000, where 500 = 5%)
     */
    function setRate(uint32 newRate) external;

    /* ============ View Functions ============ */

    /**
     * @notice Returns the current yield index
     * @return Current index value
     */
    function currentIndex() external view returns (uint128);

    /**
     * @notice Returns the current yield rate
     * @return Current rate in basis points (10000 = 100%, 500 = 5%)
     */
    function rate() external view returns (uint32);

    /**
     * @notice Role that can set the yield rate
     * @return The role identifier
     */
    function RATE_MANAGER_ROLE() external view returns (bytes32);
}
