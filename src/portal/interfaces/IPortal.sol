// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  IPortal interface
/// @author M0 Labs
/// @notice Interface for bridging PYUSDX and PYUSDX Extension tokens across chains via pluggable bridge adapters.
interface IPortal {
    /* ============ Events ============ */

    /// @notice Emitted when token is sent to a destination chain.
    /// @param  sourceToken        The address of the token on the source chain.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  destinationToken   The address of the token on the destination chain.
    /// @param  sender             The account sending tokens.
    /// @param  recipient          The account receiving tokens on destination chain.
    /// @param  amount             The amount of tokens.
    /// @param  bridgeAdapter      The address of the bridge adapter used to send the message.
    /// @param  messageId          The unique ID for the sent message.
    event TokenSent(
        address indexed sourceToken,
        uint32 destinationChainId,
        bytes32 destinationToken,
        address indexed sender,
        bytes32 indexed recipient,
        uint256 amount,
        address bridgeAdapter,
        bytes32 messageId
    );

    /// @notice Emitted when token is received from a source chain.
    /// @param  sourceChainId    The ID of the source chain.
    /// @param  destinationToken The address of the token on the destination chain.
    /// @param  sender           The account sending tokens.
    /// @param  recipient        The account receiving tokens.
    /// @param  amount           The amount of tokens.
    /// @param  messageId        The unique ID of the message.
    event TokenReceived(
        uint32 sourceChainId,
        address indexed destinationToken,
        bytes32 indexed sender,
        address indexed recipient,
        uint256 amount,
        bytes32 messageId
    );

    /// @notice Emitted when wrapping PYUSDX token to the Extension token is failed on the destination.
    /// @param  destinationExtension The address of PYUSDX Extension on the destination chain.
    /// @param  recipient            The account receiving tokens.
    /// @param  amount               The amount of tokens.
    event WrapFailed(address indexed destinationExtension, address indexed recipient, uint256 amount);

    /// @notice Emitted when the gas limit for processing messages on a destination chain is updated.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  gasLimit           The maximum gas allocated for message execution on the destination chain.
    event PayloadGasLimitSet(uint32 indexed destinationChainId, uint256 gasLimit);

    /// @notice Emitted when the default bridge adapter for a destination chain is set.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  bridgeAdapter      The address of the bridge adapter.
    event DefaultBridgeAdapterSet(uint32 indexed destinationChainId, address indexed bridgeAdapter);

    /// @notice Emitted when a supported bridge adapter for a destination chain is set.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  bridgeAdapter      The address of the bridge adapter.
    /// @param  supported          `True` if the bridge adapter is supported, `false` otherwise.
    event SupportedBridgeAdapterSet(uint32 indexed destinationChainId, address indexed bridgeAdapter, bool supported);

    /// @notice Emitted when sending is paused.
    event SendPaused();

    /// @notice Emitted when sending is unpaused.
    event SendUnpaused();

    /// @notice Emitted when receiving is paused.
    event ReceivePaused();

    /// @notice Emitted when receiving is unpaused.
    event ReceiveUnpaused();

    /// @notice Emitted when the fallback recipient is set.
    /// @param  fallbackRecipient The address that receives PYUSDX on the destination chain when the intended recipient is frozen.
    event FallbackRecipientSet(address indexed fallbackRecipient);

    /// @notice Emitted when an inbound transfer is routed to the fallback recipient because the intended recipient is frozen.
    /// @param  sourceChainId     The ID of the source chain.
    /// @param  destinationToken  The address of the token on the destination chain.
    /// @param  sender            The account that sent the tokens.
    /// @param  recipient         The intended recipient that is frozen.
    /// @param  amount            The amount of tokens.
    /// @param  messageId         The unique ID of the message.
    /// @param  fallbackRecipient The address that received the tokens instead of the frozen recipient.
    event RedirectedToFallbackRecipient(
        uint32 sourceChainId,
        address indexed destinationToken,
        bytes32 indexed sender,
        address indexed recipient,
        uint256 amount,
        bytes32 messageId,
        address fallbackRecipient
    );

    /* ============ Custom Errors ============ */

    /// @notice Thrown when the PYUSDX token is 0x0.
    error ZeroPYUSDXToken();

