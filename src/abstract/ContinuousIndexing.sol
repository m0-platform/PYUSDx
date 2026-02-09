// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { ContinuousIndexingMath } from "../../lib/m-extensions/lib/common/src/libs/ContinuousIndexingMath.sol";
import { IndexingMath } from "../../lib/m-extensions/lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../../lib/m-extensions/lib/common/src/libs/UIntMath.sol";
import { AccessControlUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IContinuousIndexing } from "../interfaces/IContinuousIndexing.sol";

/**
 * @title Continuous Indexing Storage Layout
 * @notice ERC-7201 namespaced storage layout for continuous indexing
 * @author M0 Labs
 */
abstract contract ContinuousIndexingStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.ContinuousIndexing
    struct ContinuousIndexingStorageStruct {
        uint128 latestIndex; // Current yield index (scaled by PRECISION = 1e12)
        uint40 latestUpdateTimestamp; // Timestamp of last index update
        uint32 rate; // Current annual yield rate in basis points (10000 = 100%)
        uint32 latestRate; // Cached rate for comparison (avoids redundant updates)
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.ContinuousIndexing")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _CONTINUOUS_INDEXING_STORAGE_LOCATION =
        0x07dfbdbf7845a3ae9b0fa004aa6f25f45af687f7eaaf7004254fc3fc0de62500;

    /**
     * @dev Get the storage location for ContinuousIndexing state
     * @return $ Storage pointer to ContinuousIndexingStorageStruct
     */
    function _getContinuousIndexingStorageLocation() internal pure returns (ContinuousIndexingStorageStruct storage $) {
        assembly {
            $.slot := _CONTINUOUS_INDEXING_STORAGE_LOCATION
        }
    }
}

/**
 * @title Abstract Continuous Indexing Contract
 * @notice Handles index updates and rate management for continuous yield accrual
 * @dev Uses ERC-7201 namespaced storage for state management
 * @author M0 Labs
 */
