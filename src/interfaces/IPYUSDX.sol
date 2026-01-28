// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/**
 * @title IPYUSDX
 * @notice Interface for PYUSDX - an upgradeable, non-rebasing ERC20 token with claimable yield
 * @dev Implements continuous indexing for yield accrual without balance rebase
 * @author M0 Labs
 */
interface IPYUSDX {
    /* ============ Errors ============ */

    /// @notice Thrown when minter gateway address is zero
    error ZeroMinterGateway();

    /// @notice Thrown when PYUSD address is zero
    error ZeroPYUSD();

    /* ============ View Functions ============ */

    /// @notice Returns accrued but unclaimed yield
    /// @param account Account to query
    /// @return Accrued yield amount
    function accruedYieldOf(address account) external view returns (uint240);

    /// @notice Returns balance excluding accrued yield
    /// @param account Account to query
    /// @return Current balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns balance including accrued yield
    /// @param account Account to query
    /// @return Balance plus accrued yield
    function balanceWithYieldOf(address account) external view returns (uint256);

    /// @notice Returns earning principal for yield calculations
    /// @param account Account to query
    /// @return Principal amount
    function earningPrincipalOf(address account) external view returns (uint112);

    /// @notice Returns claim recipient for an account
    /// @param account Account to query
    /// @return Claim recipient (account if not set)
    function claimRecipientFor(address account) external view returns (address);

    /// @notice Returns current yield index
    /// @return Current index value
    function currentIndex() external view returns (uint128);

    /// @notice Returns whether an account is earning
    /// @param account Account to query
    /// @return True if earning
    function isEarning(address account) external view returns (bool);

    /// @notice Returns total supply of tokens in earning state
    /// @return Total earning supply
    function totalEarningSupply() external view returns (uint256);

    /// @notice Returns total supply of tokens not earning
    /// @return Total non-earning supply
    function totalNonEarningSupply() external view returns (uint256);

    /* ============ Interactive Functions ============ */

    /// @notice Mints PYUSDX to an account
    /// @dev Only callable by the Minter Gateway
    /// @param account Recipient of minted tokens
    /// @param amount Amount to mint
    function mint(address account, uint256 amount) external;

    /// @notice Burns PYUSDX from an account
    /// @dev Only callable by the Minter Gateway
    /// @param account Account to burn from
    /// @param amount Amount to burn
    function burn(address account, uint256 amount) external;

    /// @notice Claims accrued yield for an earner
    /// @param account Earner to claim for
    /// @return Amount of yield claimed
    function claimFor(address account) external returns (uint240);

    /// @notice Starts earning for an approved earner
    /// @param account Account to start earning
    function startEarningFor(address account) external;

    /// @notice Starts earning for multiple approved earners
    /// @param accounts Accounts to start earning
    function startEarningFor(address[] calldata accounts) external;

    /// @notice Stops earning for a removed earner
    /// @dev Only callable by the Earner Manager; remaining yield is claimed before stopping earning
    /// @param account Account to stop earning
    function stopEarningFor(address account) external;

    /// @notice Stops earning for multiple removed earners
    /// @dev Only callable by the Earner Manager; remaining yield is claimed before stopping earning
    /// @param accounts Accounts to stop earning
    function stopEarningFor(address[] calldata accounts) external;

    /// @notice Sets claim recipient for an earner
    /// @dev Only callable by the Earner Manager
    /// @param account Earner account
    /// @param claimRecipient Recipient for yield claims (address(0) to clear)
    function setClaimRecipient(address account, address claimRecipient) external;

    /* ============ Events ============ */

    /// @notice Emitted when yield is claimed
    /// @param account Earner account
    /// @param recipient Recipient of the yield
    /// @param yield Amount of yield claimed
    event Claimed(address indexed account, address indexed recipient, uint240 yield);

    /// @notice Emitted when an account starts earning
    /// @param account Account that started earning
    event StartedEarning(address indexed account);

    /// @notice Emitted when an account stops earning
    /// @param account Account that stopped earning
    event StoppedEarning(address indexed account);

    /// @notice Emitted when claim recipient is set
    /// @param account Earner account
    /// @param recipient New claim recipient
    event ClaimRecipientSet(address indexed account, address indexed recipient);

    /// @notice Emitted when the yield rate is set
    /// @param newRate New annual yield rate (basis points, scaled by 1e12)
    event RateSet(uint32 indexed newRate);

    /// @notice Emitted when the yield index is updated
    /// @param newIndex New index value
    /// @param timestamp Timestamp of the update
    event IndexUpdated(uint128 indexed newIndex, uint256 indexed timestamp);
}
