// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC20ExtendedUpgradeable } from "../lib/evm-m-extensions/lib/common/src/ERC20ExtendedUpgradeable.sol";
import { Freezable } from "../lib/evm-m-extensions/src/components/freezable/Freezable.sol";
import { ForcedTransferable } from "../lib/evm-m-extensions/src/components/forcedTransferable/ForcedTransferable.sol";
import { Pausable } from "../lib/evm-m-extensions/src/components/pausable/Pausable.sol";
import { UIntMath } from "../lib/evm-m-extensions/lib/common/src/libs/UIntMath.sol";
import { ContinuousIndexingMath } from "../lib/evm-m-extensions/lib/common/src/libs/ContinuousIndexingMath.sol";
import { IndexingMath } from "../lib/evm-m-extensions/lib/common/src/libs/IndexingMath.sol";
import { AccessControlUpgradeable } from "../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IERC20 } from "../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { IPYUSDX } from "./IPYUSDX.sol";

/// @notice ERC-7201 namespaced storage layout for PYUSDX.
abstract contract PYUSDXStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDX
    struct PYUSDXStorageStruct {
        // Supply tracking
        uint256 totalSupply;
        // earner manager address (can manage earners and receive fees from their accounts)
        address earnerManager;
        // Account data
        mapping(address account => Account) accounts;
    }

    struct Account {
        // Slot 0: 256/256
        uint256 balance;
        // Slot 1: 200/256 — isEarning + index math (single SLOAD)
        uint128 lastIndex;
        uint40 lastUpdateTimestamp;
        uint32 earnerRate;
        // Slot 2: 160/256 — claim config (cold path)
        address claimRecipient;
        // Slot 3: 128/256 — principal + fee (co-read in _claim)
        uint112 earningPrincipal;
        uint16 feeRate;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDX")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PYUSDX_STORAGE_LOCATION =
        0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500;

    function _getPYUSDXStorageLocation() internal pure returns (PYUSDXStorageStruct storage $) {
        assembly {
            $.slot := _PYUSDX_STORAGE_LOCATION
        }
    }
}

