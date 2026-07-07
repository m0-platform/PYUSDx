// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { IOFT } from "./IOFT.sol";

/// @title  IPortalOFTWrapper interface
/// @author M0 Labs
/// @notice Interface for the send-only OFT facade exposing PYUSDX and PYUSDX Extension tokens
///         to LayerZero Stargate by forwarding quote and send requests to the Portal.
interface IPortalOFTWrapper is IOFT {
    /* ============ Events ============ */

    /// @notice Emitted when the destination token for a LayerZero Endpoint ID is set.
    /// @param  destinationEid   The destination LayerZero Endpoint ID.
    /// @param  destinationToken The address of the token on the destination chain.
    event DestinationTokenSet(uint32 indexed destinationEid, bytes32 destinationToken);

    /// @notice Emitted when the destination token for a LayerZero Endpoint ID is removed.
    /// @param  destinationEid The destination LayerZero Endpoint ID.
    event DestinationTokenRemoved(uint32 indexed destinationEid);

    /* ============ Custom Errors ============ */

    /// @notice Thrown when the Portal address is 0x0.
    error ZeroPortal();

    /// @notice Thrown when the bridge adapter address is 0x0.
    error ZeroBridgeAdapter();

    /// @notice Thrown when the token address is 0x0.
    error ZeroToken();

    /// @notice Thrown when the admin address is 0x0.
    error ZeroAdmin();

    /// @notice Thrown when the operator address is 0x0.
    error ZeroOperator();

    /// @notice Thrown when the destination LayerZero Endpoint ID is 0.
    error ZeroDestinationEid();

    /// @notice Thrown when the destination token address is 0x0.
    error ZeroDestinationToken();

    /// @notice Thrown when no destination token is configured for the LayerZero Endpoint ID,
    ///         or the LayerZero bridge adapter has no chain ID mapping for it.
    error UnsupportedDestinationEid(uint32 destinationEid);

    /// @notice Thrown when the caller requests paying fees in the LayerZero token,
    ///         which is unsupported since the Portal quotes and pays native fees only.
    error LayerZeroTokenUnsupported();

    /// @notice Thrown when the caller supplies a compose message. The Portal path executes a
    ///         plain token transfer on the destination, so `lzCompose` would never be invoked;
    ///         accepting the message would silently drop its semantics and could strand funds
    ///         on a composer recipient.
    error ComposeMsgUnsupported();

    /// @notice Thrown when the caller supplies an OFT command, which has no meaning on the
    ///         Portal path and would otherwise be silently ignored.
    error OFTCmdUnsupported();

    /* ============ Interactive Functions ============ */

    /// @notice Initializes the Proxy's storage.
    /// @param  admin    The address of the admin.
    /// @param  operator The address of the operator.
    function initialize(address admin, address operator) external;

    /// @notice Sets the destination token for a LayerZero Endpoint ID.
    /// @dev    The destination chain ID is not configured here: it is derived from the LayerZero
    ///         bridge adapter's Endpoint ID mapping, so the wrapper's routing cannot diverge from it.
    /// @param  destinationEid   The destination LayerZero Endpoint ID.
    /// @param  destinationToken The address of the token on the destination chain.
    function setDestinationToken(uint32 destinationEid, bytes32 destinationToken) external;

    /// @notice Removes the destination token for a LayerZero Endpoint ID.
    /// @param  destinationEid The destination LayerZero Endpoint ID.
    function removeDestinationToken(uint32 destinationEid) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can configure destination routes.
    function OPERATOR_ROLE() external view returns (bytes32);

    /// @notice The address of the Portal contract sends are forwarded to.
    function portal() external view returns (address);

    /// @notice The address of the LayerZero bridge adapter used for every send.
    /// @dev    Pinned so that Stargate transfers always travel over LayerZero regardless of the
    ///         Portal's default bridge adapter. Stargate resolves delivery status via LayerZero Scan,
    ///         which only marks a transfer delivered when the message completes over LayerZero.
    function layerZeroBridgeAdapter() external view returns (address);

    /// @notice Returns the destination token for a LayerZero Endpoint ID.
    /// @param  destinationEid   The destination LayerZero Endpoint ID.
    /// @return destinationToken The address of the token on the destination chain, or 0x0 if unset.
    function getDestinationToken(uint32 destinationEid) external view returns (bytes32 destinationToken);
}
