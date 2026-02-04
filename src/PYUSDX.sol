// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { ERC20ExtendedUpgradeable } from "../lib/m-extensions/lib/common/src/ERC20ExtendedUpgradeable.sol";
import { Freezable } from "../lib/m-extensions/src/components/freezable/Freezable.sol";
import { ForcedTransferable } from "../lib/m-extensions/src/components/forcedTransferable/ForcedTransferable.sol";
import { Pausable } from "../lib/m-extensions/src/components/pausable/Pausable.sol";
import { IndexingMath } from "../lib/m-extensions/lib/common/src/libs/IndexingMath.sol";

import { ContinuousIndexing } from "./abstract/ContinuousIndexing.sol";
import { IPYUSDX } from "./interfaces/IPYUSDX.sol";

/// @notice ERC-7201 namespaced storage layout for PYUSDX.
abstract contract PYUSDXStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDX
    struct PYUSDXStorageStruct {
        // Supply tracking
        uint112 totalEarningPrincipal;
        uint240 totalEarningSupply;
        uint240 totalNonEarningSupply;
        uint256 totalSupply;
        // Account data
        mapping(address account => Account) accounts;
        mapping(address account => uint256) balanceOf;
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
    bytes32 private constant PYUSDX_STORAGE_LOCATION =
        0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500;

    function _getPYUSDXStorageLocation() internal pure returns (PYUSDXStorageStruct storage $) {
        assembly {
            $.slot := PYUSDX_STORAGE_LOCATION
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

    /// @notice Mints new tokens to an account (only Minter Gateway).
    function mint(address account, uint256 amount) external onlyMinterGateway {
        revert("TODO: mint");
    }

    /// @notice Burns tokens from an account (only Minter Gateway).
    function burn(address account, uint256 amount) external onlyMinterGateway {
        revert("TODO: burn");
    }

    /// @inheritdoc IPYUSDX
    function claimFor(address account) external returns (uint240 yield) {
        return _claim(account, currentIndex());
    }

    /// @inheritdoc IPYUSDX
    function setEarningDetails(
        address account,
        bool isEarning_,
        uint16 feeRate_,
        address claimRecipient_
    ) external onlyEarnerManager(account) {
        _setEarningDetails(account, isEarning_, feeRate_, claimRecipient_, currentIndex());
    }

    /// @inheritdoc IPYUSDX
    function setEarningDetails(
        address[] calldata accounts,
        bool[] calldata isEarning_,
        uint16[] calldata feeRates_,
        address[] calldata claimRecipients_
    ) external {
        uint256 len = accounts.length;
        if (len == 0) revert ArrayLengthZero();
        if (len != isEarning_.length || len != feeRates_.length || len != claimRecipients_.length) {
            revert ArrayLengthMismatch();
        }

        uint128 currentIndex_ = currentIndex();

        for (uint256 i; i < len; ++i) {
            _checkEarnerManager(accounts[i]);
            _setEarningDetails(accounts[i], isEarning_[i], feeRates_[i], claimRecipients_[i], currentIndex_);
        }
    }

    /* ============ Internal Functions ============ */

    /// @dev Reverts if the caller is not the Earner Manager for the account.
    /// @dev If no earner manager is assigned (address(0)), the caller must have EARNER_MANAGER_ROLE.
    /// @dev If an earner manager is assigned, only that manager can modify the account.
    function _checkEarnerManager(address account) internal view {
        address storedManager = _getPYUSDXStorageLocation().accounts[account].earnerManager;

        if (storedManager == address(0)) {
            if (!hasRole(EARNER_MANAGER_ROLE, msg.sender)) revert NotEarnerManager(account);
        } else if (msg.sender != storedManager) {
            // Account already managed by a different earner manager
            revert EarnerDetailsAlreadySet(account);
        }
    }

    /// @dev Internal implementation for setting earning details.
    function _setEarningDetails(
        address account,
        bool isEarning_,
        uint16 feeRate_,
        address claimRecipient_,
        uint128 currentIndex_
    ) internal {
        if (account == address(0)) revert ZeroAccount();
        if (feeRate_ > MAX_FEE_RATE) revert FeeRateTooHigh(feeRate_);
        if (!isEarning_ && feeRate_ != 0) revert InvalidDetails();

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        bool wasEarning = accountData.isEarning;

        if (!wasEarning && !isEarning_) return;

        // same earning state with same settings
        if (wasEarning && isEarning_
            && accountData.feeRate == feeRate_
            && accountData.claimRecipient == claimRecipient_) return;

        emit EarningDetailsSet(account, isEarning_, msg.sender, feeRate_, claimRecipient_);

        // Claim any accrued yield first
        if (wasEarning) {
            _claim(account, currentIndex_);
        }

        uint240 balance = accountData.balance;

        // Enable earning (non-earner → earner)
        if (isEarning_ && !wasEarning) {
            accountData.earnerManager = msg.sender;
            accountData.isEarning = true;

            uint112 principal = IndexingMath.getPrincipalAmountRoundedDown(balance, currentIndex_);
            accountData.earningPrincipal = principal;

            $.totalEarningPrincipal += principal;
            $.totalEarningSupply += balance;
            $.totalNonEarningSupply -= balance;
        }
        // Disable earning (earner → non-earner)
        else if (!isEarning_ && wasEarning) {
            uint112 principal = accountData.earningPrincipal;

            accountData.isEarning = false;
            accountData.earningPrincipal = 0;
            accountData.earnerManager = address(0);

            $.totalEarningPrincipal -= principal;
            $.totalEarningSupply -= balance;
            $.totalNonEarningSupply += balance;
        }

        accountData.feeRate = feeRate_;
        accountData.claimRecipient = claimRecipient_;
    }

    /// @dev Internal claim implementation.
    function _claim(address account, uint128 currentIndex_) internal returns (uint240 yield) {
        _requireNotPaused();
        _revertIfFrozen(account);

        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        if (!accountData.isEarning) return 0;

        // Calculate accrued yield
        uint240 balance = accountData.balance;
        uint240 balanceWithYield = IndexingMath.getPresentAmountRoundedDown(accountData.earningPrincipal, currentIndex_);

        unchecked {
            yield = balanceWithYield > balance ? balanceWithYield - balance : 0;
        }

        if (yield == 0) return 0;

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
            accountData.balance = balance + yield;
            $.balanceOf[account] += yield;
            $.totalEarningSupply += yield;
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

    /// @dev Internal force transfer implementation.
    function _forceTransfer(address frozenAccount, address recipient, uint256 amount) internal override {
        revert("TODO: _forceTransfer");
    }

    /* ============ View Functions ============ */

    /// @notice Returns the balance of an account.
    function balanceOf(address account) public view returns (uint256) {
        return _getPYUSDXStorageLocation().balanceOf[account];
    }

    /// @notice Returns the total supply of tokens.
    function totalSupply() public view returns (uint256) {
        return _getPYUSDXStorageLocation().totalSupply;
    }

    /// @notice Returns the total principal of earning accounts.
    function totalEarningPrincipal() external view returns (uint112) {
        return _getPYUSDXStorageLocation().totalEarningPrincipal;
    }

    /// @notice Returns the total supply of earning accounts.
    function totalEarningSupply() external view returns (uint240) {
        return _getPYUSDXStorageLocation().totalEarningSupply;
    }

    /// @notice Returns the total supply of non-earning accounts.
    function totalNonEarningSupply() external view returns (uint240) {
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
    function accruedYieldOf(address account) public view returns (uint240) {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
        Account storage accountData = $.accounts[account];

        if (!accountData.isEarning) return 0;

        // Calculate present value from principal
        uint240 balanceWithYield = IndexingMath.getPresentAmountRoundedDown(
            accountData.earningPrincipal,
            currentIndex()
        );

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

    /* ============ ERC20ExtendedUpgradeable Override ============ */

    /// @dev Required override for ERC20ExtendedUpgradeable.
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();

        // TODO: Add principal accounting for earners

        // Update balances
        $.balanceOf[sender] -= amount;
        $.balanceOf[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }
}