    /// @notice Thrown when the Swap Facility address is 0x0.
    error ZeroSwapFacility();

    /// @notice Thrown when the admin address is 0x0.
    error ZeroAdmin();

    /// @notice Thrown when the pauser address is 0x0.
    error ZeroPauser();

    /// @notice Thrown when the operator address is 0x0.
    error ZeroOperator();

    /// @notice Thrown when the source token address is 0x0.
    error ZeroSourceToken();

    /// @notice Thrown when the destination token address is 0x0.
    error ZeroDestinationToken();

    /// @notice Thrown when the transfer amount is 0.
    error ZeroAmount();

    /// @notice Thrown when the refund address is 0x0.
    error ZeroRefundAddress();

    /// @notice Thrown when the recipient address is 0x0.
    error ZeroRecipient();

    /// @notice Thrown when the bridge adapter address is 0x0.
    error ZeroBridgeAdapter();

    /// @notice Thrown when the fallback recipient address is 0x0.
    error ZeroFallbackRecipient();

    /// @notice Thrown when the destination chain id is equal to the source one.
    error InvalidDestinationChain(uint32 destinationChainId);

    /// @notice Thrown when the bridge adapter is not supported for the destination chain.
    error UnsupportedBridgeAdapter(uint32 destinationChainId, address bridgeAdapter);

    /// @notice Thrown in `sendToken` function when the actual amount received is less than the specified amount.
    error InsufficientAmountReceived(uint256 specifiedAmount, uint256 actualAmount);

    /// @notice Thrown when sending is paused.
    error SendingPaused();

    /// @notice Thrown when receiving is paused.
    error ReceivingPaused();

    /// @notice Thrown  on the destination when a message with the given ID has already been processed.
    error MessageAlreadyProcessed(bytes32 messageId);

    /// @notice Thrown on the destination when the target chain ID does not match the current chain ID.
    error InvalidTargetChain(uint32 targetChainId);

    /// @notice Thrown on the destination when the target bridge adapter does not match the current adapter.
    error InvalidTargetBridgeAdapter(address targetBridgeAdapter);

    /// @notice Thrown when the gas limit for the specified payload type is not configured.
    error PayloadGasLimitNotSet(uint32 destinationChainId);

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can pause and unpause sending and receiving cross-chain messages.
    function PAUSER_ROLE() external view returns (bytes32);

    /// @notice The role that can configure the Portal.
    function OPERATOR_ROLE() external view returns (bytes32);

    /// @notice The address of PYUSDX token.
    function pyusdx() external view returns (address);

    /// @notice The address of the Swap Facility contract.
    function swapFacility() external view returns (address);

    /// @notice The address that receives PYUSDX or PYUSDX Extension on the destination chain when the intended recipient is frozen.
    /// @dev    Used as a safety fallback to prevent inbound cross-chain transfers from reverting when the
    ///         original recipient cannot receive tokens.
    function fallbackRecipient() external view returns (address);

    /// @notice The ID of the chain on which the Portal contract is deployed.
    function currentChainId() external view returns (uint32);

    /// @notice Returns the current nonce used for generating unique message IDs.
    function getNonce() external view returns (uint256);

    /// @notice Returns the default bridge adapter for the given destination chain.
    /// @param  destinationChainId The ID of the destination chain.
    function defaultBridgeAdapter(uint32 destinationChainId) external view returns (address);

    /// @notice Indicates whether the provided bridge adapter is supported for the destination chain.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  bridgingAdapter    The address of the bridge adapter.
    function supportedBridgeAdapter(uint32 destinationChainId, address bridgingAdapter) external view returns (bool);

    /// @notice Returns the gas limit required to process a message on the destination chain.
    /// @param  destinationChainId The ID of the destination chain.
    function payloadGasLimit(uint32 destinationChainId) external view returns (uint256);

    /// @notice The address of the original caller of `sendToken` function.
    function msgSender() external view returns (address);

    /// @notice Returns the fee for delivering a cross-chain message using the default bridge adapter.
    /// @dev    The fee must be passed as msg.value when calling `sendToken`.
    /// @param  destinationChainId The ID of the destination chain.
    function quote(uint32 destinationChainId) external view returns (uint256);

