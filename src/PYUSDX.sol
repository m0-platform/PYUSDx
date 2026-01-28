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
        bool isEarning; // 1 byte  - Whether account is actively earning yield
        uint240 balance; // 30 bytes - Token balance (excluding accrued yield)
        uint112 earningPrincipal; // 14 bytes - Principal amount for yield calculations
        bool hasClaimRecipient; // 1 byte  - Whether custom claim recipient is set
        bool hasEarnerDetails; // 1 byte  - Whether earner details are set
        // 16 bytes padding to align to slot boundary
    }

    /**
     * @notice Continuous indexing state
     * @dev Stored in same storage struct to save slots
     */
    struct IndexingState {
        uint128 latestIndex; // Current yield index (scaled by EXP_SCALED_ONE = 1e12)
        uint40 latestUpdateTimestamp; // Timestamp of last index update
        uint32 rate; // Current annual yield rate (basis points, scaled by 1e12)
        uint32 _latestRate; // Previous rate for index calculation
    }

    /**
     * @notice Earner details for fee management
     */
    struct EarnerDetails {
        bool isWhitelisted; // Whether account is whitelisted to earn
        uint16 feeRate; // Fee rate in basis points (0-10000)
        address feeRecipient; // Recipient of fees
    }

    /**
     * @notice Main storage struct for PYUSDX
     * @dev Stored at ERC-7201 namespaced storage slot
     */
    struct PYUSDXStorageStruct {
        mapping(address => Account) accounts; // Account states
        mapping(address => address) claimRecipients; // Custom claim recipients
        mapping(address => EarnerDetails) earnerDetails; // Earner whitelisting and fees
        uint112 totalEarningPrincipal; // Sum of all earning principals
        uint240 totalEarningSupply; // Total supply of earning tokens
        uint240 totalNonEarningSupply; // Total supply of non-earning tokens
        IndexingState indexing; // Yield index and rate
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

    /**
     * @notice Calculates accrued yield for an earner
     * @dev Computes the difference between balance with yield and current balance.
     *      Formula: max(0, (earningPrincipal × currentIndex / PRECISION) - balance)
     * @param balance_ Current balance (excluding accrued yield)
     * @param earningPrincipal_ Principal amount for yield calculations
     * @param currentIndex_ Current yield index
     * @return Accrued yield amount (0 if no yield or negative)
     */
    function _getAccruedYield(uint240 balance_, uint112 earningPrincipal_, uint128 currentIndex_)
        internal
        pure
        returns (uint240)
    {
        // If no principal, no yield can be accrued
        if (earningPrincipal_ == 0) {
            return 0;
        }

        // Calculate balance with yield: principal × currentIndex / PRECISION
        uint256 balanceWithYield = IndexingMath.getPresentAmountRoundedDown(earningPrincipal_, currentIndex_);

        // Return the difference (accrued yield), ensuring no underflow
        uint256 balance = uint256(balance_);
        if (balanceWithYield > balance) {
            return uint240(balanceWithYield - balance);
        }
        return 0;
    }

    /* ============ Interface Implementation Stubs ============ */
    // NOTE: These will be implemented in subsequent phases as per the DTP

    /// @notice Stub implementation - to be implemented in Phase 2.8
    function balanceOf(address account) public view override(IERC20, IPYUSDX) returns (uint256) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return $.accounts[account].balance;
    }

    /**
     * @notice Returns accrued but unclaimed yield for an account
     * @dev Returns 0 for non-earners. For earners, calculates the difference
     *      between balance with yield and current balance.
     * @param account Account to query
     * @return Accrued yield amount
     */
    function accruedYieldOf(address account) external view override returns (uint240) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account memory accountData = $.accounts[account];

        // Non-earners have no accrued yield
        if (!accountData.isEarning) {
            return 0;
        }

        // Calculate accrued yield using internal helper
        return _getAccruedYield(accountData.balance, accountData.earningPrincipal, _calculateIndex($));
    }

    /**
     * @notice Returns balance plus accrued yield for an account
     * @dev For earners: returns balance + accruedYieldOf(account)
     *      For non-earners: returns balance (same as balanceOf)
     * @param account Account to query
     * @return Balance including any accrued but unclaimed yield
     */
    function balanceWithYieldOf(address account) external view override returns (uint256) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account memory accountData = $.accounts[account];

        uint256 balance = uint256(accountData.balance);

        // Non-earners: balance is same as stored balance
        if (!accountData.isEarning) {
            return balance;
        }

        // Earners: add accrued yield
        uint240 yield = _getAccruedYield(accountData.balance, accountData.earningPrincipal, _calculateIndex($));
        return balance + uint256(yield);
    }

    /**
     * @notice Returns the earning principal for an account
     * @dev The earning principal is the amount used to calculate yield.
     *      For earners: returns the stored earning principal.
     *      For non-earners: returns 0.
     * @param account Account to query
     * @return Earning principal amount (0 if not earning)
     */
    function earningPrincipalOf(address account) external view override returns (uint112) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account memory accountData = $.accounts[account];

        // Return 0 for non-earners
        if (!accountData.isEarning) {
            return 0;
        }

        return accountData.earningPrincipal;
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

    /**
     * @notice Returns the total earning principal across all earners
     * @return Total earning principal
     */
    function totalEarningPrincipal() external view returns (uint112) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return $.totalEarningPrincipal;
    }

    /**
     * @notice Returns the total supply of PYUSDX tokens
     * @dev Total supply is the sum of earning and non-earning supplies
     * @return Total supply (totalEarningSupply + totalNonEarningSupply)
     */
    function totalSupply() external view override returns (uint256) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return uint256($.totalEarningSupply) + uint256($.totalNonEarningSupply);
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

    /* ============ Earner Management ============ */
    // NOTE: These are minimal implementations for testing; full implementation in Phase 3.1

    /**
     * @notice Sets earner details for an account
     * @dev Only callable by EARNER_MANAGER_ROLE
     * @param account Account to set earner details for
     * @param isWhitelisted Whether the account is whitelisted to earn
     * @param feeRate Fee rate in basis points (0-10000)
     * @param feeRecipient Recipient of fees
     */
    function setEarnerDetails(address account, bool isWhitelisted, uint16 feeRate, address feeRecipient) external {
        if (!hasRole(EARNER_MANAGER_ROLE, msg.sender)) revert("not earner manager");
        if (feeRate > 10000) revert("fee rate too high");

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        $.earnerDetails[account] =
            EarnerDetails({isWhitelisted: isWhitelisted, feeRate: feeRate, feeRecipient: feeRecipient});
        $.accounts[account].hasEarnerDetails = true;
    }

    /**
     * @notice Gets earner details for an account
     * @param account Account to query
     * @return isWhitelisted Whether the account is whitelisted to earn
     * @return feeRate Fee rate in basis points
     * @return feeRecipient Recipient of fees
     */
    function getEarnerDetails(address account)
        external
        view
        returns (bool isWhitelisted, uint16 feeRate, address feeRecipient)
    {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        EarnerDetails memory details = $.earnerDetails[account];
        return (details.isWhitelisted, details.feeRate, details.feeRecipient);
    }

    /**
     * @notice Checks if an account is an approved earner
     * @param account Account to check
     * @return True if the account is whitelisted to earn
     */
    function earnerStatusFor(address account) external view returns (bool) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        return $.earnerDetails[account].isWhitelisted;
    }

    /* ============ Mint ============ */

    /**
     * @notice Mints PYUSDX to an account
     * @dev Only callable by the Minter Gateway
     * @param account Recipient of minted tokens
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) external override whenNotPaused {
        // Access control: only minter gateway can mint
        if (msg.sender != minterGateway) revert NotMinterGateway();

        // Pre-flight checks
        _revertIfFrozen(account);
        if (amount == 0) revert("zero amount");

        // Cast amount to uint240 (will revert on overflow)
        uint240 amount240 = UIntMath.safe240(amount);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // Update account balance
        $.accounts[account].balance += amount240;

        // Update supply tracking based on earning status
        if ($.accounts[account].isEarning) {
            $.totalEarningSupply += amount240;
        } else {
            $.totalNonEarningSupply += amount240;
        }

        emit Transfer(address(0), account, amount);
    }

    /**
     * @notice Burns PYUSDX from an account
     * @dev Only callable by the Minter Gateway
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function burn(address account, uint256 amount) external override whenNotPaused {
        // Access control: only minter gateway can burn
        if (msg.sender != minterGateway) revert NotMinterGateway();

        // Pre-flight checks
        _revertIfFrozen(account);
        if (amount == 0) revert("zero amount");

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // Check sufficient balance
        uint240 balance = $.accounts[account].balance;
        if (amount > balance) revert("insufficient balance");

        // Cast amount to uint240 (will revert on overflow)
        uint240 amount240 = UIntMath.safe240(amount);

        // Update account balance
        $.accounts[account].balance = balance - amount240;

        // Update supply tracking and adjust earning principal if applicable
        if ($.accounts[account].isEarning) {
            $.totalEarningSupply -= amount240;
            // If earner has earning principal, adjust it proportionally
            uint112 principal = $.accounts[account].earningPrincipal;
            if (principal > 0 && balance > 0) {
                // Calculate principal to remove: amount * principal / balance
                // Use round up to ensure we don't leave dust principal
                uint112 principalToRemove =
                    uint112((uint256(amount240) * uint256(principal) + uint256(balance) - 1) / uint256(balance));
                $.accounts[account].earningPrincipal = principal - principalToRemove;
                $.totalEarningPrincipal -= principalToRemove;
            }
        } else {
            $.totalNonEarningSupply -= amount240;
        }

        emit Transfer(account, address(0), amount);
    }

    /**
     * @notice Claims accrued yield for an account
     * @dev Permissionless function (anyone can claim for any earner).
     *      Calculates gross yield, deducts fee if applicable, updates account state,
     *      and transfers net yield to claim recipient.
     * @param account Account to claim yield for
     * @return netYield Amount of yield actually received (after fee deduction)
     */
    function claimFor(address account) external override whenNotPaused returns (uint240) {
        // Pre-flight checks
        _revertIfFrozen(account);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        // Account must be earning
        if (!accountData.isEarning) {
            revert("not earning");
        }

        // Update index to get current value
        uint128 idx = _updateIndex();

        // Calculate accrued yield
        uint240 grossYield = _getAccruedYield(accountData.balance, accountData.earningPrincipal, idx);

        // Early return if no yield to claim
        if (grossYield == 0) {
            return 0;
        }

        // Get earner details for fee calculation
        EarnerDetails memory earnerInfo = $.earnerDetails[account];
        uint16 feeRate = earnerInfo.feeRate;
        address feeRecipient = earnerInfo.feeRecipient;

        uint240 netYield = grossYield;
        uint240 fee = 0;

        // Calculate fee if applicable
        if (feeRate > 0) {
            fee = uint240((uint256(grossYield) * uint256(feeRate)) / 10000);
            netYield = grossYield - fee;
        }

        // Get claim recipient (returns account if not set)
        address recipient = $.claimRecipients[account];
        if (recipient == address(0)) {
            recipient = account;
        }

        // Store old principal for delta calculation
        uint112 oldPrincipal = accountData.earningPrincipal;

        // Update account state
        accountData.balance += grossYield;
        accountData.earningPrincipal =
            uint112(uint256(oldPrincipal) + IndexingMath.getPrincipalAmountRoundedUp(grossYield, idx));

        // Update totals
        $.totalEarningSupply += grossYield;
        $.totalEarningPrincipal += accountData.earningPrincipal - oldPrincipal;

        // Transfer fee if applicable
        if (fee > 0 && feeRecipient != address(0)) {
            $.accounts[feeRecipient].balance += fee;
            $.totalNonEarningSupply += fee;
            emit Transfer(address(0), feeRecipient, fee);
        }

        // Transfer net yield to recipient
        if (recipient != account) {
            $.accounts[recipient].balance += netYield;
            $.totalNonEarningSupply += netYield;
            emit Transfer(address(0), recipient, netYield);
        } else {
            // Recipient is the account itself, already added to balance
            emit Transfer(address(0), account, netYield);
        }

        emit Claimed(account, recipient, netYield);

        return netYield;
    }

    /**
     * @notice Starts earning yield for an account
     * @dev Permissionless function. Account must be whitelisted as earner and not already earning.
     *      Principal is calculated as: balance × PRECISION / currentIndex
     * @param account Account to start earning for
     */
    function startEarningFor(address account) external override whenNotPaused {
        // Pre-flight checks
        _revertIfFrozen(account);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // Account must be whitelisted as earner
        if (!$.earnerDetails[account].isWhitelisted) {
            revert("not approved earner");
        }

        Account storage accountData = $.accounts[account];

        // Account must not already be earning
        if (accountData.isEarning) {
            revert("already earning");
        }

        // Calculate principal: balance × PRECISION / currentIndex
        uint128 idx = _updateIndex();
        uint256 balance = uint256(accountData.balance);

        uint112 principal;
        if (balance > 0) {
            // Use getPrincipalAmountRoundedUp to get principal amount
            // This ensures we don't lose yield due to rounding
            principal = IndexingMath.getPrincipalAmountRoundedUp(uint240(balance), idx);
            $.totalEarningPrincipal += principal;
        }

        // Mark account as earning
        accountData.isEarning = true;
        accountData.earningPrincipal = principal;

        // Update supply tracking
        $.totalEarningSupply += uint240(balance);
        $.totalNonEarningSupply -= uint240(balance);

        emit StartedEarning(account);
    }

    /**
     * @notice Starts earning yield for multiple accounts
     * @dev Batch variant of startEarningFor. Loops through accounts and calls single variant logic.
     * @param accounts Array of accounts to start earning for
     */
    function startEarningFor(address[] calldata accounts) external override whenNotPaused {
        if (accounts.length == 0) {
            revert("array length zero");
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];

            // Pre-flight checks
            _revertIfFrozen(account);

            PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

            // Account must be whitelisted as earner
            if (!$.earnerDetails[account].isWhitelisted) {
                continue; // Skip non-approved earners
            }

            Account storage accountData = $.accounts[account];

            // Account must not already be earning
            if (accountData.isEarning) {
                continue; // Skip already earning accounts
            }

            // Calculate principal: balance × PRECISION / currentIndex
            // Note: _updateIndex is called each iteration to ensure fresh index
            // This could be optimized by caching, but keeping it simple for now
            uint128 idx = _updateIndex();
            uint256 balance = uint256(accountData.balance);

            uint112 principal;
            if (balance > 0) {
                principal = IndexingMath.getPrincipalAmountRoundedUp(uint240(balance), idx);
                $.totalEarningPrincipal += principal;
            }

            // Mark account as earning
            accountData.isEarning = true;
            accountData.earningPrincipal = principal;

            // Update supply tracking
            $.totalEarningSupply += uint240(balance);
            $.totalNonEarningSupply -= uint240(balance);

            emit StartedEarning(account);
        }
    }

    /**
     * @notice Stops earning yield for an account
     * @dev Permissionless function. Account must be earning and earner status must be false (removed).
     *      If yield has accrued, it is claimed before stopping earning.
     * @param account Account to stop earning for
     */
    function stopEarningFor(address account) external override whenNotPaused {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        Account storage accountData = $.accounts[account];

        // Account must be earning
        if (!accountData.isEarning) {
            revert("not earning");
        }

        // Account must not be whitelisted as earner (removed by EarnerManager)
        if ($.earnerDetails[account].isWhitelisted) {
            revert("still approved earner");
        }

        // Update index to get current value
        uint128 idx = _updateIndex();

        // Calculate and claim accrued yield if any
        // Note: This inlines the claim logic since claimFor is implemented in Phase 2.11
        uint256 balance = uint256(accountData.balance);
        uint112 principal = accountData.earningPrincipal;

        if (principal > 0 && balance > 0) {
            uint240 accruedYield = _getAccruedYield(accountData.balance, principal, idx);

            if (accruedYield > 0) {
                // Get earner details for fee calculation (direct storage access)
                EarnerDetails memory earnerInfo = $.earnerDetails[account];
                uint16 feeRate = earnerInfo.feeRate;
                address feeRecipient = earnerInfo.feeRecipient;

                uint240 grossYield = accruedYield;
                uint240 netYield = accruedYield;
                uint240 fee = 0;

                // Calculate fee if applicable
                if (feeRate > 0) {
                    fee = uint240((uint256(grossYield) * uint256(feeRate)) / 10000);
                    netYield = grossYield - fee;
                }

                // Get claim recipient
                address recipient = $.claimRecipients[account];
                if (recipient == address(0)) {
                    recipient = account;
                }

                // Update account balance and principal
                accountData.balance += grossYield;
                accountData.earningPrincipal =
                    uint112(uint256(principal) + IndexingMath.getPrincipalAmountRoundedUp(grossYield, idx));

                // Update total earning supply
                $.totalEarningSupply += grossYield;
                $.totalEarningPrincipal += accountData.earningPrincipal - principal;

                // Transfer fee if applicable
                if (fee > 0 && feeRecipient != address(0)) {
                    // Mint fee to fee recipient (same as claim balance increase)
                    $.accounts[feeRecipient].balance += fee;
                    $.totalNonEarningSupply += fee;
                    emit Transfer(address(0), feeRecipient, fee);
                }

                // Transfer net yield to recipient
                if (recipient != account) {
                    $.accounts[recipient].balance += netYield;
                    $.totalNonEarningSupply += netYield;
                    emit Transfer(address(0), recipient, netYield);
                } else {
                    // Recipient is the account itself, already added to balance
                    emit Transfer(address(0), account, netYield);
                }

                emit Claimed(account, recipient, netYield);
            }
        }

        // Clear earning state
        accountData.isEarning = false;
        uint112 oldPrincipal = accountData.earningPrincipal;
        accountData.earningPrincipal = 0;

        // Update totals
        balance = uint256(accountData.balance); // Re-read in case it changed from claim
        $.totalEarningPrincipal -= oldPrincipal;
        $.totalEarningSupply -= uint240(balance);
        $.totalNonEarningSupply += uint240(balance);

        emit StoppedEarning(account);
    }

    /**
     * @notice Stops earning yield for multiple accounts
     * @dev Batch variant of stopEarningFor. Loops through accounts and applies single variant logic.
     * @param accounts Array of accounts to stop earning for
     */
    function stopEarningFor(address[] calldata accounts) external override whenNotPaused {
        if (accounts.length == 0) {
            revert("array length zero");
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];

            PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

            Account storage accountData = $.accounts[account];

            // Account must be earning
            if (!accountData.isEarning) {
                continue; // Skip non-earning accounts
            }

            // Account must not be whitelisted as earner
            if ($.earnerDetails[account].isWhitelisted) {
                continue; // Skip approved earners
            }

            // Update index
            uint128 idx = _updateIndex();

            // Calculate and claim accrued yield if any
            uint256 balance = uint256(accountData.balance);
            uint112 principal = accountData.earningPrincipal;

            if (principal > 0 && balance > 0) {
                uint240 accruedYield = _getAccruedYield(accountData.balance, principal, idx);

                if (accruedYield > 0) {
                    // Get earner details for fee calculation (direct storage access)
                    EarnerDetails memory earnerInfo = $.earnerDetails[account];
                    uint16 feeRate = earnerInfo.feeRate;
                    address feeRecipient = earnerInfo.feeRecipient;

                    uint240 grossYield = accruedYield;
                    uint240 netYield = accruedYield;
                    uint240 fee = 0;

                    // Calculate fee if applicable
                    if (feeRate > 0) {
                        fee = uint240((uint256(grossYield) * uint256(feeRate)) / 10000);
                        netYield = grossYield - fee;
                    }

                    // Get claim recipient
                    address recipient = $.claimRecipients[account];
                    if (recipient == address(0)) {
                        recipient = account;
                    }

                    // Update account balance and principal
                    accountData.balance += grossYield;
                    accountData.earningPrincipal =
                        uint112(uint256(principal) + IndexingMath.getPrincipalAmountRoundedUp(grossYield, idx));

                    // Update total earning supply
                    $.totalEarningSupply += grossYield;
                    $.totalEarningPrincipal += accountData.earningPrincipal - principal;

                    // Transfer fee if applicable
                    if (fee > 0 && feeRecipient != address(0)) {
                        $.accounts[feeRecipient].balance += fee;
                        $.totalNonEarningSupply += fee;
                        emit Transfer(address(0), feeRecipient, fee);
                    }

                    // Transfer net yield to recipient
                    if (recipient != account) {
                        $.accounts[recipient].balance += netYield;
                        $.totalNonEarningSupply += netYield;
                        emit Transfer(address(0), recipient, netYield);
                    } else {
                        emit Transfer(address(0), account, netYield);
                    }

                    emit Claimed(account, recipient, netYield);
                }
            }

            // Clear earning state
            accountData.isEarning = false;
            uint112 oldPrincipal = accountData.earningPrincipal;
            accountData.earningPrincipal = 0;

            // Update totals
            balance = uint256(accountData.balance); // Re-read in case it changed
            $.totalEarningPrincipal -= oldPrincipal;
            $.totalEarningSupply -= uint240(balance);
            $.totalNonEarningSupply += uint240(balance);

            emit StoppedEarning(account);
        }
    }

    /* ============ Set Rate ============ */

    /**
     * @notice Sets the annual yield rate
     * @dev Only callable by RATE_MANAGER_ROLE. Rate is in basis points (1e12 scaling = 100%).
     *      This triggers an index update to apply the old rate for the elapsed period.
     * @param newRate New annual yield rate (0 to 10000 basis points, scaled by 1e12)
     */
    function setRate(uint32 newRate) external {
        // Access control: only rate manager can set rate
        if (!hasRole(RATE_MANAGER_ROLE, msg.sender)) revert("not rate manager");

        // Validate rate doesn't exceed 100% (10000 basis points)
        // Validate rate doesn't exceed 100% (10000 basis points)
        // Rate is in format: bps * PRECISION / 10000, so max 100% = 10000 * PRECISION / 10000 = PRECISION
        if (newRate > uint32(PRECISION)) revert RateTooHigh();

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // Update index to apply old rate for elapsed period
        _updateIndex();

        // Early return if rate unchanged
        if ($.indexing.rate == newRate) {
            return;
        }

        // Set new rate
        $.indexing.rate = newRate;
        emit RateSet(newRate);
    }

    /**
     * @notice Sets the claim recipient for an earner
     * @dev Only callable by EARNER_MANAGER_ROLE. Use address(0) to clear custom recipient.
     * @param account Earner account to set recipient for
     * @param claimRecipient Recipient for yield claims (address(0) to clear and revert to account)
     */
    function setClaimRecipient(address account, address claimRecipient) external override {
        // Access control: only earner manager can set claim recipient
        if (!hasRole(EARNER_MANAGER_ROLE, msg.sender)) revert("not earner manager");

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // Set claim recipient (address(0) is valid - it clears the custom recipient)
        $.claimRecipients[account] = claimRecipient;
        $.accounts[account].hasClaimRecipient = (claimRecipient != address(0));

        emit ClaimRecipientSet(account, claimRecipient);
    }

    /* ============ Internal Transfer Helpers ============ */

    /**
     * @notice Subtract earning amount from an account (for transfer out from earner)
     * @param account Account to subtract from
     * @param principalAmount Principal amount to subtract (pre-calculated from amount)
     */
    function _subtractEarningAmount(address account, uint112 principalAmount) private {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        unchecked {
            $.totalEarningPrincipal -= principalAmount;
            $.totalEarningSupply -= $.accounts[account].balance; // Balance is decreased after this
        }
    }

    /**
     * @notice Subtract non-earning amount from an account (for transfer out from non-earner)
     * @param account Account to subtract from
     * @param amount Amount to subtract
     */
    function _subtractNonEarningAmount(address account, uint240 amount) private {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        unchecked {
            $.totalNonEarningSupply -= amount;
        }
    }

    /**
     * @notice Add earning amount to an account (for transfer in to earner)
     * @param account Account to add to
     * @param principalAmount Principal amount to add (pre-calculated from amount)
     */
    function _addEarningAmount(address account, uint112 principalAmount) private {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        unchecked {
            $.totalEarningPrincipal += principalAmount;
            $.totalEarningSupply += $.accounts[account].balance; // Balance is increased after this
        }
    }

    /**
     * @notice Add non-earning amount to an account (for transfer in to non-earner)
     * @param account Account to add to
     * @param amount Amount to add
     */
    function _addNonEarningAmount(address account, uint240 amount) private {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        unchecked {
            $.totalNonEarningSupply += amount;
        }
    }

    /**
     * @notice Transfer amount in-kind between two earners or two non-earners
     * @param sender Sender account
     * @param recipient Recipient account
     * @param amount Amount to transfer
     * @param senderIsEarning Whether both are earning (if false, both are non-earning)
     */
    function _transferAmountInKind(
        address sender,
        address recipient,
        uint240 amount,
        bool senderIsEarning
    ) private {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // If both are earning, adjust principals
        if (senderIsEarning) {
            uint128 idx = _calculateIndex($);
            uint112 principalAmount = IndexingMath.getPrincipalAmountRoundedUp(amount, idx);

            unchecked {
                $.accounts[sender].earningPrincipal -= principalAmount;
                // Recipient principal will be increased after balance update
                $.accounts[recipient].earningPrincipal =
                    uint112(uint256($.accounts[recipient].earningPrincipal) + uint256(principalAmount));
            }
        }

        // Transfer balances (total supply unchanged for in-kind transfers)
        $.accounts[sender].balance -= amount;
        $.accounts[recipient].balance += amount;
    }

    /* ============ Transfer Override ============ */

    /**
     * @notice Internal transfer hook - handles transfers between earners and non-earners
     * @dev This hooks into both transfer and transferFrom from ERC20ExtendedUpgradeable
     *      Includes pause and frozen checks since the public functions are not virtual
     * @param sender Sender address
     * @param recipient Recipient address (must not be zero address)
     * @param amount Amount to transfer
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        // Pause check - contract must not be paused
        _requireNotPaused();

        // Frozen checks - both sender and recipient must not be frozen
        _revertIfFrozen(sender);
        _revertIfFrozen(recipient);
        // Validate recipient is not zero address
        if (recipient == address(0)) {
            revert("ERC20: transfer to zero address");
        }

        // Cast amount to uint240 with overflow protection
        uint240 amount240 = UIntMath.safe240(amount);

        // Get storage
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // Emit Transfer event at start (same as MToken pattern)
        emit Transfer(sender, recipient, amount240);

        // Check sender earning status once
        bool senderIsEarning = $.accounts[sender].isEarning;
        bool recipientIsEarning = $.accounts[recipient].isEarning;

        // Handle transfer based on earning status
        if (senderIsEarning == recipientIsEarning) {
            // In-kind transfer (both earning or both non-earning)
            _transferAmountInKind(sender, recipient, amount240, senderIsEarning);
        } else if (senderIsEarning) {
            // Earner to non-earner
            uint128 idx = _calculateIndex($);
            uint112 principalAmount = IndexingMath.getPrincipalAmountRoundedUp(amount240, idx);

            _subtractEarningAmount(sender, principalAmount);
            _addNonEarningAmount(recipient, amount240);

            // Transfer balances
            $.accounts[sender].balance -= amount240;
            $.accounts[recipient].balance += amount240;

            // Adjust sender principal
            unchecked {
                $.accounts[sender].earningPrincipal -= principalAmount;
            }
        } else {
            // Non-earner to earner
            uint128 idx = _calculateIndex($);
            uint112 principalAmount = IndexingMath.getPrincipalAmountRoundedDown(amount240, idx);

            _subtractNonEarningAmount(sender, amount240);
            _addEarningAmount(recipient, principalAmount);

            // Transfer balances
            $.accounts[sender].balance -= amount240;
            $.accounts[recipient].balance += amount240;

            // Adjust recipient principal
            unchecked {
                $.accounts[recipient].earningPrincipal =
                    uint112(uint256($.accounts[recipient].earningPrincipal) + uint256(principalAmount));
            }
        }

        // Update index at end
        _updateIndex();
    }
}
