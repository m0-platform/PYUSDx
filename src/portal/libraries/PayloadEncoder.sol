// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import { BytesParser } from "../../../lib/evm-m-extensions/lib/common/src/libs/BytesParser.sol";
import { TypeConverter } from "../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

/// @notice Payload types for cross-chain messages.
/// @dev    Initially only the `TokenTransfer` payload type is supported,
///         but the list can be extended in the future to support additional message types
///         (e.g., order book fill and cancel reports).
enum PayloadType {
    TokenTransfer
}

/// @title  PayloadEncoder
/// @author M0 Labs
/// @notice Encodes and decodes cross-chain message payloads.
library PayloadEncoder {
    using BytesParser for bytes;
    using TypeConverter for *;

    /// @dev Token Transfer payloads have the following structure:
    /// ┌──────────────────────┬──────────────────┬────────────┬───────────┬───────────────────┬────────────┬─────────────┐
    /// │ Destination Chain ID │ Destination Peer │ Message ID │  Amount   │ Destination Token │   Sender   |  Recipient  │
    /// │       (uint32)       │    (bytes32)     │  (bytes32) │ (uint128) │     (bytes32)     │  (bytes32) │  (bytes32)  │
    /// │       4 bytes        │    32 bytes      │  32 bytes  │ 16 bytes  │      32 bytes     │   32 bytes │   32 bytes  │
    /// └──────────────────────┴──────────────────┴────────────┴───────────┴───────────────────┴────────────┴─────────────┘
    uint256 internal constant DESTINATION_CHAIN_ID_LENGTH = 4;
    uint256 internal constant DESTINATION_PEER_LENGTH = 32;
    uint256 internal constant MESSAGE_ID_LENGTH = 32;
    uint256 internal constant AMOUNT_LENGTH = 16;
    uint256 internal constant DESTINATION_TOKEN_LENGTH = 32;
    uint256 internal constant SENDER_LENGTH = 32;
    uint256 internal constant RECIPIENT_LENGTH = 32;

    uint256 internal constant PAYLOAD_LENGTH =
        DESTINATION_CHAIN_ID_LENGTH +
            DESTINATION_PEER_LENGTH +
            MESSAGE_ID_LENGTH +
            AMOUNT_LENGTH +
            DESTINATION_TOKEN_LENGTH +
            SENDER_LENGTH +
            RECIPIENT_LENGTH;

    error InvalidPayloadLength(uint256 length);

    /// @notice Encodes a token transfer payload.
    /// @dev    Encoded values are packed using `abi.encodePacked`.
    /// @param destinationChainId The destination chain ID.
    /// @param destinationPeer    The address of the peer bridge adapter on the destination chain.
    /// @param messageId          The message ID.
    /// @param amount             The amount of tokens to transfer.
    /// @param destinationToken   The address of the destination token.
    /// @param sender             The address of the sender.
    /// @param recipient          The address of the recipient.
    function encodeTokenTransfer(
        uint32 destinationChainId,
        bytes32 destinationPeer,
        bytes32 messageId,
        uint256 amount,
        bytes32 destinationToken,
        address sender,
        bytes32 recipient
    ) internal pure returns (bytes memory) {
        // Converting addresses to `bytes32` and amount to `uint128` to support non-EVM chains.
        return
            abi.encodePacked(
                destinationChainId,
                destinationPeer,
                messageId,
                amount.toUint128(),
                destinationToken,
                sender.toBytes32(),
                recipient
            );
    }

    /// @notice Decodes a token transfer payload.
    /// @param  payload            The payload to decode.
    /// @return destinationChainId The destination chain ID.
    /// @return destinationPeer    The address of the peer bridge adapter on the destination chain.
    /// @return messageId          The message ID.
    /// @return amount             The amount of tokens to transfer.
    /// @return destinationToken   The address of the destination token.
    /// @return sender             The address of the sender.
    /// @return recipient          The address of the recipient.
    function decodeTokenTransfer(
        bytes memory payload
    )
        internal
        pure
        returns (
            uint32 destinationChainId,
            address destinationPeer,
            bytes32 messageId,
            uint256 amount,
            address destinationToken,
            bytes32 sender,
            address recipient
        )
    {
        if (payload.length != PAYLOAD_LENGTH) revert InvalidPayloadLength(payload.length);

        uint256 offset = 0;
        bytes32 destinationPeerBytes32;
        bytes32 destinationTokenBytes32;
        bytes32 recipientBytes32;

        (destinationChainId, offset) = payload.asUint32Unchecked(offset);
        (destinationPeerBytes32, offset) = payload.asBytes32Unchecked(offset);
        (messageId, offset) = payload.asBytes32Unchecked(offset);
        (amount, offset) = payload.asUint128Unchecked(offset);
        (destinationTokenBytes32, offset) = payload.asBytes32Unchecked(offset);
        (sender, offset) = payload.asBytes32Unchecked(offset);
        (recipientBytes32, offset) = payload.asBytes32Unchecked(offset);

        destinationPeer = destinationPeerBytes32.toAddress();
        destinationToken = destinationTokenBytes32.toAddress();
        recipient = recipientBytes32.toAddress();

        payload.checkLength(offset);
    }

    /// @notice Generates a payload with empty data
    /// @dev    Used for estimating gas costs when the actual payload doesn't matter.
    function generateEmptyPayload() internal pure returns (bytes memory) {
        return encodeTokenTransfer(0, bytes32(0), bytes32(0), 0, bytes32(0), address(0), bytes32(0));
    }
}