/// @title PYUSDX
/// @author M0 Labs
/// @notice PYUSDX upgradeable ERC20 non-rebasing token with claimable yield.
contract PYUSDX is
    IPYUSDX,
    PYUSDXStorageLayout,
    AccessControlUpgradeable,
    ERC20ExtendedUpgradeable,
    Freezable,
    ForcedTransferable,
    Pausable
{
    /* ============ Constants ============ */

    /// @notice Maximum fee rate in bps (100%).
    uint16 public constant ONE_HUNDRED_PERCENT = 10_000;

    /// @notice Precision scaling for index calculations (1e12).
    uint128 public constant EXP_SCALED_ONE = 1e12;

    /// @notice The role that can issue PYUSDX tokens.
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    /* ============ Constructor ============ */

    /// @notice Constructs the PYUSDX implementation contract.
    constructor() {
        _disableInitializers();
    }

    /* ============ Modifiers ============ */

    /// @notice Restricts access to only the Earner Manager address.
    modifier onlyEarnerManager() {
        if (msg.sender != earnerManager()) revert NotEarnerManager();
        _;
    }

    /* ============ Initializer ============ */

    /// @notice Initializes the PYUSDX contract.
    /// @param name The token name.
    /// @param symbol The token symbol.
    /// @param admin The admin address with DEFAULT_ADMIN_ROLE.
    /// @param pauser The pauser address with PAUSER_ROLE.
    /// @param freezeManager The freeze manager address with FREEZE_MANAGER_ROLE.
    /// @param forcedTransferManager The forced transfer manager address with FORCED_TRANSFER_MANAGER_ROLE.
    /// @param earnerManager_ The earner manager address.
    function initialize(
        string calldata name,
        string calldata symbol,
        address admin,
        address pauser,
        address freezeManager,
        address forcedTransferManager,
        address earnerManager_
    ) external initializer {
        if (admin == address(0)) revert ZeroAdmin();

        __ERC20ExtendedUpgradeable_init(name, symbol, 6);
        __ForcedTransferable_init(forcedTransferManager);
        __Freezable_init(freezeManager);
        __Pausable_init(pauser);

        _setEarnerManager(earnerManager_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IPYUSDX
    function mint(address account, uint256 amount) external onlyRole(ISSUER_ROLE) whenNotPaused {
        _revertIfZeroAccount(account);
        _revertIfFrozen(account);
        _revertIfZeroAmount(amount);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        $.totalSupply += amount;

        if (isEarning(account)) {
            _addEarningAmount($, account, amount);
        } else {
            _addNonEarningAmount($, account, amount);
        }

        emit Transfer(address(0), account, amount);
    }

    /// @inheritdoc IPYUSDX
    function burn(address account, uint256 amount) external onlyRole(ISSUER_ROLE) whenNotPaused {
        _revertIfZeroAccount(account);
        _revertIfFrozen(account);
        _revertIfZeroAmount(amount);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        if (isEarning(account)) {
            _subtractEarningAmount($, account, amount);
        } else {
            _subtractNonEarningAmount($, account, amount);
        }

        $.totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    /// @inheritdoc IPYUSDX
    function claimFor(
        address account
    ) external whenNotPaused returns (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFee) {
        return _claimFor(account);
    }

    /// @inheritdoc IPYUSDX
    function claimFor(
        address[] calldata accounts
    )
        external
        whenNotPaused
        returns (uint256[] memory yieldWithFees, uint256[] memory fees, uint256[] memory yieldNetOfFees)
    {
        if (accounts.length == 0) revert ArrayLengthZero();

        yieldWithFees = new uint256[](accounts.length);
        fees = new uint256[](accounts.length);
        yieldNetOfFees = new uint256[](accounts.length);

        for (uint256 i; i < accounts.length; ++i) {
            (yieldWithFees[i], fees[i], yieldNetOfFees[i]) = _claimFor(accounts[i]);
        }
    }

    /// @inheritdoc IPYUSDX
    function setAccountInfo(
        address account,
        uint32 earnerRate,
        uint16 feeRate,
        address claimRecipient
    ) external onlyEarnerManager {
        _setAccountInfo(account, earnerRate, feeRate, claimRecipient);
    }

    /// @inheritdoc IPYUSDX
    function setAccountInfo(
        address[] calldata accounts,
        uint32[] calldata earnerRates,
        uint16[] calldata feeRates,
        address[] calldata claimRecipients
    ) external onlyEarnerManager {
        if (accounts.length == 0) revert ArrayLengthZero();
        if (
            accounts.length != earnerRates.length ||
            accounts.length != feeRates.length ||
            accounts.length != claimRecipients.length
        ) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i; i < accounts.length; ++i) {
            _setAccountInfo(accounts[i], earnerRates[i], feeRates[i], claimRecipients[i]);
        }
    }

    /// @inheritdoc IPYUSDX
    function distributeReward(address account, uint256 amount) external onlyEarnerManager whenNotPaused {
        _revertIfZeroAccount(account);
        _revertIfFrozen(account);
        _revertIfZeroAmount(amount);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        $.totalSupply += amount;

        // Add to recipient
        if (isEarning(account)) {
            _addEarningAmount($, account, amount);
        } else {
            _addNonEarningAmount($, account, amount);
        }

        emit Transfer(address(0), account, amount);
    }

    /// @inheritdoc IPYUSDX
    function setEarnerManager(address earnerManager_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setEarnerManager(earnerManager_);
    }

    /* ============ External/Public view functions ============ */

    /// @inheritdoc IPYUSDX
    function earnerManager() public view returns (address) {
        return _getPYUSDXStorageLocation().earnerManager;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256) {
        return _getPYUSDXStorageLocation().totalSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override returns (uint256) {
        return _getPYUSDXStorageLocation().accounts[account].balance;
    }

    /// @inheritdoc IPYUSDX
    function accruedYieldAndFeeOf(
        address account
    ) public view returns (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFee) {
        Account storage accountInfo = _getPYUSDXStorageLocation().accounts[account];

        if (accountInfo.earnerRate == 0) return (0, 0, 0);

        uint256 balanceWithYield = _getPresentAmountRoundedDown(accountInfo.earningPrincipal, currentIndexOf(account));
        yieldWithFee = balanceWithYield > accountInfo.balance ? balanceWithYield - accountInfo.balance : 0;
        uint16 feeRate = accountInfo.feeRate;

        if (feeRate == 0 || yieldWithFee == 0) return (yieldWithFee, 0, yieldWithFee);

        unchecked {
            fee = (yieldWithFee * feeRate) / ONE_HUNDRED_PERCENT;
            yieldNetOfFee = yieldWithFee - fee;
        }
    }

    /// @inheritdoc IPYUSDX
    function accruedYieldOf(address account) public view returns (uint256 yieldNetOfFee) {
        (, , yieldNetOfFee) = accruedYieldAndFeeOf(account);
    }

    /// @inheritdoc IPYUSDX
    function accruedFeeOf(address account) public view returns (uint256 fee) {
        (, fee, ) = accruedYieldAndFeeOf(account);
    }

    /// @inheritdoc IPYUSDX
    function balanceWithYieldOf(address account) external view returns (uint256) {
        unchecked {
            return balanceOf(account) + accruedYieldOf(account);
        }
    }

    /// @inheritdoc IPYUSDX
    function isEarning(address account) public view returns (bool) {
        return _getPYUSDXStorageLocation().accounts[account].earnerRate > 0;
    }

    /// @inheritdoc IPYUSDX
    function getAccountEarningInfo(
        address account
    ) external view returns (uint32 earnerRate, uint16 feeRate, address claimRecipient) {
        Account memory accountInfo = _getPYUSDXStorageLocation().accounts[account];
        return (accountInfo.earnerRate, accountInfo.feeRate, claimRecipientFor(account));
    }

    /// @inheritdoc IPYUSDX
    function claimRecipientFor(address account) public view returns (address) {
        address claimRecipient = _getPYUSDXStorageLocation().accounts[account].claimRecipient;
        return claimRecipient == address(0) ? account : claimRecipient;
    }

    /// @inheritdoc IPYUSDX
    function earningPrincipalOf(address account) external view returns (uint112) {
        return _getPYUSDXStorageLocation().accounts[account].earningPrincipal;
    }

    /// @inheritdoc IPYUSDX
    function lastIndexOf(address account) public view returns (uint128) {
        return _getPYUSDXStorageLocation().accounts[account].lastIndex;
    }

    /// @inheritdoc IPYUSDX
    function lastUpdateTimestampOf(address account) external view returns (uint40) {
        return _getPYUSDXStorageLocation().accounts[account].lastUpdateTimestamp;
    }

    /// @inheritdoc IPYUSDX
    function currentIndexOf(address account) public view returns (uint128) {
        Account storage accountInfo = _getPYUSDXStorageLocation().accounts[account];

        if (accountInfo.earnerRate == 0) return EXP_SCALED_ONE;

        unchecked {
            return
                UIntMath.bound128(
                    ContinuousIndexingMath.multiplyIndicesDown(
                        accountInfo.lastIndex,
                        ContinuousIndexingMath.getContinuousIndex(
                            ContinuousIndexingMath.convertFromBasisPoints(accountInfo.earnerRate),
                            uint32(block.timestamp - accountInfo.lastUpdateTimestamp)
                        )
                    )
                );
        }
    }

    /* ============ Hooks For Internal Interactive Functions ============ */

    /**
     * @dev   Hook called before freezing an account.
     * @param account   The account to be frozen.
     */
    function _beforeFreeze(address account) internal override {
        _claimFor(account);

        _stopEarningFor(account);

        super._beforeFreeze(account);
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev Sets the earner manager.
     * @param earnerManager_ The address of the new earner manager.
     */
    function _setEarnerManager(address earnerManager_) internal {
        if (earnerManager_ == address(0)) revert ZeroEarnerManager();

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // If the new earner manager is the same as the current one, do nothing.
        if (earnerManager_ == $.earnerManager) return;

        $.earnerManager = earnerManager_;

        emit EarnerManagerSet(earnerManager_);
    }

    /// @dev Internal implementation for setting earning details.
    // TODO: limits on earner rate?
    function _setAccountInfo(address account, uint32 earnerRate, uint16 feeRate, address claimRecipient) internal {
        _revertIfZeroAccount(account);
        if (feeRate > ONE_HUNDRED_PERCENT) revert FeeRateTooHigh(feeRate);

        // Disable earning should have all earning-related fields set to 0, address(0).
        if (earnerRate == 0 && (feeRate != 0 || claimRecipient != address(0))) revert InvalidAccountInfo();

        bool wasEarning = isEarning(account);
        bool willBeEarning = earnerRate > 0;

        // No change for a non-earner, no-op action.
        if (!wasEarning && !willBeEarning) return;

        Account storage accountInfo = _getPYUSDXStorageLocation().accounts[account];

        // No change for an earner, no-op action. Happens rarely, consider removing.
        if (
            wasEarning &&
            willBeEarning &&
            earnerRate == accountInfo.earnerRate &&
            feeRate == accountInfo.feeRate &&
            claimRecipient == accountInfo.claimRecipient
        ) return;

        // Update account info.
        emit AccountInfoUpdated(account, earnerRate, feeRate, claimRecipient);

        // Claim accrued yield for earners before changing their earning status & configuration.
        _claimFor(account);

        // Option 1: Disable earning for an earner, resetting all earning-related fields to 0, address(0).
        if (wasEarning && !willBeEarning) {
            _stopEarningFor(account);

            return;
        }

        // Update index for the account before potentially changing its earner rate.
        _updateIndexOf(account);
        accountInfo.earnerRate = earnerRate;
        accountInfo.feeRate = feeRate;
        accountInfo.claimRecipient = claimRecipient;

        // Enable earning for a non-earner.
        if (!wasEarning && willBeEarning) {
            accountInfo.lastIndex = EXP_SCALED_ONE;
            accountInfo.lastUpdateTimestamp = uint40(block.timestamp);
            accountInfo.earningPrincipal = _getPrincipalAmountRoundedDown(accountInfo.balance, EXP_SCALED_ONE);

            emit StartedEarning(account);
        }
    }

    /// @dev Snapshots the account's current index into storage. Returns the new index value.
    function _updateIndexOf(address account) internal returns (uint128 currentIndex) {
        if (!isEarning(account)) return EXP_SCALED_ONE;

        Account storage accountInfo = _getPYUSDXStorageLocation().accounts[account];

        accountInfo.lastIndex = currentIndex = currentIndexOf(account);
        accountInfo.lastUpdateTimestamp = uint40(block.timestamp);

        emit IndexUpdated(account, currentIndex);
    }

    /// @dev Internal claim implementation.
    function _claimFor(address account) internal returns (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFee) {
        (yieldWithFee, fee, yieldNetOfFee) = accruedYieldAndFeeOf(account);

        if (yieldWithFee == 0) return (0, 0, 0);

        // Emit the appropriate `YieldClaimed` and `Transfer` events.
        emit YieldClaimed(account, yieldNetOfFee);
        emit Transfer(address(0), account, yieldWithFee);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // No change in principal, only the balance is updated to include the newly claimed yield.
        $.totalSupply += yieldWithFee;
        $.accounts[account].balance += yieldWithFee;

        address claimRecipient = claimRecipientFor(account);

        // Transfer net yield to claim recipient (if different from account).
        if (claimRecipient != account && yieldNetOfFee > 0) {
            _transfer(account, claimRecipient, yieldNetOfFee);
        }

        if (fee == 0) return (yieldWithFee, 0, yieldNetOfFee);

        // Transfer fee to an earner manager.
        address feeRecipient = $.earnerManager;

        emit FeeClaimed(account, feeRecipient, fee);

        _transfer(account, feeRecipient, fee);
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev Reverts if amount is zero.
    function _revertIfZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /// @dev Reverts if account is zero address.
    function _revertIfZeroAccount(address account) internal pure {
        if (account == address(0)) revert ZeroAccount();
    }

    /// @dev   Stops earning for an account, claiming any accrued yield first.
    /// @param account The account to stop earning for.
    function _stopEarningFor(address account) internal {
        // If account is not an earner, return early.
        if (!isEarning(account)) return;

        Account storage accountInfo = _getPYUSDXStorageLocation().accounts[account];

        // Clean up all account info fields except balance.
        delete accountInfo.earningPrincipal;
        delete accountInfo.earnerRate;
        delete accountInfo.feeRate;
        delete accountInfo.claimRecipient;
        delete accountInfo.lastIndex;
        delete accountInfo.lastUpdateTimestamp;

        emit StoppedEarning(account);
    }

    /// @dev Adds non-earning amount to an account's balance and total supply.
    /// @param $ The storage pointer.
    /// @param account The account to add the amount to.
    /// @param amount The amount to add (must be safe240).
    function _addNonEarningAmount(PYUSDXStorageStruct storage $, address account, uint256 amount) internal {
        // NOTE: Safe to use unchecked here since overflow of the total supply is checked in `mint`.
        unchecked {
            $.accounts[account].balance += amount;
        }
    }

    /// @dev Adds earning amount to an account's balance and earning principal.
    /// @param $ The storage pointer.
    /// @param account The account to add the amount to.
    /// @param amount The present amount to add.
    function _addEarningAmount(PYUSDXStorageStruct storage $, address account, uint256 amount) internal {
        uint112 principal = _getPrincipalAmountRoundedDown(amount, _updateIndexOf(account));

        // NOTE: Safe to use unchecked here since overflow of the total supply is checked in `mint`.
        unchecked {
            $.accounts[account].balance += amount;
            $.accounts[account].earningPrincipal += principal;
        }
    }

    /// @dev Subtracts non-earning amount from an account's balance and total supply.
    /// @param $ The storage pointer.
    /// @param account The account to subtract the amount from.
    /// @param amount The amount to subtract (must be safe240).
    function _subtractNonEarningAmount(PYUSDXStorageStruct storage $, address account, uint256 amount) internal {
        uint256 accountBalance = $.accounts[account].balance;

        if (accountBalance < amount) {
            revert InsufficientBalance(account, accountBalance, amount);
        }

        unchecked {
            $.accounts[account].balance -= amount;
        }
    }

    /// @dev Subtracts earning amount from an account's balance and total earning supply/principal.
    /// @param $ The storage pointer.
    /// @param account The account to subtract the amount from.
    /// @param amount The present amount to subtract (must be safe240).
    function _subtractEarningAmount(PYUSDXStorageStruct storage $, address account, uint256 amount) internal {
        uint256 accountBalance = $.accounts[account].balance;

        if (accountBalance < amount) {
            revert InsufficientBalance(account, accountBalance, amount);
        }

        uint112 principal = _getPrincipalAmountRoundedUp(amount, _updateIndexOf(account));
        uint112 earningPrincipal = $.accounts[account].earningPrincipal;

        unchecked {
            $.accounts[account].balance -= amount;

            // NOTE: `min112` prevents underflow.
            $.accounts[account].earningPrincipal = earningPrincipal - UIntMath.min112(principal, earningPrincipal);
        }
    }

    /// @dev Required override for ERC20ExtendedUpgradeable.
    /// @param sender    The sender's address.
    /// @param recipient The recipient's address.
    /// @param amount    The amount to be transferred.
    function _transfer(address sender, address recipient, uint256 amount) internal override whenNotPaused {
        _revertIfFrozen(msg.sender);
        _revertIfFrozen(sender);
        _revertIfFrozen(recipient);
        _revertIfZeroAccount(recipient);

        emit Transfer(sender, recipient, amount);

        if (amount == 0) return;

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // Subtract from sender
        if (isEarning(sender)) {
            _subtractEarningAmount($, sender, amount);
        } else {
            _subtractNonEarningAmount($, sender, amount);
        }

        // Add to recipient
        if (isEarning(recipient)) {
            _addEarningAmount($, recipient, amount);
        } else {
            _addNonEarningAmount($, recipient, amount);
        }
    }

    /// @dev   Internal force transfer implementation to seize funds from frozen accounts.
    /// @param frozenAccount The frozen account to transfer from.
    /// @param recipient     The account to transfer to.
    /// @param amount        The amount to transfer.
    function _forceTransfer(address frozenAccount, address recipient, uint256 amount) internal override {
        _revertIfZeroAccount(recipient);
        _revertIfNotFrozen(frozenAccount);

        emit Transfer(frozenAccount, recipient, amount);
        emit ForcedTransfer(frozenAccount, recipient, msg.sender, amount);

        if (amount == 0) return;

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // Subtract from frozen (non-earning) account
        _subtractNonEarningAmount($, frozenAccount, amount);

        // Add to recipient (can be earning or non-earning)
        if (isEarning(recipient)) {
            _addEarningAmount($, recipient, amount);
        } else {
            _addNonEarningAmount($, recipient, amount);
        }
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev Returns the present amount (rounded down) given the principal amount and an index.
    function _getPresentAmountRoundedDown(uint112 principalAmount, uint128 index) internal pure returns (uint256) {
        return IndexingMath.getPresentAmountRoundedDown(principalAmount, index);
    }

    /// @dev Returns the principal amount (rounded down) given the present amount and an index.
    function _getPrincipalAmountRoundedDown(uint256 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedDown(uint240(presentAmount), index);
    }

    /// @dev Returns the principal amount (rounded up) given the present amount and an index.
    function _getPrincipalAmountRoundedUp(uint256 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedUp(uint240(presentAmount), index);
    }
}
