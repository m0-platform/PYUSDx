// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  IPYUSDX
/// @author M0 Labs
/// @notice Interface for PYUSDX upgradeable ERC20 non-rebasing token with claimable yield
/// @dev    PYUSDX is an upgradeable ERC20 token with:
///         - Claimable yield via continuous indexing
///         - Built-in pausing and compliance functionalities
///         - Earner Manager controlled yield distribution
interface IPYUSDX {
    /* ============ Events ============ */

    /// @notice Emitted when earning is started for an account.
    /// @param  account The account that started earning.
    event StartedEarning(address indexed account);

    /// @notice Emitted when earning is stopped for an account.
    /// @param  account The account that stopped earning.
    event StoppedEarning(address indexed account);

    /// @notice Emitted when account info is updated.
    /// @param  account        The account that was updated.
    /// @param  earnerRate     The new earner rate in basis points (0 = not earning).
    /// @param  feeRate        The new fee rate in basis points.
    /// @param  claimRecipient The new claim recipient address.
    event AccountInfoUpdated(
        address indexed account,
        uint16 earnerRate,
        uint16 feeRate,
        address indexed claimRecipient
    );

    /// @notice Emitted when the earner manager is set or updated.
    /// @param  earnerManager The address of the new earner manager.
    event EarnerManagerSet(address indexed earnerManager);

    /// @notice Emitted when an account's index is updated.
    event IndexUpdated(address indexed account, uint128 currentIndex);

    /// @notice Emitted when yield is claimed for an account.
    event YieldClaimed(address indexed account, uint256 yieldNetOfFee);

    /// @notice Emitted when a fee is claimed from an account's yield.
    event FeeClaimed(address indexed account, address indexed recipient, uint256 fee);

    /// @notice Emitted when earner manager distributed additional reward for an account.
    event RewardDistributed(address indexed account, uint256 amount);

    /* ============ Structs ============ */

    /// @notice Parameters for initializing the PYUSDX contract.
    struct InitializeParams {
        string name;
        string symbol;
        address admin;
        address pauser;
        address freezeManager;
        address forcedTransferManager;
        address earnerManager;
        address rateLimitManager;
        address issuer;
    }

    /* ============ Custom Errors ============ */

    /// @notice Thrown when the admin address is zero.
    error ZeroAdmin();

    /// @notice Thrown when the issuer address is zero.
    error ZeroIssuer();

    /// @notice Thrown when the earner manager address is zero.
    error ZeroEarnerManager();

    /// @notice Thrown when an account address is zero.
    error ZeroAccount();

    /// @notice Thrown when an amount is zero.
    error ZeroAmount();

    /// @notice Thrown when the caller is not the earner manager.
    error NotEarnerManager();

    /// @notice Thrown when account info is invalid (e.g., not earning but has fee rate).
    error InvalidAccountInfo();

    /// @notice Thrown when the fee rate exceeds the maximum.
    error FeeRateTooHigh(uint16 feeRate);

    /// @notice Thrown when the earner rate exceeds the maximum.
    error EarnerRateTooHigh(uint16 earnerRate);

    /// @notice Thrown when an input array is empty.
    error ArrayLengthZero();

    /// @notice Thrown when burn amount exceeds account balance.
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    /* ============ Interactive Functions ============ */

    /// @notice Mints PYUSDX to an account.
    /// @dev    MUST only be callable by ISSUER_ROLE.
    /// @dev    MUST revert if the contract is paused.
    /// @dev    MUST revert if the account is frozen.
    /// @param  account The account receiving the minted PYUSDX.
    /// @param  amount  The amount of PYUSDX to mint.
    function mint(address account, uint256 amount) external;

    /// @notice Burns PYUSDX from an account.
    /// @dev    MUST only be callable by ISSUER_ROLE.
    /// @dev    MUST revert if the contract is paused.
    /// @dev    MUST revert if the account is frozen.
    /// @dev    `ISSUER_ROLE` is expected to be granted only to contracts that burn from their
    ///         own non-earning balance (e.g., IssuerGateway, Portal). Burning directly from an
    ///         earning account does not pre-claim accrued yield: `_subtractEarningAmount` rounds
    ///         the consumed principal up (e.g. in favor of the protocol), so any unclaimed yield
    ///         at the time of burn is subject to a sub-unit rounding loss in present value.
    /// @param  account The account from which PYUSDX is burnt.
    /// @param  amount  The amount of PYUSDX to burn.
    function burn(address account, uint256 amount) external;

    /// @notice Claims accrued yield for an account.
    /// @dev    Anyone can call on behalf of any account.
    /// @dev    MUST revert if the contract is paused.
    /// @dev    MUST revert if the account is frozen.
    /// @param  account The account to claim yield for.
    /// @return yieldWithFee  The gross yield claimed.
    /// @return fee           The fee deducted.
    /// @return yieldNetOfFee The net yield after fee.
    function claimFor(address account) external returns (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFee);

    /// @notice Claims accrued yield for multiple accounts.
    /// @dev    MUST revert if the contract is paused or any account is frozen.
    /// @param  accounts       The accounts to claim yield for.
    /// @return yieldWithFees  The gross yield claimed per account.
    /// @return fees           The fee deducted per account.
    /// @return yieldNetOfFees The net yield per account.
    function claimFor(
        address[] calldata accounts
    ) external returns (uint256[] memory yieldWithFees, uint256[] memory fees, uint256[] memory yieldNetOfFees);

