// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

/**
 * @title IPYUSDX
 * @author M0 Labs
 * @notice Interface for PYUSDX upgradeable ERC20 non-rebasing token with claimable yield
 * @dev    PYUSDX is an upgradeable ERC20 token with:
 *         - Claimable yield via continuous indexing
 *         - Built-in pausing and compliance functionalities
 *         - Earner Manager controlled yield distribution
 */
interface IPYUSDX is IContinuousIndexing {
    /* ============ Events ============ */

    /**
     * @notice Emitted when earning details are set for an account.
     * @param account        The account whose earning details are being set.
     * @param isEarning      Whether the account is earning.
     * @param earnerManager  The Earner Manager setting the details.
     * @param feeRate        The fee rate on yield (basis points).
     * @param claimRecipient The address that will receive claimed yield.
     */
    event EarningDetailsSet(
        address indexed account,
        bool indexed isEarning,
        address indexed earnerManager,
        uint16 feeRate,
        address claimRecipient
    );

    /**
     * @notice Emitted when yield is claimed for an account.
     * @param account         The account for which yield is claimed.
     * @param claimRecipient  The address receiving the yield.
     * @param yield           The amount of yield claimed.
     */
    event Claimed(address indexed account, address indexed claimRecipient, uint240 yield);

    /**
     * @notice Emitted when earning is stopped for an account.
     * @param account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    /// @notice Thrown when the minter gateway address is zero.
    error ZeroMinterGateway();

    /// @notice Thrown when the admin address is zero.
    error ZeroAdmin();

    /// @notice Thrown when the earner manager address is zero.
    error ZeroEarnerManager();

    /// @notice Thrown when an account address is zero.
    error ZeroAccount();

    /// @notice Thrown when the caller does not have the EARNER_MANAGER_ROLE.
    error NotEarnerManager();

    /// @notice Thrown when the caller is not the Minter Gateway.
    error NotMinterGateway();

    /// @notice Thrown when earning details were already set by a different earner manager.
    error EarnerDetailsAlreadySet(address account);

    /// @notice Thrown when earning details are invalid (e.g., not earning but has fee rate).
    error InvalidDetails();

    /// @notice Thrown when the fee rate exceeds the maximum.
    error FeeRateTooHigh(uint16 feeRate);

    /// @notice Thrown when an input array is empty.
    error ArrayLengthZero();

    /// @notice Thrown when an amount is zero.
    error ZeroAmount();

    /// @notice Thrown when mint would overflow principal calculations.
    error OverflowsPrincipalOfTotalSupply();

    /// @notice Thrown when burn amount exceeds account balance.
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    /* ============ Interactive Functions ============ */

    /**
     * @notice Mints PYUSDX to an account.
     * @dev    MUST only be callable by MinterGateway.
     * @dev    MUST revert if the contract is paused.
     * @dev    MUST revert if the account is frozen.
     * @param account The account receiving the minted PYUSDX.
     * @param amount  The amount of PYUSDX to mint.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Burns PYUSDX from an account.
     * @dev    MUST only be callable by MinterGateway.
     * @dev    MUST revert if the contract is paused.
     * @dev    MUST revert if the account is frozen.
     * @param account The account from which PYUSDX is burnt.
     * @param amount  The amount of PYUSDX to burn.
     */
    function burn(address account, uint256 amount) external;

    /**
     * @notice Claims accrued yield for an account.
     * @dev    Anyone can call on behalf of any account.
     * @dev    MUST revert if the contract is paused.
     * @dev    MUST revert if the account is frozen.
     * @param account The account to claim yield for.
     * @return yield  The amount of yield claimed.
     */
    function claimFor(address account) external returns (uint240 yield);

    /**
     * @notice Sets earning details for a single account.
     * @dev    MUST only be callable by an Earner Manager.
     * @dev    MUST revert if the account is already managed by a different earner manager.
     * @param account         The account to configure.
     * @param isEarning       Whether the account is earning.
     * @param feeRate         The fee rate on yield (basis points, 0-10000).
     * @param claimRecipient  The address to receive claimed yield (address(0) to clear).
     */
    function setEarningDetails(address account, bool isEarning, uint16 feeRate, address claimRecipient) external;

