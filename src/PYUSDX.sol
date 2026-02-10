// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { ERC20ExtendedUpgradeable } from "../lib/m-extensions/lib/common/src/ERC20ExtendedUpgradeable.sol";
import { Freezable } from "../lib/m-extensions/src/components/freezable/Freezable.sol";
import { ForcedTransferable } from "../lib/m-extensions/src/components/forcedTransferable/ForcedTransferable.sol";
import { Pausable } from "../lib/m-extensions/src/components/pausable/Pausable.sol";
import { UIntMath } from "../lib/m-extensions/lib/common/src/libs/UIntMath.sol";
import { ContinuousIndexingMath } from "../lib/m-extensions/lib/common/src/libs/ContinuousIndexingMath.sol";
import { ContinuousIndexing } from "./abstract/ContinuousIndexing.sol";
import { IPYUSDX } from "./interfaces/IPYUSDX.sol";

/// @notice ERC-7201 namespaced storage layout for PYUSDX.
abstract contract PYUSDXStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDX
    struct PYUSDXStorageStruct {
        // Supply tracking
        uint240 totalSupply;
        // Account data
        mapping(address account => Account) accounts;
    }

    struct Account {
        // Slot 0
        uint240 balance;
        uint16 feeRate;
        // Slot 1
        address earnerManager;
        uint32 lastIndexUpdate;
        uint24 rateBps;
        bool isEarning;
        // Slot 2
        address claimRecipient;
        // Slot 3
        uint128 lastIndex;
        uint112 earningPrincipal;
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
    PYUSDXStorageLayout,
    IPYUSDX,
    ContinuousIndexing,
    ERC20ExtendedUpgradeable,
    Freezable,
    ForcedTransferable,
    Pausable
{
    /* ============ Constants ============ */

    /// @notice Maximum fee rate (100%).
    uint16 public constant MAX_FEE_RATE = 10_000;

    /// @notice The role that can mint PYUSDX tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice The role that can manage earners.
    bytes32 public constant EARNER_MANAGER_ROLE = keccak256("EARNER_MANAGER_ROLE");

    /* ============ Immutable Variables ============ */

    /// @notice The Minter Gateway contract address.
    address public immutable minterGateway;

    /* ============ Constructor ============ */

    /// @notice Constructs the PYUSDX implementation contract.
    /// @param minterGateway_ The Minter Gateway contract address.
    constructor(address minterGateway_) {
        _disableInitializers();

        if (minterGateway_ == address(0)) revert ZeroMinterGateway();
        minterGateway = minterGateway_;
    }

    /* ============ Modifiers ============ */

    /// @notice Restricts access to only the Minter Gateway contract.
    modifier onlyMinterGateway() {
        if (msg.sender != minterGateway) revert NotMinterGateway();
        _;
    }

    /// @notice Restricts access to only the Earner Manager for a specific account.
    /// @dev    If no earner manager is assigned (address(0)), access is allowed.
    modifier onlyEarnerManager(address account) {
        _checkEarnerManager(account);
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
    /// @param earnerManager The earner manager address with EARNER_MANAGER_ROLE.
    /// @param rateManager The rate manager address with RATE_MANAGER_ROLE.
    function initialize(
        string calldata name,
        string calldata symbol,
        address admin,
        address pauser,
        address freezeManager,
        address forcedTransferManager,
        address earnerManager,
        address rateManager
    ) external initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (earnerManager == address(0)) revert ZeroEarnerManager();

        // Initialize ERC20Extended with 6 decimals (PYUSD standard)
        __ERC20ExtendedUpgradeable_init(name, symbol, 6);

        __ContinuousIndexing_init(rateManager);
        __ForcedTransferable_init(forcedTransferManager);
        __Freezable_init(freezeManager);
        __Pausable_init(pauser);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minterGateway);
        _grantRole(EARNER_MANAGER_ROLE, earnerManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IPYUSDX
    function mint(address account, uint256 amount) external onlyMinterGateway whenNotPaused {
        _revertIfZeroAmount(amount);
        _revertIfZeroAccount(account);
        _revertIfFrozen(account);

        uint240 safeAmount = UIntMath.safe240(amount);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        unchecked {
            if (uint256($.totalSupply) + safeAmount > type(uint240).max) {
                revert OverflowsPrincipalOfTotalSupply();
            }

            $.totalSupply += safeAmount;
        }

        if ($.accounts[account].isEarning) {
            uint128 accountIndex = _updateAccountIndex(account);
            _addEarningAmount($, account, safeAmount, accountIndex);
        } else {
            _addNonEarningAmount($, account, safeAmount);
        }

        emit Transfer(address(0), account, amount);
    }

    /// @inheritdoc IPYUSDX
    function burn(address account, uint256 amount) external onlyMinterGateway whenNotPaused {
        _revertIfZeroAmount(amount);
        _revertIfFrozen(account);

        uint240 safeAmount = UIntMath.safe240(amount);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        unchecked {
            $.totalSupply -= safeAmount;
        }

        if ($.accounts[account].isEarning) {
            uint128 accountIndex = _updateAccountIndex(account);
            _subtractEarningAmount($, account, safeAmount, accountIndex);
        } else {
            _subtractNonEarningAmount($, account, safeAmount);
        }

        emit Transfer(account, address(0), amount);
    }

    /// @inheritdoc IPYUSDX
    function claimFor(address account) external returns (uint240 yield) {
        return _claim(account);
    }

    /// @inheritdoc IPYUSDX
    function setEarningDetails(
        address account,
        bool isEarning_,
        uint16 feeRate,
        address claimRecipient
    ) external onlyEarnerManager(account) {
        _setEarningDetails(account, isEarning_, feeRate, claimRecipient, currentIndex());
    }

    /// @inheritdoc IPYUSDX
    function setEarningDetails(
        address[] calldata accounts,
        bool[] calldata isEarning_,
        uint16[] calldata feeRates,
        address[] calldata claimRecipients
    ) external {
        uint256 len = accounts.length;
        if (len == 0) revert ArrayLengthZero();
        if (len != isEarning_.length || len != feeRates.length || len != claimRecipients.length) {
            revert ArrayLengthMismatch();
        }

        uint128 currentIndex_ = currentIndex();

        for (uint256 i; i < len; ++i) {
            _checkEarnerManager(accounts[i]);
            _setEarningDetails(accounts[i], isEarning_[i], feeRates[i], claimRecipients[i], currentIndex_);
        }
    }

    /// @dev   Overrides Freezable.freeze to stop earning before freezing.
    /// @param account The account to freeze.
    function freeze(address account) external override onlyRole(FREEZE_MANAGER_ROLE) {
        _stopEarningFor(account);
        _freeze(_getFreezableStorageLocation(), account);
    }

    /// @dev   Overrides Freezable.freezeAccounts to stop earning before freezing.
    /// @param accounts The accounts to freeze.
    function freezeAccounts(address[] calldata accounts) external override onlyRole(FREEZE_MANAGER_ROLE) {
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();
        for (uint256 i; i < accounts.length; ++i) {
            _stopEarningFor(accounts[i]);
            _freeze($, accounts[i]);
        }
    }

    /* ============ View Functions ============ */

    /// @notice Returns the balance of an account.
    function balanceOf(address account) public view override returns (uint256) {
        return _getPYUSDXStorageLocation().accounts[account].balance;
    }

    /// @notice Returns the total supply of tokens.
    function totalSupply() public view override returns (uint256) {
        return _getPYUSDXStorageLocation().totalSupply;
    }

    /// @notice Returns whether an account is earning yield.
    function isEarning(address account) external view returns (bool) {
        return _getPYUSDXStorageLocation().accounts[account].isEarning;
    }

    /// @notice Returns whether multiple accounts are earning yield.
    function isEarning(address[] calldata accounts) external view returns (bool[] memory) {
        bool[] memory results = new bool[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            results[i] = _getPYUSDXStorageLocation().accounts[accounts[i]].isEarning;
        }
        return results;
    }

    /// @notice Returns the claim recipient for an account.
    function claimRecipientFor(address account) external view returns (address) {
        address recipient = _getPYUSDXStorageLocation().accounts[account].claimRecipient;
        return recipient == address(0) ? account : recipient;
    }

    /// @notice Returns the claim recipients for multiple accounts.
    function claimRecipientsFor(address[] calldata accounts) external view returns (address[] memory) {
        address[] memory recipients = new address[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            address recipient = _getPYUSDXStorageLocation().accounts[accounts[i]].claimRecipient;
            recipients[i] = recipient == address(0) ? accounts[i] : recipient;
        }
        return recipients;
    }

    /// @notice Returns earning details for a single account.
    function getEarningDetails(
        address account
    ) external view returns (bool isEarning_, address earnerManager, uint16 feeRate, address claimRecipient) {
        Account memory accountData = _getPYUSDXStorageLocation().accounts[account];
        return (accountData.isEarning, accountData.earnerManager, accountData.feeRate, accountData.claimRecipient);
    }

    /// @notice Returns earning details for multiple accounts.
    function getEarningDetails(
        address[] calldata accounts
    )
        external
        view
        returns (
            bool[] memory isEarning_,
            address[] memory earnerManagers,
            uint16[] memory feeRates,
            address[] memory claimRecipients
        )
    {
        uint256 len = accounts.length;
        isEarning_ = new bool[](len);
        earnerManagers = new address[](len);
        feeRates = new uint16[](len);
        claimRecipients = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            Account memory accountData = _getPYUSDXStorageLocation().accounts[accounts[i]];
            isEarning_[i] = accountData.isEarning;
            earnerManagers[i] = accountData.earnerManager;
            feeRates[i] = accountData.feeRate;
            claimRecipients[i] = accountData.claimRecipient;
        }
    }

    /// @notice Returns the accrued yield for an account.
    function accruedYieldOf(address account) public view returns (uint240) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        if (!accountData.isEarning) return 0;

        // Calculate present value from principal using per-account index
        uint240 balanceWithYield = _getPresentAmountRoundedDown(accountData.earningPrincipal, currentAccountIndex(account));

        // Yield = present value - stored balance
        uint240 balance = accountData.balance;
        unchecked {
            return balanceWithYield > balance ? balanceWithYield - balance : 0;
        }
    }

    /// @notice Returns the balance including yield for an account.
    function balanceWithYieldOf(address account) external view returns (uint256) {
        return balanceOf(account) + accruedYieldOf(account);
    }

    /// @notice Returns the earning principal for an account.
    function earningPrincipalOf(address account) external view returns (uint112) {
        return _getPYUSDXStorageLocation().accounts[account].earningPrincipal;
    }

    /// @inheritdoc IPYUSDX
    function currentAccountIndex(address account) public view returns (uint128) {
        Account storage accountData = _getPYUSDXStorageLocation().accounts[account];

        if (!accountData.isEarning) return uint128(PRECISION);

        unchecked {
            return UIntMath.bound128(
                ContinuousIndexingMath.multiplyIndicesDown(
                    accountData.lastIndex,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(accountData.rateBps),
                        uint32(block.timestamp - accountData.lastIndexUpdate)
                    )
                )
            );
        }
    }

    /// @inheritdoc IPYUSDX
    function setEarnerRate(address account, uint24 newRateBps) external onlyRateManager {
        _setEarnerRate(account, newRateBps);
    }

    /// @inheritdoc IPYUSDX
    function setEarnerRateBatch(address[] calldata accounts, uint24[] calldata rates) external onlyRateManager {
        if (accounts.length != rates.length) revert ArrayLengthMismatch();
        for (uint256 i; i < accounts.length; ++i) {
            _setEarnerRate(accounts[i], rates[i]);
        }
    }

    /* ============ Internal Functions ============ */

    /// @dev Internal implementation for setting earning details.
    function _setEarningDetails(
        address account,
        bool isEarning_,
        uint16 feeRate,
        address claimRecipient,
        uint128 currentIndex_
    ) internal {
        _revertIfZeroAccount(account);
        if (feeRate > MAX_FEE_RATE) revert FeeRateTooHigh(feeRate);
        if (!isEarning_ && feeRate != 0) revert InvalidDetails();

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        bool wasEarning = accountData.isEarning;

        if (!wasEarning && !isEarning_) return;

        // same earning state with same settings
        if (wasEarning && isEarning_ && accountData.feeRate == feeRate && accountData.claimRecipient == claimRecipient)
            return;

        emit EarningDetailsSet(account, isEarning_, msg.sender, feeRate, claimRecipient);

        // Claim any accrued yield first
        if (wasEarning) {
            _claim(account);
        }

        uint240 balance = accountData.balance;

        // Enable earning (non-earner to earner)
        if (isEarning_ && !wasEarning) {
            accountData.earnerManager = msg.sender;
            accountData.isEarning = true;
            accountData.lastIndex = uint128(PRECISION);
            accountData.lastIndexUpdate = uint32(block.timestamp);

            uint112 principal = _getPrincipalAmountRoundedDown(balance, currentIndex_);
            accountData.earningPrincipal = principal;
        } else if (isEarning_ && wasEarning) {
            // Update manager if caller is different (takeover scenario)
            if (accountData.earnerManager != msg.sender) {
                accountData.earnerManager = msg.sender;
            }
        }

        // Disable earning (earner → non-earner)
        else if (!isEarning_ && wasEarning) {
            accountData.isEarning = false;
            accountData.earningPrincipal = 0;
            accountData.earnerManager = address(0);
            accountData.lastIndex = 0;
            accountData.lastIndexUpdate = 0;
            accountData.rateBps = 0;
        }

        accountData.feeRate = feeRate;
        accountData.claimRecipient = claimRecipient;
    }

    /// @dev Snapshots the account's current index into storage. Returns the new index value.
    function _updateAccountIndex(address account) internal returns (uint128 newIndex) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        if (!accountData.isEarning) return uint128(PRECISION);

        newIndex = currentAccountIndex(account);
        accountData.lastIndex = newIndex;
        accountData.lastIndexUpdate = uint32(block.timestamp);
    }

    /// @dev Internal implementation for setting an individual earner's yield rate.
    function _setEarnerRate(address account, uint24 newRateBps) internal {
        if (newRateBps > 10_000) revert RateTooHigh();

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        if (!accountData.isEarning) revert NotEarning();

        // Snapshot index at old rate before changing
        _updateAccountIndex(account);

        uint24 oldRate = accountData.rateBps;
        if (oldRate == newRateBps) return;

        accountData.rateBps = newRateBps;

        emit EarnerRateSet(account, oldRate, newRateBps);
    }

    /// @dev Internal claim implementation.
    function _claim(address account) internal returns (uint240 yield) {
        _requireNotPaused();
        _revertIfFrozen(account);

        yield = accruedYieldOf(account);
        if (yield == 0) return 0;

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        // Calculate fee
        uint16 feeRate = accountData.feeRate;
        uint240 fee;
        if (feeRate > 0) {
            unchecked {
                fee = uint240((uint256(yield) * feeRate) / MAX_FEE_RATE);
            }
        }
        uint240 netYield = yield - fee;

        // Add full yield to balance (yield is minted)
        unchecked {
            accountData.balance += yield;
            $.totalSupply += yield;
        }

        address claimRecipient = accountData.claimRecipient;
        if (claimRecipient == address(0)) {
            claimRecipient = account;
        }

        emit Claimed(account, claimRecipient, yield);
        emit Transfer(address(0), account, yield);

        // Transfer fee to earner manager (if any)
        if (fee > 0) {
            address earnerManager = accountData.earnerManager;
            _transfer(account, earnerManager, fee);
        }

        // Transfer net yield to claim recipient (if different from account)
        if (claimRecipient != account && netYield > 0) {
            _transfer(account, claimRecipient, netYield);
        }

        return yield;
    }

    /// @dev   Stops earning for an account, claiming any accrued yield first.
    /// @param account The account to stop earning for.
    function _stopEarningFor(address account) internal {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        if (!accountData.isEarning) return;

        // Claim any accrued yield first
        _claim(account);

        accountData.isEarning = false;
        accountData.earningPrincipal = 0;
        accountData.earnerManager = address(0);
        accountData.feeRate = 0;
        accountData.claimRecipient = address(0);
        accountData.lastIndex = 0;
        accountData.lastIndexUpdate = 0;
        accountData.rateBps = 0;

        emit StoppedEarning(account);
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
        uint240 safeAmount = UIntMath.safe240(amount);

        // Subtract from frozen (non-earning) account
        _subtractNonEarningAmount($, frozenAccount, safeAmount);

        // Add to recipient (can be earning or non-earning)
        if ($.accounts[recipient].isEarning) {
            uint128 recipientIndex = _updateAccountIndex(recipient);
            _addEarningAmount($, recipient, safeAmount, recipientIndex);
        } else {
            _addNonEarningAmount($, recipient, safeAmount);
        }
    }

    /// @dev Reverts if the caller is not authorized to manage earning details for the account.
    function _checkEarnerManager(address account) internal view {
        if (!hasRole(EARNER_MANAGER_ROLE, msg.sender)) revert NotEarnerManager();

        address storedManager = _getPYUSDXStorageLocation().accounts[account].earnerManager;

        // No manager assigned: allow management takeover
        if (storedManager == address(0)) return;

        // Caller is this account's current manager
        if (msg.sender == storedManager) return;

        // Current manager lost their role: allow management takeover
        if (!hasRole(EARNER_MANAGER_ROLE, storedManager)) return;

        // Account is already managed by another active manager: revert
        revert EarnerDetailsAlreadySet(account);
    }

    /// @dev Reverts if amount is zero.
    function _revertIfZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /// @dev Reverts if account is zero address.
    function _revertIfZeroAccount(address account) internal pure {
        if (account == address(0)) revert ZeroAccount();
    }

    /// @dev Adds non-earning amount to an account's balance and total supply.
    /// @param $ The storage pointer.
    /// @param account The account to add the amount to.
    /// @param amount The amount to add (must be safe240).
    function _addNonEarningAmount(PYUSDXStorageStruct storage $, address account, uint240 amount) internal {
        // NOTE: Safe to use unchecked here since overflow of the total supply is checked in `_mint`.
        unchecked {
            $.accounts[account].balance += amount;
        }
    }

    /// @dev Adds earning amount to an account's balance and total earning supply/principal.
    /// @param $ The storage pointer.
    /// @param account The account to add the amount to.
    /// @param amount The present amount to add (must be safe240).
    /// @param accountIndex The per-account index to use for principal conversion.
    function _addEarningAmount(PYUSDXStorageStruct storage $, address account, uint240 amount, uint128 accountIndex) internal {
        uint112 principal = _getPrincipalAmountRoundedDown(amount, accountIndex);

        // NOTE: Safe to use unchecked here since overflow of the total supply is checked in `_mint`.
        unchecked {
            $.accounts[account].balance += amount;
            $.accounts[account].earningPrincipal += principal;
        }
    }

    /// @dev Subtracts non-earning amount from an account's balance and total supply.
    /// @param $ The storage pointer.
    /// @param account The account to subtract the amount from.
    /// @param amount The amount to subtract (must be safe240).
    function _subtractNonEarningAmount(PYUSDXStorageStruct storage $, address account, uint240 amount) internal {
        uint240 accountBalance = $.accounts[account].balance;

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
    /// @param accountIndex The per-account index to use for principal conversion.
    function _subtractEarningAmount(PYUSDXStorageStruct storage $, address account, uint240 amount, uint128 accountIndex) internal {
        uint240 accountBalance = $.accounts[account].balance;

        if (accountBalance < amount) {
            revert InsufficientBalance(account, accountBalance, amount);
        }

        uint112 principal = _getPrincipalAmountRoundedUp(amount, accountIndex);
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
        uint240 safeAmount = UIntMath.safe240(amount);

        // Subtract from sender
        if ($.accounts[sender].isEarning) {
            uint128 senderIndex = _updateAccountIndex(sender);
            _subtractEarningAmount($, sender, safeAmount, senderIndex);
        } else {
            _subtractNonEarningAmount($, sender, safeAmount);
        }

        // Add to recipient
        if ($.accounts[recipient].isEarning) {
            uint128 recipientIndex = _updateAccountIndex(recipient);
            _addEarningAmount($, recipient, safeAmount, recipientIndex);
        } else {
            _addNonEarningAmount($, recipient, safeAmount);
        }
    }
}
