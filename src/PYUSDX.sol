// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPYUSDX} from "./interfaces/IPYUSDX.sol";
import {IERC20} from "m-extensions/lib/common/src/interfaces/IERC20.sol";
import {ERC20ExtendedUpgradeable} from "m-extensions/lib/common/src/ERC20ExtendedUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Freezable} from "m-extensions/src/components/freezable/Freezable.sol";
import {ForcedTransferable} from "m-extensions/src/components/forcedTransferable/ForcedTransferable.sol";
import {Pausable} from "m-extensions/src/components/pausable/Pausable.sol";
import {IndexingMath} from "m-extensions/lib/common/src/libs/IndexingMath.sol";
import {ContinuousIndexingMath} from "m-extensions/lib/common/src/libs/ContinuousIndexingMath.sol";
import {UIntMath} from "m-extensions/lib/common/src/libs/UIntMath.sol";

/**
 * @title PYUSDXLayout
 * @notice Storage layout for PYUSDX using ERC-7201 namespaced storage pattern
 * @author M0 Labs
 */
abstract contract PYUSDXLayout is IPYUSDX {
    /* ============ Structs ============ */

    /**
     * @notice Account state storage
     * @dev Packed to exactly 2 slots (64 bytes) for efficiency
     */
    struct Account {
        bool isEarning;           // 1 byte  - Whether account is actively earning yield
        uint240 balance;          // 30 bytes - Token balance (excluding accrued yield)
        uint112 earningPrincipal; // 14 bytes - Principal amount for yield calculations
        bool hasClaimRecipient;   // 1 byte  - Whether custom claim recipient is set
        bool hasEarnerDetails;    // 1 byte  - Whether earner details are set
        // 16 bytes padding to align to slot boundary
    }

    /**
     * @notice Continuous indexing state
     * @dev Stored in same storage struct to save slots
     */
    struct IndexingState {
        uint128 latestIndex;          // Current yield index (scaled by EXP_SCALED_ONE = 1e12)
        uint40 latestUpdateTimestamp; // Timestamp of last index update
        uint32 rate;                  // Current annual yield rate (basis points, scaled by 1e12)
        uint32 _latestRate;           // Previous rate for index calculation
    }

    /**
     * @notice Earner details for fee management
     */
    struct EarnerDetails {
        bool isWhitelisted;  // Whether account is whitelisted to earn
        uint16 feeRate;      // Fee rate in basis points (0-10000)
        address feeRecipient; // Recipient of fees
    }

    /**
     * @notice Main storage struct for PYUSDX
     * @dev Stored at ERC-7201 namespaced storage slot
     */
    struct PYUSDXStorageStruct {
        mapping(address => Account) accounts;         // Account states
        mapping(address => address) claimRecipients;   // Custom claim recipients
        mapping(address => EarnerDetails) earnerDetails; // Earner whitelisting and fees
        uint112 totalEarningPrincipal;                // Sum of all earning principals
        uint240 totalEarningSupply;                   // Total supply of earning tokens
        uint240 totalNonEarningSupply;                // Total supply of non-earning tokens
        IndexingState indexing;                       // Yield index and rate
    }

    /* ============ Storage Layout ============ */

    /// @dev ERC-7201 namespaced storage slot
    bytes32 private constant _PYUSDX_STORAGE_LOCATION =
        0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500;

    /**
     * @notice Get the storage location for PYUSDX state
     * @return $ Storage pointer to PYUSDXStorageStruct
     */
    function _getPYUSDXStorageLocation() internal pure returns (PYUSDXStorageStruct storage $) {
        assembly {
            $.slot := _PYUSDX_STORAGE_LOCATION
        }
    }

    /* ============ Constants ============ */

    /// @notice Precision scaling for index calculations (from IndexingMath)
    uint256 internal constant PRECISION = IndexingMath.EXP_SCALED_ONE; // 1e12
}

/**
 * @title PYUSDX
 * @notice Upgradeable, non-rebasing ERC20 token with claimable yield and compliance features
 * @dev Implements continuous indexing for yield accrual without balance rebase
 * @author M0 Labs
 */
