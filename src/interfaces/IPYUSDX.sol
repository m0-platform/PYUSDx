// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/**
 * @title IPYUSDX
 * @author M0 Labs
 * @notice Interface for PYUSDX upgradeable ERC20 non-rebasing token with claimable yield
 * @dev    PYUSDX is an upgradeable ERC20 token with:
 *         - Claimable yield via continuous indexing
 *         - Built-in pausing and compliance functionalities
 *         - Earner Manager controlled yield distribution
 */
interface IPYUSDX {
    /* ============ Events ============ */

    /**
     * @notice Emitted when account info is set.
     * @param account        The account whose info is being set.
     * @param earnerRate     The earner rate in basis points (0 = not earning).
     * @param feeRate        The fee rate on yield (basis points).
     * @param claimRecipient The address that will receive claimed yield.
     */
    event AccountInfoSet(address indexed account, uint24 earnerRate, uint16 feeRate, address claimRecipient);

    /**
     * @notice Emitted when earning is started for an account.
     * @param account The account that started earning.
     */
    event StartedEarning(address indexed account);

    /**
     * @notice Emitted when earning is stopped for an account.
     * @param account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /**
     * @notice Emitted when yield is claimed for an account.
     * @param account         The account for which yield is claimed.
     * @param claimRecipient  The address receiving the yield.
     * @param yield           The amount of yield claimed.
     */
    event Claimed(address indexed account, address indexed claimRecipient, uint256 yield);

    /**
     * @notice Emitted when the earner manager is set or updated.
     * @param  account The address of the new earner manager.
     */
    event EarnerManagerSet(address indexed account);

    /* ============ Custom Errors ============ */

    /// @notice Thrown when the admin address is zero.
    error ZeroAdmin();

    /// @notice Thrown when the earner manager address is zero.
    error ZeroEarnerManager();

    /// @notice Thrown when an account address is zero.
    error ZeroAccount();

    /// @notice Thrown when an amount is zero.
    error ZeroAmount();

    /// @notice Thrown when the caller does not have the ISSUER_ROLE.
    error NotIssuer();

    /// @notice Thrown when the caller is not the earner manager.
    error NotEarnerManager();

    /// @notice Thrown when account info is invalid (e.g., not earning but has fee rate).
    error InvalidAccountInfo();

    /// @notice Thrown when the fee rate exceeds the maximum.
    error FeeRateTooHigh(uint16 feeRate);

    /// @notice Thrown when an input array is empty.
    error ArrayLengthZero();

    /// @notice Thrown when burn amount exceeds account balance.
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    /* ============ Interactive Functions ============ */

    /**
     * @notice Mints PYUSDX to an account.
     * @dev    MUST only be callable by ISSUER_ROLE.
     * @dev    MUST revert if the contract is paused.
     * @dev    MUST revert if the account is frozen.
     * @param account The account receiving the minted PYUSDX.
     * @param amount  The amount of PYUSDX to mint.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Burns PYUSDX from an account.
     * @dev    MUST only be callable by ISSUER_ROLE.
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
     * @param account The account to claim yield for.
     * @return yield  The amount of yield claimed.
     */
    function claimFor(address account) external returns (uint256 yield);

    /**
     * @notice Sets account info for a single account.
     * @dev    MUST only be callable by the earner manager.
     * @param account         The account to configure.
     * @param earnerRate      The earner rate in basis points (0 to stop earning).
     * @param feeRate         The fee rate on yield (basis points, 0-10000).
     * @param claimRecipient  The address to receive claimed yield (address(0) to clear).
     */
    function setAccountInfo(address account, uint24 earnerRate, uint16 feeRate, address claimRecipient) external;

    /**
     * @notice Sets account info for multiple accounts.
     * @dev    MUST only be callable by the earner manager.
     * @dev    MUST revert if array lengths do not match.
     * @param accounts         The accounts to configure.
     * @param earnerRates      The earner rates for each account (basis points).
     * @param feeRates         The fee rates for each account (basis points).
     * @param claimRecipients  The addresses to receive claimed yield.
     */
    function setAccountInfo(
        address[] calldata accounts,
        uint24[] calldata earnerRates,
        uint16[] calldata feeRates,
        address[] calldata claimRecipients
    ) external;

    /**
     * @notice Starts earning for an account with the given configuration.
     * @dev    MUST only be callable by the earner manager.
     * @param account         The account to start earning for.
     * @param earnerRate      The earner rate in basis points.
     * @param feeRate         The fee rate on yield (basis points).
     * @param claimRecipient  The address to receive claimed yield.
     */
    function startEarningFor(address account, uint24 earnerRate, uint16 feeRate, address claimRecipient) external;

    /**
     * @notice Sets the earner manager address.
     * @dev    MUST only be callable by DEFAULT_ADMIN_ROLE.
     * @param earnerManager The new earner manager address.
     */
    function setEarnerManager(address earnerManager) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The earner manager address.
    function earnerManager() external view returns (address);

    /// @notice The maximum fee rate (10000 = 100%).
    function MAX_FEE_RATE() external view returns (uint16);

    /// @notice The role that can issue (mint/burn) PYUSDX tokens.
    function ISSUER_ROLE() external view returns (bytes32);

    /**
     * @notice Returns whether an account is earning.
     * @param account The account to query.
     * @return True if the account is earning (earnerRate > 0).
     */
    function isEarning(address account) external view returns (bool);

    /**
     * @notice Returns the recipient of yield claims for an account.
     * @dev    Returns the account itself if no claim recipient is set.
     * @param account The account to query.
     * @return The claim recipient address.
     */
    function claimRecipientFor(address account) external view returns (address);

    /**
     * @notice Returns earning configuration for an account.
     * @param account The account to query.
     * @return earnerRate     The earner rate in basis points (0 = not earning).
     * @return feeRate        The fee rate on yield (basis points).
     * @return claimRecipient The address that receives claimed yield.
     */
    function getAccountEarningInfo(
        address account
    ) external view returns (uint24 earnerRate, uint16 feeRate, address claimRecipient);

    /**
     * @notice Returns accrued yield, fee, and net yield for an account.
     * @param account The account to query.
     * @return yieldWithFee  The total accrued yield including fee.
     * @return fee           The fee portion of the accrued yield.
     * @return yieldNetOfFee The accrued yield net of fee.
     */
    function accruedYieldAndFeeOf(
        address account
    ) external view returns (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFee);

    /**
     * @notice Returns the accrued but unclaimed yield (net of fee) for an account.
     * @param account The account to query.
     * @return The accrued yield net of fee (0 if account not earning).
     */
    function accruedYieldOf(address account) external view returns (uint256);

    /**
     * @notice Returns the accrued fee for an account.
     * @param account The account to query.
     * @return The accrued fee (0 if account not earning).
     */
    function accruedFeeOf(address account) external view returns (uint256);

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
     * @notice Returns the stored (last snapshotted) index for an account.
     * @param account The account to query.
     * @return The last stored index value.
     */
    function lastIndexOf(address account) external view returns (uint128);

    /**
     * @notice Returns the computed current index for an account.
     * @dev    Returns EXP_SCALED_ONE (1e12) for non-earners.
     * @param account The account to query.
     * @return The current index value.
     */
    function currentIndexOf(address account) external view returns (uint128);

    /**
     * @notice Returns the last update timestamp for an account.
     * @param account The account to query.
     * @return The last update timestamp.
     */
    function lastUpdateTimestampOf(address account) external view returns (uint32);
}
