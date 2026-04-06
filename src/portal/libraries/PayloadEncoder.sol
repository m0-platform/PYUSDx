// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import { BytesParser } from "../../../lib/evm-m-extensions/lib/common/src/libs/BytesParser.sol";
import { TypeConverter } from "../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

/// @notice Payload types for cross-chain messages
enum PayloadType {
    TokenTransfer,
    ComposedTokenTransfer
}

/// @title  PayloadEncoder
/// @author M0 Labs
/// @notice Encodes and decodes cross-chain message payloads.
library PayloadEncoder {
    using BytesParser for bytes;
    using TypeConverter for *;

    /// @dev Both TokenTransfer and ComposedTokenTransfer payloads have the following structure:
    /// ┌──────────────┬──────────────────────┬──────────────────┬────────────┬───────────┬───────────────────┬────────────┬─────────────┬───────────────────────┐
    /// │ Payload Type │ Destination Chain ID │ Destination Peer │ Message ID │  Amount   │ Destination Token │   Sender   |  Recipient  │ Payload Specific Data │
    /// │   (uint8)    │       (uint32)       │    (bytes32)     │  (bytes32) │ (uint128) │     (bytes32)     │  (bytes32) │  (bytes32)  │  (variable length)    │
    /// │   1 byte     │        32 bytes      │    32 bytes      │  32 bytes  │  16 bytes │      32 bytes     │   32 bytes │   32 bytes  │                       │
    /// └──────────────┴──────────────────────┴──────────────────┴────────────┴───────────┴───────────────────┴────────────┴─────────────┴───────────────────────┘
    uint256 internal constant PAYLOAD_TYPE_LENGTH = 1;
    uint256 internal constant DESTINATION_CHAIN_ID_LENGTH = 4;
    uint256 internal constant DESTINATION_PEER_LENGTH = 32;
    uint256 internal constant MESSAGE_ID_LENGTH = 32;
    uint256 internal constant AMOUNT_LENGTH = 16;
    uint256 internal constant DESTINATION_TOKEN_LENGTH = 32;
    uint256 internal constant SENDER_LENGTH = 32;
    uint256 internal constant RECIPIENT_LENGTH = 32;
    uint256 internal constant OFFSET = PAYLOAD_TYPE_LENGTH + DESTINATION_CHAIN_ID_LENGTH + DESTINATION_PEER_LENGTH;

    uint256 internal constant MIN_PAYLOAD_LENGTH =
        PAYLOAD_TYPE_LENGTH +
            DESTINATION_CHAIN_ID_LENGTH +
            DESTINATION_PEER_LENGTH +
            MESSAGE_ID_LENGTH +
            AMOUNT_LENGTH +
            DESTINATION_TOKEN_LENGTH +
            SENDER_LENGTH +
            RECIPIENT_LENGTH;

    error InvalidPayloadLength(uint256 length);
    error InvalidPayloadType(uint8 value);

    /// @notice Decodes the payload type from the payload.
    /// @param  payload The payload to decode.
    function decodePayloadType(bytes calldata payload) internal pure returns (PayloadType) {
        if (payload.length < MIN_PAYLOAD_LENGTH) revert InvalidPayloadLength(payload.length);

        uint8 payloadType;
        (payloadType, ) = payload.asUint8Unchecked(0);

        if (payloadType > uint8(type(PayloadType).max)) revert InvalidPayloadType(payloadType);
        return PayloadType(payloadType);
    }

    /// @notice Decodes the message ID from the payload.
    /// @param  payload   The payload to decode.
    /// @return messageId The message ID.
    function decodeMessageId(bytes memory payload) internal pure returns (bytes32 messageId) {
        if (payload.length < MIN_PAYLOAD_LENGTH) revert InvalidPayloadLength(payload.length);

        (messageId, ) = payload.asBytes32Unchecked(OFFSET);
    }

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
                PayloadType.TokenTransfer,
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
    /// @param  payload          The payload to decode.
    /// @return messageId        The message ID.
    /// @return amount           The amount of tokens to transfer.
    /// @return destinationToken The address of the destination token.
    /// @return sender           The address of the sender.
    /// @return recipient        The address of the recipient.
    function decodeTokenTransfer(
        bytes memory payload
    )
        internal
        pure
        returns (bytes32 messageId, uint256 amount, address destinationToken, bytes32 sender, address recipient)
    {
        uint256 offset = OFFSET;
        bytes32 destinationTokenBytes32;
        bytes32 recipientBytes32;

        (messageId, offset) = payload.asBytes32Unchecked(offset);
        (amount, offset) = payload.asUint128Unchecked(offset);
        (destinationTokenBytes32, offset) = payload.asBytes32Unchecked(offset);
        (sender, offset) = payload.asBytes32Unchecked(offset);
        (recipientBytes32, offset) = payload.asBytes32Unchecked(offset);

        destinationToken = destinationTokenBytes32.toAddress();
        recipient = recipientBytes32.toAddress();

        payload.checkLength(offset);
    }

    /// @notice Encodes a token transfer payload and composed message.
    /// @dev    Encoded values are packed using `abi.encodePacked`.
    /// @param destinationChainId The destination chain ID.
    /// @param destinationPeer    The address of the peer bridge adapter on the destination chain.
    /// @param messageId          The message ID.
    /// @param amount             The amount of tokens to transfer.
    /// @param destinationToken   The address of the destination token.
    /// @param sender             The address of the sender.
    /// @param recipient          The address of the recipient.
    function encodeComposedTokenTransfer(
        uint32 destinationChainId,
        bytes32 destinationPeer,
        bytes32 messageId,
        uint256 amount,
        bytes32 destinationToken,
        address sender,
        bytes32 recipient,
        bytes32 composer,
        bytes memory composedMessage
    ) internal pure returns (bytes memory) {
        // Converting addresses to `bytes32` and amount to `uint128` to support non-EVM chains.
        return
            abi.encodePacked(
                PayloadType.ComposedTokenTransfer,
                destinationChainId,
                destinationPeer,
                messageId,
                amount.toUint128(),
                destinationToken,
                sender.toBytes32(),
                recipient,
                composer,
                composedMessage
            );
    }

    function decodeComposedTokenTransfer(
        bytes memory payload
    )
        internal
        pure
        returns (
            bytes32 messageId,
            uint256 amount,
            address destinationToken,
            bytes32 sender,
            address recipient,
            address composer,
            bytes memory composedMessage
        )
    {
        uint256 offset = OFFSET;
        bytes32 destinationTokenBytes32;
        bytes32 recipientBytes32;
        bytes32 composerBytes32;

        (messageId, offset) = payload.asBytes32Unchecked(offset);
        (amount, offset) = payload.asUint128Unchecked(offset);
        (destinationTokenBytes32, offset) = payload.asBytes32Unchecked(offset);
        (sender, offset) = payload.asBytes32Unchecked(offset);
        (recipientBytes32, offset) = payload.asBytes32Unchecked(offset);
        (composerBytes32, offset) = payload.asBytes32Unchecked(offset);
        composedMessage = new bytes(payload.length - offset);
        assembly {
            mcopy(add(composedMessage, 0x20), add(add(payload, 0x20), offset), mload(composedMessage))
        }
        offset += composedMessage.length;

        destinationToken = destinationTokenBytes32.toAddress();
        recipient = recipientBytes32.toAddress();
        composer = composerBytes32.toAddress();

        payload.checkLength(offset);
    }

    /// @notice Generates a payload with empty data
    /// @dev    Used for estimating gas costs when the actual payload doesn't matter.
    function generateEmptyPayload() internal pure returns (bytes memory) {
        return encodeTokenTransfer(0, bytes32(0), bytes32(0), 0, bytes32(0), address(0), bytes32(0));
    }
}