    /// @notice Sets account info for a single account.
    /// @dev    MUST only be callable by the earner manager.
    /// @dev    Callable while paused so the earner manager retains an emergency lever over
    ///         earner configuration. When called while paused, any accrued yield is
    ///         materialized onto `account`'s own balance and the `claimRecipient` routing and
    ///         fee `_transfer` are skipped — the earner manager forgoes the fee for that call.
    ///         The forgone fee is recoverable: `freeze(account)` followed by
    ///         `forceTransfer(account, feeRecipient, amount)` can move the fee portion out of
    ///         the earner's balance after the incident response.
    /// @param  account        The account to configure.
    /// @param  earnerRate     The earner rate in basis points (0 to stop earning).
    /// @param  feeRate        The fee rate on yield (basis points, 0-10000).
    /// @param  claimRecipient The address to receive claimed yield (address(0) to clear).
    function setAccountInfo(address account, uint16 earnerRate, uint16 feeRate, address claimRecipient) external;

    /// @notice Sets account info for multiple accounts.
    /// @dev    MUST only be callable by the earner manager.
    /// @dev    MUST revert if array lengths do not match.
    /// @dev    Pause semantics match the single-account overload: yield materializes to each
    ///         account's own balance, fee and `claimRecipient` routing are skipped per entry.
    ///         The forgone fee on any entry is recoverable post-incident via `freeze` +
    ///         `forceTransfer`.
    /// @param  accounts        The accounts to configure.
    /// @param  earnerRates     The earner rates for each account (basis points).
    /// @param  feeRates        The fee rates for each account (basis points).
    /// @param  claimRecipients The addresses to receive claimed yield.
    function setAccountInfo(
        address[] calldata accounts,
        uint16[] calldata earnerRates,
        uint16[] calldata feeRates,
        address[] calldata claimRecipients
    ) external;

    /// @notice Distributes a reward to an account by minting new PYUSDX.
    /// @dev    MUST only be callable by the earner manager.
    /// @dev    MUST revert if the contract is paused.
    /// @dev    MUST revert if the account is frozen.
    /// @param  account The account to receive the reward.
    /// @param  amount  The amount of PYUSDX to distribute.
    function distributeReward(address account, uint256 amount) external;

    /// @notice Sets the earner manager address.
    /// @dev    MUST only be callable by DEFAULT_ADMIN_ROLE.
    /// @param  earnerManager The new earner manager address.
    function setEarnerManager(address earnerManager) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The maximum fee rate (10000 = 100%).
    function ONE_HUNDRED_PERCENT() external view returns (uint16);

    /// @notice Precision scaling for index calculations (1e12).
    function EXP_SCALED_ONE() external view returns (uint128);

    /// @notice The role that can issue (mint/burn) PYUSDX tokens.
    function ISSUER_ROLE() external view returns (bytes32);

    /// @notice The earner manager address.
    function earnerManager() external view returns (address);

    /// @notice Returns whether an account is earning.
    /// @param  account The account to query.
    /// @return True if the account is earning (earnerRate > 0).
    function isEarning(address account) external view returns (bool);

    /// @notice Returns the recipient of yield claims for an account.
    /// @dev    Returns the account itself if no claim recipient is set.
    /// @param  account The account to query.
    /// @return The claim recipient address.
    function claimRecipientFor(address account) external view returns (address);

    /// @notice Returns earning configuration for an account.
    /// @param  account The account to query.
    /// @return earnerRate     The earner rate in basis points (0 = not earning).
    /// @return feeRate        The fee rate on yield (basis points).
    /// @return claimRecipient The address that receives claimed yield.
    function getAccountEarningInfo(
        address account
    ) external view returns (uint16 earnerRate, uint16 feeRate, address claimRecipient);

    /// @notice Returns accrued yield, fee, and net yield for an account.
    /// @param  account The account to query.
    /// @return yieldWithFee  The total accrued yield including fee.
    /// @return fee           The fee portion of the accrued yield.
    /// @return yieldNetOfFee The accrued yield net of fee.
    function accruedYieldAndFeeOf(
        address account
    ) external view returns (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFee);

    /// @notice Returns the accrued but unclaimed yield (net of fee) for an account.
    /// @param  account The account to query.
    /// @return The accrued yield net of fee (0 if account not earning).
    function accruedYieldOf(address account) external view returns (uint256);

    /// @notice Returns the accrued yield that would be claimed by the account itself.
    /// @param  account The account to query.
    /// @return The accrued yield to self (0 if account not earning or yield is redirected).
    function accruedYieldToSelfOf(address account) external view returns (uint256);

    /// @notice Returns the accrued fee for an account.
    /// @param  account The account to query.
    /// @return The accrued fee (0 if account not earning).
    function accruedFeeOf(address account) external view returns (uint256);

    /// @notice Returns the token balance including any accrued yield.
    /// @dev    Note: Claiming yield may not result in this balance if yield is redirected.
    /// @param  account The account to query.
    /// @return Balance plus accrued yield.
    function balanceWithYieldOf(address account) external view returns (uint256);

    /// @notice Returns the earning principal of an account.
    /// @param  account The account to query.
    /// @return The principal amount used for yield calculations.
    function earningPrincipalOf(address account) external view returns (uint112);

    /// @notice Returns the stored (last snapshotted) index for an account.
    /// @param  account The account to query.
    /// @return The last stored index value.
    function lastIndexOf(address account) external view returns (uint128);

    /// @notice Returns the computed current index for an account.
    /// @dev    Returns EXP_SCALED_ONE (1e12) for non-earners.
    /// @param  account The account to query.
    /// @return The current index value.
    function currentIndexOf(address account) external view returns (uint128);

    /// @notice Returns the last update timestamp for an account.
    /// @param  account The account to query.
    /// @return The last update timestamp.
    function lastUpdateTimestampOf(address account) external view returns (uint40);
}