    /// @notice Returns the fee for delivering a cross-chain message using the specified bridge adapter.
    /// @dev    The fee must be passed as msg.value when calling `sendToken`.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  bridgeAdapter      The address of the bridge adapter.
    function quote(uint32 destinationChainId, address bridgeAdapter) external view returns (uint256);

    /// @notice Indicates whether sending cross-chain messages is paused.
    function sendPaused() external view returns (bool);

    /// @notice Indicates whether receiving cross-chain messages is paused.
    function receivePaused() external view returns (bool);

    /* ============ Interactive Functions ============ */

    /// @notice Sets the gas limit required to process a message on the destination chain.
    /// @dev    Passing `gasLimit = 0` clears the configured gas limit, which disables `quote` and
    ///         `transfer` for that destination chain until a non-zero gas limit is set again.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  gasLimit           The gas limit required to process the message, or 0 to unset it.
    function setPayloadGasLimit(uint32 destinationChainId, uint256 gasLimit) external;

    /// @notice Sets the default bridge adapter for a destination chain.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  bridgeAdapter      The address of the bridge adapter.
    function setDefaultBridgeAdapter(uint32 destinationChainId, address bridgeAdapter) external;

    /// @notice Sets a supported bridge adapter for a destination chain.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  bridgeAdapter      The address of the bridge adapter.
    /// @param  supported          `True` if the bridge adapter is supported, `false` otherwise.
    function setSupportedBridgeAdapter(uint32 destinationChainId, address bridgeAdapter, bool supported) external;

    /// @notice Sets the address that receives PYUSDX or PYUSDX Extension on the destination chain when the intended recipient is frozen.
    /// @param  fallbackRecipient The address of the fallback recipient.
    function setFallbackRecipient(address fallbackRecipient) external;

    /// @notice Transfers PYUSDX or PYUSDX Extension to the destination chain using the default bridge adapter.
    /// @dev    If wrapping on the destination fails, the recipient will receive PYUSDX token.
    /// @param  amount             The amount of tokens to transfer.
    /// @param  sourceToken        The address of the token (PYUSDX or PYUSDX Extension) on the source chain.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  destinationToken   The address of the token (PYUSDX or PYUSDX Extension) on the destination chain.
    /// @param  recipient          The account to receive tokens.
    /// @param  refundAddress      The address to receive excess native gas on the source chain.
    /// @return messageId          The unique identifier of the message sent.
    function sendToken(
        uint256 amount,
        address sourceToken,
        uint32 destinationChainId,
        bytes32 destinationToken,
        bytes32 recipient,
        bytes32 refundAddress
    ) external payable returns (bytes32 messageId);

    /// @notice Transfers PYUSDX Token or PYUSDX Extension to the destination chain using the specified bridge adapter.
    /// @dev    If wrapping on the destination fails, the recipient will receive PYUSDX token.
    /// @param  amount             The amount of tokens to transfer.
    /// @param  sourceToken        The address of the token (PYUSDX or PYUSDX Extension) on the source chain.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  destinationToken   The address of the token (PYUSDX or PYUSDX Extension) on the destination chain.
    /// @param  recipient          The account to receive tokens.
    /// @param  refundAddress      The address to receive excess native gas on the source chain.
    /// @param  bridgeAdapter      The address of the bridge adapter to use.
    /// @return messageId          The unique identifier of the message sent.
    function sendToken(
        uint256 amount,
        address sourceToken,
        uint32 destinationChainId,
        bytes32 destinationToken,
        bytes32 recipient,
        bytes32 refundAddress,
        address bridgeAdapter
    ) external payable returns (bytes32 messageId);

    /// @notice Receives a message from the bridge.
    /// @param  sourceChainId The chain Id of the source chain.
    /// @param  payload       The message payload.
    function receiveMessage(uint32 sourceChainId, bytes calldata payload) external;

    /// @notice Pauses sending cross-chain messages.
    function pauseSend() external;

    /// @notice Unpauses sending cross-chain messages.
    function unpauseSend() external;

    /// @notice Pauses receiving cross-chain messages.
    function pauseReceive() external;

    /// @notice Unpauses receiving cross-chain messages.
    function unpauseReceive() external;

    /// @notice Pauses both sending and receiving cross-chain messages.
    function pauseAll() external;

    /// @notice Unpauses both sending and receiving cross-chain messages.
    function unpauseAll() external;
}
