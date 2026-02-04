// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { ERC20ExtendedUpgradeable } from "../lib/m-extensions/lib/common/src/ERC20ExtendedUpgradeable.sol";
import { Freezable } from "../lib/m-extensions/src/components/freezable/Freezable.sol";
import { ForcedTransferable } from "../lib/m-extensions/src/components/forcedTransferable/ForcedTransferable.sol";
import { Pausable } from "../lib/m-extensions/src/components/pausable/Pausable.sol";
import { UIntMath } from "../lib/m-extensions/lib/common/src/libs/UIntMath.sol";

import { ContinuousIndexing } from "./abstract/ContinuousIndexing.sol";
import { IPYUSDX } from "./interfaces/IPYUSDX.sol";

/// @notice ERC-7201 namespaced storage layout for PYUSDX.
abstract contract PYUSDXStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDX
    struct PYUSDXStorageStruct {
        // Supply tracking
        uint112 totalEarningPrincipal;
        uint240 totalNonEarningSupply;
        // Account data
        mapping(address account => Account) accounts;
    }

    struct Account {
        address earnerManager;
        uint240 balance;
        bool isEarning;
        uint112 earningPrincipal;
        uint16 feeRate;
        address claimRecipient;
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
/// @dev    DUMMY IMPLEMENTATION - Functions return placeholder values.
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

    /// @notice The PYUSD token contract address.
    address public immutable pyusd;

    /* ============ Constructor ============ */

    /// @notice Constructs the PYUSDX implementation contract.
    /// @param minterGateway_ The Minter Gateway contract address.
    /// @param pyusd_ The PYUSD token contract address.
    constructor(address minterGateway_, address pyusd_) {
        if (minterGateway_ == address(0)) revert ZeroMinterGateway();
        if (pyusd_ == address(0)) revert ZeroPYUSD();

        minterGateway = minterGateway_;

        // TODO: is PYUSD needed? We may only need it in the Minter Gateway to check balances before minting/burning.
        pyusd = pyusd_;

        _disableInitializers();
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

    /* ============ Interactive Functions (TODO Dummies) ============ */

    /// @inheritdoc IPYUSDX
    function mint(address account, uint256 amount) external onlyMinterGateway whenNotPaused {
        _revertIfZeroAmount(amount);
        _revertIfZeroRecipient(account);
        _revertIfFrozen(account);

        uint240 safeAmount = UIntMath.safe240(amount);
        uint128 index = currentIndex();

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // NOTE: Overflow check: prevent a mint that would overflow `totalEarningPrincipal`
        //       if all tokens (earning and non-earning) were converted to a principal earning amount
        unchecked {
            if (
                uint256($.totalNonEarningSupply) + safeAmount > type(uint240).max ||
                uint256($.totalEarningPrincipal) +
                    _getPrincipalAmountRoundedUp($.totalNonEarningSupply + safeAmount, index) >=
                    type(uint112).max
            ) {
                revert OverflowsPrincipalOfTotalSupply();
            }
        }

        if ($.accounts[account].isEarning) {
            _addEarningAmount($, account, safeAmount, index);
            updateIndex();
        } else {
            _addNonEarningAmount($, account, safeAmount);
        }

        emit Transfer(address(0), account, amount);
    }

    /// @notice Burns tokens from an account (only Minter Gateway).
    function burn(address account, uint256 amount) external onlyMinterGateway whenNotPaused {
        revert("TODO: burn");
    }

    /// @notice Claims yield for an account.
    function claimFor(address account) external returns (uint240 yield) {
        revert("TODO: claimFor");
    }

    /// @notice Sets earning details for a single account.
    function setEarningDetails(
        address account,
        bool isEarning_,
        uint16 feeRate_,
        address claimRecipient_
    ) external onlyEarnerManager(account) {
        revert("TODO: setEarningDetails single");
    }

    /// @notice Sets earning details for multiple accounts.
    function setEarningDetails(
        address[] calldata accounts,
        bool[] calldata isEarning_,
        uint16[] calldata feeRates_,
        address[] calldata claimRecipients_
    ) external {
        // Check that caller is earner manager for all accounts
        for (uint256 i = 0; i < accounts.length; i++) {
            _checkEarnerManager(accounts[i]);
        }
        revert("TODO: setEarningDetails batch");
    }

    /* ============ View Functions ============ */

    /// @notice Returns the balance of an account.
    function balanceOf(address account) public view override returns (uint256) {
        return _getPYUSDXStorageLocation().accounts[account].balance;
    }

    /// @notice Returns the total supply of tokens.
    function totalSupply() public view override returns (uint256) {
        unchecked {
            return totalEarningSupply() + totalNonEarningSupply();
        }
    }

    /// @inheritdoc IPYUSDX
    function totalEarningPrincipal() public view returns (uint112) {
        return _getPYUSDXStorageLocation().totalEarningPrincipal;
    }

    /// @inheritdoc IPYUSDX
    function totalEarningSupply() public view returns (uint240) {
        return _getPresentAmountRoundedDown(totalEarningPrincipal());
    }

    /// @inheritdoc IPYUSDX
    function totalNonEarningSupply() public view returns (uint240) {
        return _getPYUSDXStorageLocation().totalNonEarningSupply;
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
    ) external view returns (bool isEarning_, address earnerManager_, uint16 feeRate_, address claimRecipient_) {
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
            address[] memory earnerManagers_,
            uint16[] memory feeRates_,
            address[] memory claimRecipients_
        )
    {
        uint256 len = accounts.length;
        isEarning_ = new bool[](len);
        earnerManagers_ = new address[](len);
        feeRates_ = new uint16[](len);
        claimRecipients_ = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            Account memory accountData = _getPYUSDXStorageLocation().accounts[accounts[i]];
            isEarning_[i] = accountData.isEarning;
            earnerManagers_[i] = accountData.earnerManager;
            feeRates_[i] = accountData.feeRate;
            claimRecipients_[i] = accountData.claimRecipient;
        }
    }

    /// @notice Returns the accrued yield for an account.
    function accruedYieldOf(address) external view returns (uint240) {
        return 0; // Dummy: no yield accrued
    }

    /// @notice Returns the balance including yield for an account.
    function balanceWithYieldOf(address account) external view returns (uint256) {
        return balanceOf(account); // Dummy: no yield included
    }

    /// @notice Returns the earning principal for an account.
    function earningPrincipalOf(address account) external view returns (uint112) {
        return _getPYUSDXStorageLocation().accounts[account].earningPrincipal;
    }

    /* ============ Internal Functions ============ */

    /// @dev Reverts if the caller is not the Earner Manager for the account.
    /// @dev If no earner manager is assigned (address(0)), the check passes.
    function _checkEarnerManager(address account) internal view {
        address earnerManager = _getPYUSDXStorageLocation().accounts[account].earnerManager;
        if (earnerManager != address(0) && msg.sender != earnerManager) revert NotEarnerManager(account);
    }

    /// @dev Internal force transfer implementation.
    function _forceTransfer(address frozenAccount, address recipient, uint256 amount) internal override {
        revert("TODO: _forceTransfer");
    }

    /// @dev Reverts if amount is zero.
    function _revertIfZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /// @dev Reverts if recipient is zero address.
    function _revertIfZeroRecipient(address recipient) internal pure {
        if (recipient == address(0)) revert ZeroRecipient();
    }

    /// @dev Adds non-earning amount to an account's balance and total supply.
    /// @param $ The storage pointer.
    /// @param account The account to add the amount to.
    /// @param amount The amount to add (must be safe240).
    function _addNonEarningAmount(PYUSDXStorageStruct storage $, address account, uint240 amount) internal {
        $.accounts[account].balance += amount;
        $.totalNonEarningSupply += amount;
    }

    /// @dev Adds earning amount to an account's balance and total earning supply/principal.
    /// @param $ The storage pointer.
    /// @param account The account to add the amount to.
    /// @param amount The present amount to add (must be safe240).
    /// @param index The current index for principal calculation.
    function _addEarningAmount(PYUSDXStorageStruct storage $, address account, uint240 amount, uint128 index) internal {
        uint112 principal = _getPrincipalAmountRoundedDown(amount, index);

        $.accounts[account].balance += amount;
        $.totalEarningPrincipal += principal;
        $.accounts[account].earningPrincipal += principal;
    }

    /// @dev Required override for ERC20ExtendedUpgradeable.
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // TODO: Add principal accounting for earners

        // Update balances
        $.accounts[sender].balance -= uint240(amount);
        $.accounts[recipient].balance += uint240(amount);

        emit Transfer(sender, recipient, amount);
    }
}