contract PYUSDX is
    PYUSDXLayout,
    ERC20ExtendedUpgradeable,
    AccessControlUpgradeable,
    Freezable,
    ForcedTransferable,
    Pausable
{
    /* ============ Roles ============ */

    /// @notice Role that can set the yield rate
    bytes32 public constant RATE_MANAGER_ROLE = keccak256("RATE_MANAGER_ROLE");

    /// @notice Role that can manage earners
    bytes32 public constant EARNER_MANAGER_ROLE = keccak256("EARNER_MANAGER_ROLE");

    /* ============ Immutable Variables ============ */

    /// @notice Address of the Minter Gateway contract
    address public immutable minterGateway;

    /// @notice Address of the PYUSD token contract
    address public immutable pyusd;

    /* ============ Errors ============ */

    /// @notice Thrown when rate exceeds maximum (100%)
    error RateTooHigh();

    /// @notice Thrown when caller is not the minter gateway
    error NotMinterGateway();

    /* ============ Events ============ */

    /// @notice Emitted when the yield rate is set
    event RateSet(uint32 indexed newRate);

    /// @notice Emitted when the index is updated
    event IndexUpdated(uint128 indexed newIndex, uint256 indexed timestamp);

    /* ============ Constructor ============ */

    /**
     * @notice Constructs the PYUSDX contract
     * @dev Sets immutable variables; initializer must be called separately
     * @param _minterGateway Address of the Minter Gateway contract
     * @param _pyusd Address of the PYUSD token contract
     */
    constructor(address _minterGateway, address _pyusd) {
        if (_minterGateway == address(0)) revert ZeroMinterGateway();
        if (_pyusd == address(0)) revert ZeroPYUSD();
        minterGateway = _minterGateway;
        pyusd = _pyusd;
    }

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the PYUSDX contract
     * @dev Called by proxy deployment; sets up ERC20 metadata, roles, and initial state
     * @param admin Address that will have DEFAULT_ADMIN_ROLE
     * @param rateManager Address that will have RATE_MANAGER_ROLE
     * @param earnerManager Address that will have EARNER_MANAGER_ROLE
     * @param freezeManager Address that will have FREEZE_MANAGER_ROLE
     * @param forcedTransferManager Address that will have FORCED_TRANSFER_MANAGER_ROLE
     * @param pauser Address that will have PAUSER_ROLE
     */
    function initialize(
        address admin,
        address rateManager,
        address earnerManager,
        address freezeManager,
        address forcedTransferManager,
        address pauser
    ) external initializer {
        // Initialize parent contracts
        __ERC20ExtendedUpgradeable_init("PYUSDX", "PYUSDX", 6); // 6 decimals like PYUSD
        __AccessControl_init();
        __Freezable_init(freezeManager);
        __ForcedTransferable_init(forcedTransferManager);
        __Pausable_init(pauser);

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RATE_MANAGER_ROLE, rateManager);
        _grantRole(EARNER_MANAGER_ROLE, earnerManager);

        // Initialize indexing state
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        $.indexing.latestIndex = uint128(PRECISION); // Start at 1.0
        $.indexing.latestUpdateTimestamp = uint40(block.timestamp);
        $.indexing.rate = 0; // Start with 0% rate
        $.indexing._latestRate = 0;
    }

    /* ============ View Functions ============ */

    /**
     * @notice Returns the current yield index
     * @return Current index value
     */
    function currentIndex() external view returns (uint128) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return _calculateIndex($);
    }

    /**
     * @notice Returns the current yield rate
     * @return Current rate in basis points (scaled by 1e12)
     */
    function rate() external view returns (uint32) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return $.indexing.rate;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Calculates the current index based on elapsed time and rate
     * @dev Uses continuous compounding formula: e^(rate * time)
     * @param $ Storage pointer
     * @return The calculated index
     */
    function _calculateIndex(PYUSDXStorageStruct storage $) internal view returns (uint128) {
        uint40 lastUpdate = $.indexing.latestUpdateTimestamp;
        if (block.timestamp == lastUpdate) {
            return $.indexing.latestIndex;
        }

        uint32 currentRate = $.indexing.rate;
        if (currentRate == 0) {
            return $.indexing.latestIndex;
        }

        // Calculate time elapsed in seconds
        uint32 elapsedTime = uint32(block.timestamp - lastUpdate);

        // Calculate delta index using continuous compounding
        // getContinuousIndex returns e^(rate * time / seconds_per_year) scaled by 1e12
        uint48 deltaIndex = ContinuousIndexingMath.getContinuousIndex(currentRate, elapsedTime);

        // Multiply current index by delta index
        uint144 newIndex = ContinuousIndexingMath.multiplyIndicesDown($.indexing.latestIndex, deltaIndex);

        // Bound to uint128 max
        return UIntMath.bound128(newIndex);
    }

    /**
     * @notice Updates the index to the current value
     * @dev Caches result in storage to avoid recalculation within the same block
     * @return The new index value
     */
    function _updateIndex() internal returns (uint128) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        uint128 newIndex = _calculateIndex($);

        if (newIndex != $.indexing.latestIndex) {
            $.indexing.latestIndex = newIndex;
            $.indexing.latestUpdateTimestamp = uint40(block.timestamp);
            $.indexing._latestRate = $.indexing.rate;
            emit IndexUpdated(newIndex, block.timestamp);
        }

        return newIndex;
    }

    /* ============ Interface Implementation Stubs ============ */
    // NOTE: These will be implemented in subsequent phases as per the DTP

    /// @notice Stub implementation - to be implemented in Phase 2.8
    function balanceOf(address account) public view override(IERC20, IPYUSDX) returns (uint256) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return $.accounts[account].balance;
    }

    /// @notice Stub implementation - to be implemented in Phase 2.7
    function accruedYieldOf(address account) external view override returns (uint240) {
        revert("TODO: Phase 2.7");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.8
    function balanceWithYieldOf(address account) external view override returns (uint256) {
        revert("TODO: Phase 2.8");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.8
    function earningPrincipalOf(address account) external view override returns (uint112) {
        revert("TODO: Phase 2.8");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.12
    function claimRecipientFor(address account) external view override returns (address) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        address recipient = $.claimRecipients[account];
        return recipient == address(0) ? account : recipient;
    }

    /// @notice Stub implementation - to be implemented in Phase 2.15
    function isEarning(address account) external view override returns (bool) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return $.accounts[account].isEarning;
    }

    /// @notice Stub implementation - to be implemented in Phase 2.14
    function totalSupply() external pure override returns (uint256) {
        revert("TODO: Phase 2.14");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.14
    function totalEarningSupply() external view override returns (uint256) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return $.totalEarningSupply;
    }

    /// @notice Stub implementation - to be implemented in Phase 2.14
    function totalNonEarningSupply() external view override returns (uint256) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return $.totalNonEarningSupply;
    }

    /// @notice Stub implementation - to be implemented in Phase 2.2
    function mint(address account, uint256 amount) external override {
        revert("TODO: Phase 2.2");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.3
    function burn(address account, uint256 amount) external override {
        revert("TODO: Phase 2.3");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.11
    function claimFor(address account) external override returns (uint240) {
        revert("TODO: Phase 2.11");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.9
    function startEarningFor(address account) external override {
        revert("TODO: Phase 2.9");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.9
    function startEarningFor(address[] calldata accounts) external override {
        revert("TODO: Phase 2.9");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.10
    function stopEarningFor(address account) external override {
        revert("TODO: Phase 2.10");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.10
    function stopEarningFor(address[] calldata accounts) external override {
        revert("TODO: Phase 2.10");
    }

    /// @notice Stub implementation - to be implemented in Phase 2.12
    function setClaimRecipient(address account, address claimRecipient) external override {
        revert("TODO: Phase 2.12");
    }

    /// @notice Internal transfer hook - to be implemented in Phase 2.13
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        revert("TODO: Phase 2.13");
    }
}
