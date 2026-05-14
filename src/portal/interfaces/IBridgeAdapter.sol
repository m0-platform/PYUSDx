// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  IBridgeAdapter interface
/// @author M0 Labs
/// @notice Interface defining a bridge adapter for cross-chain messaging functionality.
interface IBridgeAdapter {
    /* ============ Events ============ */

    /// @notice Emitted when the address of bridge adapter on the remote chain is set.
    /// @param  chainId The ID of the remote chain.
    /// @param  peer    The address of the bridge contract on the remote chain.
    event PeerSet(uint32 chainId, bytes32 peer);

    /// @notice Emitted when the provider-specific chain ID is set.
    /// @param  chainId       The ID of the chain.
    /// @param  bridgeChainId The provider-specific chain ID.
    event BridgeChainIdSet(uint32 chainId, uint256 bridgeChainId);

    /// @notice Emitted when a previously configured `(chainId, bridgeChainId)` pair is removed
    ///         as a side effect of `setBridgeChainId` reassigning either side of the 1-1 mapping.
    /// @param  chainId       The internal chain ID whose mapping was removed.
    /// @param  bridgeChainId The provider-specific chain ID whose mapping was removed.
    event BridgeChainIdRemoved(uint32 chainId, uint256 bridgeChainId);

    /* ============ Custom Errors ============ */

    /// @notice Thrown when `sendMessage` function caller is not the portal.
    error NotPortal();

    /// @notice Thrown when the portal address is 0x0.
    error ZeroPortal();

    /// @notice Thrown when the admin address is 0x0.
    error ZeroAdmin();

    /// @notice Thrown when the operator address is 0x0.
    error ZeroOperator();

    /// @notice Thrown when the chain ID is 0.
    error ZeroChain();

    /// @notice Thrown when the provider-specific chain ID is 0.
    error ZeroBridgeChain();

    /// @notice Thrown when the specified remote chain isn't supported.
    error UnsupportedChain(uint32 chainId);

    /// @notice Thrown when the specified remote bridge chain isn't supported.
    error UnsupportedBridgeChain(uint256 bridgeChainId);

    /// @notice Thrown when the source chain isn't supported or configured peer doesn't match the sender.
    error UnsupportedSender(bytes32 sender);

    /* ============ Interactive Functions ============ */

    /// @notice Sends a message to the remote chain.
    /// @param  destinationChainId The chain Id of the destination chain.
    /// @param  gasLimit           The gas limit to execute the message on the destination chain.
    /// @param  refundAddress      The address to refund the fee to.
    /// @param  payload            The message payload to send.
    function sendMessage(
        uint32 destinationChainId,
        uint256 gasLimit,
        bytes32 refundAddress,
        bytes memory payload
    ) external payable;

    /// @notice Sets an address of Bridge Adapter contract on the remote chain.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  destinationPeer    The address of the Bridge Adapter contract on the destination chain.
    function setPeer(uint32 destinationChainId, bytes32 destinationPeer) external;

    /// @notice Sets the provider-specific chain ID.
    /// @param  chainId       The ID of the chain.
    /// @param  bridgeChainId The provider-specific chain ID.
    function setBridgeChainId(uint32 chainId, uint256 bridgeChainId) external;

    /// @notice Initializes the Bridge Adapter Proxy contract.
    /// @param  admin    The address of the admin.
    /// @param  operator The address of the operator.
    function initialize(address admin, address operator) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can configure the bridge adapter.
    function OPERATOR_ROLE() external view returns (bytes32);

    /// @notice Returns the address of the portal.
    function portal() external view returns (address);

    /// @notice Returns the fee for sending a message to the remote chain
    /// @param  destinationChainId The chain Id of the destination chain.
    /// @param  gasLimit           The gas limit to execute the message on the destination chain.
    /// @param  payload            The message payload to send.
    /// @return fee                The fee for sending a message.
    function quote(
        uint32 destinationChainId,
        uint256 gasLimit,
        bytes memory payload
    ) external view returns (uint256 fee);

    /// @notice Returns the address of Bridge Adapter contract on the remote chain.
    /// @param  chainId The ID of the remote chain.
    function getPeer(uint32 chainId) external view returns (bytes32);

    /// @notice Returns the provider-specific chain ID.
    /// @param  chainId The internal ID of the chain.
    function getBridgeChainId(uint32 chainId) external view returns (uint256);

    /// @notice Returns the internal chain ID.
    /// @param  bridgeChainId The provider-specific chain ID.
    function getChainId(uint256 bridgeChainId) external view returns (uint32);
}