    /**
     * @notice Sets earning details for multiple accounts.
     * @dev    MUST only be callable by an Earner Manager.
     * @dev    MUST revert if array lengths do not match.
     * @param accounts         The accounts to configure.
     * @param isEarning        The earning statuses for each account.
     * @param feeRates         The fee rates for each account (basis points).
     * @param claimRecipients  The addresses to receive claimed yield.
     */
    function setEarningDetails(
        address[] calldata accounts,
        bool[] calldata isEarning,
        uint16[] calldata feeRates,
        address[] calldata claimRecipients
    ) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The Minter Gateway contract address.
    function minterGateway() external view returns (address);

    /// @notice The maximum fee rate (10000 = 100%).
    function MAX_FEE_RATE() external view returns (uint16);

    /// @notice The total principal amount of earning accounts.
    function totalEarningPrincipal() external view returns (uint112);

    /// @notice The total supply of tokens in earning state.
    function totalEarningSupply() external view returns (uint240);

    /// @notice The total supply of tokens not earning yield.
    function totalNonEarningSupply() external view returns (uint240);

    /**
     * @notice Returns whether an account is earning.
     * @param account The account to query.
     * @return True if the account is earning.
     */
    function isEarning(address account) external view returns (bool);

    /**
     * @notice Returns earning statuses for multiple accounts.
     * @param accounts The accounts to query.
     * @return Boolean array indicating earning status for each account.
     */
    function isEarning(address[] calldata accounts) external view returns (bool[] memory);

    /**
     * @notice Returns the recipient of yield claims for an account.
     * @dev    Returns the locally set claim recipient if set, otherwise the account itself.
     * @param account The account to query.
     * @return The claim recipient address.
     */
    function claimRecipientFor(address account) external view returns (address);

    /**
     * @notice Returns the recipients of yield claims for multiple accounts.
     * @param accounts The accounts to query.
     * @return recipients Array of claim recipient addresses.
     */
    function claimRecipientsFor(address[] calldata accounts) external view returns (address[] memory);

    /**
     * @notice Returns detailed earning configuration for an account.
     * @param account The account to query.
     * @return isEarning      Whether the account is earning.
     * @return earnerManager  The Earner Manager for the account.
     * @return feeRate        The fee rate on yield (basis points).
     * @return claimRecipient The address that receives claimed yield.
     */
    function getEarningDetails(
        address account
    ) external view returns (bool isEarning, address earnerManager, uint16 feeRate, address claimRecipient);

    /**
     * @notice Returns detailed earning configuration for multiple accounts.
     * @param accounts The accounts to query.
     * @return isEarning       Earning status for each account.
     * @return earnerManagers  Earner Manager address for each account.
     * @return feeRates        Fee rate for each account (basis points).
     * @return claimRecipients Addresses to receive claimed yield.
     */
    function getEarningDetails(
        address[] calldata accounts
    )
        external
        view
        returns (
            bool[] memory isEarning,
            address[] memory earnerManagers,
            uint16[] memory feeRates,
            address[] memory claimRecipients
        );

    /**
     * @notice Returns the accrued but unclaimed yield for an account.
     * @param account The account to query.
     * @return The accrued yield (0 if account not earning).
     */
    function accruedYieldOf(address account) external view returns (uint240);

    /**
     * @notice Returns the token balance including any accrued yield.
     * @dev    Note: Claiming yield may not result in this balance if yield is redirected.
     * @param account The account to query.
     * @return Balance plus accrued yield.
     */
    function balanceWithYieldOf(address account) external view returns (uint256);

    /**
     * @notice Returns the earning principal of an account.
     * @param account The account to query.
     * @return The principal amount used for yield calculations.
     */
    function earningPrincipalOf(address account) external view returns (uint112);

    /**
     * @notice The role that can manage earners.
     * @return The EARNER_MANAGER_ROLE bytes32 value.
     */
    function EARNER_MANAGER_ROLE() external view returns (bytes32);

    /**
     * @notice The role that can mint PYUSDX tokens.
     * @return The MINTER_ROLE bytes32 value.
     */
    function MINTER_ROLE() external view returns (bytes32);
}
