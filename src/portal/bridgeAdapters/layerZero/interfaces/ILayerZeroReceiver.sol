// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import { Origin } from "./ILayerZeroEndpointV2.sol";

/// @title  ILayerZeroReceiver
/// @author LayerZero Labs
/// @dev    Copied from:
///         https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroReceiver.sol
interface ILayerZeroReceiver {
    /// @notice Checks if the path initialization is allowed based on the provided origin.
    /// @dev    Indicates to endpoint that the receiver has enabled receiving messages for the specified path.
    /// @param  origin The origin information containing the source endpoint and sender address.
    /// @return true if the path has been initialized, false otherwise.
    function allowInitializePath(Origin calldata origin) external view returns (bool);

    /// @notice Returns the next expected nonce for a given source endpoint and sender.
    /// @dev    Used by the off-chain executor to determine if the receiver expects ordered message execution.
    ///         Nonces start from 1. Returning 0 disables nonce ordering enforcement.
    ///         Ordering is disabled by default (hardcoded to return 0).
    /// @param  eid    The source endpoint ID.
    /// @param  sender The sender address.
    /// @return nonce  The next expected nonce, or 0 if ordering is disabled.
    function nextNonce(uint32 eid, bytes32 sender) external view returns (uint64);

    /// @notice The entry point for receiving messages from LayerZero endpoint.
    /// @param  origin    The origin information containing the source endpoint and sender address.
    /// @param  guid      The unique identifier for the received LayerZero message.
    /// @param  message   The payload of the received message.
    /// @param  executor  The address of the executor for the received message.
    /// @param  extraData Additional arbitrary data provided by the executor.
    function lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external payable;
}
