// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @title IMinterGateway
/// @notice Interface for the MinterGateway contract that manages minting and burning of PYUSDX tokens
/// @dev Defines all events, errors, and functions for the MinterGateway
interface IMinterGateway {
    /* ============ Events ============ */

    /// @notice Emitted when a new mint is proposed
    /// @param mintId The unique identifier for the mint proposal
    /// @param minter The address that proposed the mint
    /// @param amount The amount of PYUSDX to mint
    /// @param recipient The address that will receive the minted tokens
    event MintProposed(uint48 indexed mintId, address indexed minter, uint256 amount, address indexed recipient);

    /// @notice Emitted when a mint is executed
    /// @param mintId The unique identifier for the mint proposal
    /// @param caller The address that executed the mint
    /// @param amount The amount of PYUSDX minted
    /// @param recipient The address that received the minted tokens
    event MintExecuted(uint48 indexed mintId, address indexed caller, uint256 amount, address indexed recipient);

    /// @notice Emitted when a mint proposal is canceled
    /// @param mintId The unique identifier for the mint proposal
    /// @param minter The address that proposed and canceled the mint
    event MintCanceled(uint48 indexed mintId, address indexed minter);

    /// @notice Emitted when tokens are burned
    /// @param minter The address that initiated the burn
    /// @param amount The amount of PYUSDX burned
    event BurnExecuted(address indexed minter, uint256 amount);

    /// @notice Emitted when the mint delay is updated
    /// @param mintDelay The mint delay in seconds
    event MintDelaySet(uint32 mintDelay);

    /// @notice Emitted when the mint TTL is updated
    /// @param mintTTL The mint TTL in seconds
    event MintTTLSet(uint32 mintTTL);

    /* ============ Errors ============ */

    /// @notice Thrown when the PYUSDX token address is zero
    error ZeroPYUSDXToken();

    /// @notice Thrown when attempting to propose a mint with zero amount
    error ZeroMintAmount();

    /// @notice Thrown when attempting to propose a mint with zero recipient address
    error ZeroMintRecipient();

    /// @notice Thrown when attempting to burn zero amount
    error ZeroBurnAmount();

    /// @notice Thrown when a mint proposal is invalid or does not exist
    error InvalidMintProposal();

    /// @notice Thrown when attempting to execute a mint before the delay has elapsed
    /// @param activeAt The timestamp when the mint can be executed
    error PendingMintProposal(uint40 activeAt);

    /// @notice Thrown when attempting to execute a mint after it has expired
    /// @param expiresAt The timestamp when the mint expired
    error ExpiredMintProposal(uint40 expiresAt);

    /// @notice Thrown when a non-creator attempts to cancel a mint proposal
    error NotMintProposalCreator();

    /// @notice Thrown when attempting to cancel a mint that is already active or expired
    /// @param activeAt The timestamp when the mint became active
    error ActiveMintProposal(uint40 activeAt);

    /* ============ Constants ============ */

    /// @notice Returns the role identifier for minter role
    /// @return The bytes32 role identifier
    function MINTER_ROLE() external view returns (bytes32);

    /* ============ Initializer ============ */

    /// @notice Initializes the MinterGateway contract
    /// @dev Can only be called once due to initializer modifier
    /// @param admin The address that will have the default admin role
    /// @param minter The address that will have the minter role
    /// @param mintDelay The delay in seconds before a mint can be executed after proposal
    /// @param mintTTL The time to live in seconds for a mint proposal before it expires
    function initialize(address admin, address minter, uint32 mintDelay, uint32 mintTTL) external;

    /* ============ Interactive Functions ============ */

    /// @notice Proposes a new mint operation
    /// @dev Only callable by addresses with MINTER_ROLE
    /// @param amount The amount of PYUSDX to mint
    /// @param recipient The address that will receive the minted tokens
    /// @return mintId The unique identifier for the mint proposal
    function proposeMint(uint256 amount, address recipient) external returns (uint48 mintId);

    /// @notice Executes a proposed mint after the delay has elapsed
    /// @dev Can be called by anyone after the mint delay has passed and before TTL expires
    /// @param mintId The unique identifier for the mint proposal
    function mint(uint48 mintId) external;

    /// @notice Burns PYUSDX tokens from the caller's balance
    /// @dev Only callable by addresses with MINTER_ROLE
    /// @param amount The amount of PYUSDX to burn
    function burn(uint256 amount) external;

    /// @notice Cancels a pending mint proposal
    /// @dev Only callable by the original proposer while the proposal is still pending (before delay elapses)
    /// @param mintId The unique identifier for the mint proposal
    function cancelMint(uint48 mintId) external;

    /* ============ View Functions ============ */

    /// @notice Returns the PYUSDX token contract address
    /// @return The PYUSDX token contract address
    function pyusdx() external view returns (address);

    /// @notice Returns the current mint delay
    /// @return The mint delay in seconds
    function mintDelay() external view returns (uint32);

    /// @notice Returns the current mint time-to-live
    /// @return The mint TTL in seconds
    function mintTTL() external view returns (uint32);

    /// @notice Returns the current mint nonce
    /// @return The mint nonce used for generating unique mint IDs
    function mintNonce() external view returns (uint48);

    /// @notice Returns the details of a mint proposal
    /// @param mintId The unique identifier for the mint proposal
    /// @return createdAt The timestamp when the proposal was created
    /// @return minter The address that proposed the mint
    /// @return recipient The address that will receive the minted tokens
    /// @return amount The amount of PYUSDX to mint
    function getMintProposal(
        uint48 mintId
    ) external view returns (uint40 createdAt, address minter, address recipient, uint256 amount);

    /* ============ Admin Functions ============ */

    /// @notice Updates the mint delay
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @param mintDelay The mint delay in seconds
    function setMintDelay(uint32 mintDelay) external;

    /// @notice Updates the mint TTL
    /// @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
    /// @param mintTTL The mint TTL in seconds
    function setMintTTL(uint32 mintTTL) external;
}