abstract contract ContinuousIndexing is IContinuousIndexing, AccessControlUpgradeable, ContinuousIndexingStorageLayout {
    /* ============ Roles ============ */

    /// @inheritdoc IContinuousIndexing
    bytes32 public constant RATE_MANAGER_ROLE = keccak256("RATE_MANAGER_ROLE");

    /* ============ Constants ============ */

    /// @notice Precision scaling for index calculations (1e12)
    uint256 public constant PRECISION = 1e12;

    /* ============ Modifiers ============ */

    /// @notice Modifier to restrict access to accounts with RATE_MANAGER_ROLE
    modifier onlyRateManager() {
        if (!hasRole(RATE_MANAGER_ROLE, msg.sender)) revert NotRateManager();
        _;
    }

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the contract with the given rate manager.
     * @param rateManager The address of a rate manager.
     */
    function __ContinuousIndexing_init(address rateManager) internal onlyInitializing {
        if (rateManager == address(0)) revert ZeroRateManager();
        _grantRole(RATE_MANAGER_ROLE, rateManager);

        ContinuousIndexingStorageStruct storage $ = _getContinuousIndexingStorageLocation();

        // TODO: should we initialize the rate at deployment?
        $.latestIndex = uint128(PRECISION);
        $.latestUpdateTimestamp = uint40(block.timestamp);
    }

    /* ============ Interactive Functions ============ */

    /**
     * @notice Updates the index to the current value
     * @dev Caches result in storage to avoid recalculation within the same block
     * @return currentIndex_ The new index value
     */
    function updateIndex() public virtual returns (uint128 currentIndex_) {
        ContinuousIndexingStorageStruct storage $ = _getContinuousIndexingStorageLocation();

        uint32 rate_ = $.rate;

        // Early return if index already updated this block and rate unchanged
        if ($.latestUpdateTimestamp == block.timestamp && $.latestRate == rate_) {
            return $.latestIndex;
        }

        // NOTE: `currentIndex()` depends on `latestRate`, so only update it after this.
        $.latestIndex = currentIndex_ = currentIndex();
        $.latestRate = rate_;
        $.latestUpdateTimestamp = uint40(block.timestamp);

        emit IndexUpdated(currentIndex_, rate_);
    }

    /**
     * @notice Sets the annual yield rate
     * @dev Only callable by RATE_MANAGER_ROLE. Rate is in basis points (10000 = 100%).
     *      This triggers an index update to apply the old rate for the elapsed period.
     * @param newRate New annual yield rate in basis points (0 to 10000, where 500 = 5%)
     */
    function setRate(uint32 newRate) public virtual onlyRateManager {
        // Validate rate doesn't exceed 100% (10000 basis points)
        if (newRate > 10000) revert RateTooHigh();

        ContinuousIndexingStorageStruct storage $ = _getContinuousIndexingStorageLocation();

        // Update index to apply old rate for elapsed period
        updateIndex();

        // Early return if rate unchanged
        if ($.rate == newRate) {
            return;
        }

        // Set new rate
        emit RateSet($.rate = newRate);

        // Update index to apply the new rate from now on
        updateIndex();
    }

    /* ============ View Functions ============ */

    /**
     * @notice Returns the current yield index
     * @return Current index value
     */
    function currentIndex() public view virtual returns (uint128) {
        ContinuousIndexingStorageStruct storage $ = _getContinuousIndexingStorageLocation();

        // NOTE: Safe to use unchecked here, since `block.timestamp` is always greater than `latestUpdateTimestamp`.
        unchecked {
            return
                // NOTE: Cap the index to `type(uint128).max` to prevent overflow in present value math.
                UIntMath.bound128(
                    ContinuousIndexingMath.multiplyIndicesDown(
                        $.latestIndex,
                        ContinuousIndexingMath.getContinuousIndex(
                            ContinuousIndexingMath.convertFromBasisPoints($.latestRate),
                            uint32(block.timestamp - $.latestUpdateTimestamp)
                        )
                    )
                );
        }
    }

    /**
     * @notice Returns the current yield rate
     * @return Current rate in basis points (10000 = 100%)
     */
    function rate() public view virtual returns (uint32) {
        return _getContinuousIndexingStorageLocation().rate;
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Returns the present amount (rounded down) given the principal amount and an index.
     * @param  principalAmount The principal amount.
     * @param  index           An index.
     * @return The present amount rounded down.
     */
    function _getPresentAmountRoundedDown(uint112 principalAmount, uint128 index) internal pure returns (uint240) {
        return uint240(IndexingMath.getPresentAmountRoundedDown(principalAmount, index));
    }

    /**
     * @dev    Returns the present amount (rounded down) given the principal amount, using the current index.
     * @param  principalAmount The principal amount.
     * @return The present amount rounded down.
     */
    function _getPresentAmountRoundedDown(uint112 principalAmount) internal view returns (uint240) {
        return uint240(IndexingMath.getPresentAmountRoundedDown(principalAmount, currentIndex()));
    }

    /**
     * @dev    Returns the principal amount (rounded down) given the present amount and an index.
     * @param  presentAmount The present amount.
     * @param  index         An index.
     * @return The principal amount rounded down.
     */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedDown(presentAmount, index);
    }

    /**
     * @dev    Returns the principal amount (rounded down) given the present amount, using the current index.
     * @param  presentAmount The present amount.
     * @return The principal amount rounded down.
     */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount) internal view returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedDown(presentAmount, currentIndex());
    }

    /**
     * @dev    Returns the principal amount (rounded up) given the present amount and an index.
     * @param  presentAmount The present amount.
     * @param  index         An index.
     * @return The principal amount rounded up.
     */
    function _getPrincipalAmountRoundedUp(uint240 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedUp(presentAmount, index);
    }

    /**
     * @dev    Returns the principal amount given the present amount, using the current index.
     * @param  presentAmount The present amount.
     * @return The principal amount rounded up.
     */
    function _getPrincipalAmountRoundedUp(uint240 presentAmount) internal view returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedUp(presentAmount, currentIndex());
    }
}
