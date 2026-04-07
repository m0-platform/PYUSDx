// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

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
    uint256 internal constant COMPOSER_LENGTH = 32;

    // Field offsets within the payload (literal values required for inline assembly).
    uint256 internal constant MESSAGE_ID_OFFSET = 37; // PAYLOAD_TYPE_LENGTH + DESTINATION_CHAIN_ID_LENGTH + DESTINATION_PEER_LENGTH: 1 + 4 + 32
    uint256 internal constant AMOUNT_OFFSET = 69; // MESSAGE_ID_OFFSET + MESSAGE_ID_LENGTH: 37 + 32
    uint256 internal constant DESTINATION_TOKEN_OFFSET = 85; // AMOUNT_OFFSET + AMOUNT_LENGTH: 69 + 16
    uint256 internal constant SENDER_OFFSET = 117; // DESTINATION_TOKEN_OFFSET + DESTINATION_TOKEN_LENGTH: 85 + 32
    uint256 internal constant RECIPIENT_OFFSET = 149; // SENDER_OFFSET + SENDER_LENGTH: 117 + 32
    uint256 internal constant COMPOSER_OFFSET = 181; // RECIPIENT_OFFSET + RECIPIENT_LENGTH: 149 + 32
    uint256 internal constant COMPOSED_MSG_OFFSET = 213; // COMPOSER_OFFSET + COMPOSER_LENGTH: 181 + 32

    uint256 internal constant MIN_PAYLOAD_LENGTH = 181; // RECIPIENT_OFFSET + RECIPIENT_LENGTH: 149 + 32

    uint256 internal constant ADDRESS_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;

    /// @dev Right-shift to extract uint8 from a 32-byte word: 256 - 8
    uint256 internal constant UINT8_SHIFT = 248;

    /// @dev Right-shift to extract uint128 from a 32-byte word: 256 - 128
    uint256 internal constant UINT128_SHIFT = 128;

    error InvalidPayloadLength(uint256 length);
    error InvalidPayloadType(uint8 value);

    /// @notice Decodes the payload type from the payload.
    /// @param  payload The payload to decode.
    function decodePayloadType(bytes calldata payload) internal pure returns (PayloadType) {
        if (payload.length < MIN_PAYLOAD_LENGTH) revert InvalidPayloadLength(payload.length);

        uint8 payloadType;
        assembly {
            payloadType := shr(UINT8_SHIFT, calldataload(payload.offset))
        }

        if (payloadType > uint8(type(PayloadType).max)) revert InvalidPayloadType(payloadType);
        return PayloadType(payloadType);
    }

    /// @notice Decodes the message ID from the payload.
    /// @param  payload   The payload to decode.
    /// @return messageId The message ID.
    function decodeMessageId(bytes calldata payload) internal pure returns (bytes32 messageId) {
        if (payload.length < MIN_PAYLOAD_LENGTH) revert InvalidPayloadLength(payload.length);

        assembly {
            messageId := calldataload(add(payload.offset, MESSAGE_ID_OFFSET))
        }
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
    /// @return amount           The amount of tokens to transfer.
    /// @return destinationToken The address of the destination token.
    /// @return sender           The address of the sender.
    /// @return recipient        The address of the recipient.
    function decodeTokenTransfer(
        bytes calldata payload
    ) internal pure returns (uint256 amount, address destinationToken, bytes32 sender, address recipient) {
        if (payload.length != MIN_PAYLOAD_LENGTH) revert InvalidPayloadLength(payload.length);

        (amount, destinationToken, sender, recipient) = _decodeTokenTransfer(payload);
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
    /// @param composer           The address of the contract on the destination chain that will receive the composed message via `lzCompose`.
    /// @param composedMessage    The arbitrary calldata forwarded to the composer contract via `lzCompose`.
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
        bytes calldata payload
    )
        internal
        pure
        returns (
            uint256 amount,
            address destinationToken,
            bytes32 sender,
            address recipient,
            address composer,
            bytes calldata composedMessage
        )
    {
        if (payload.length < MIN_PAYLOAD_LENGTH + COMPOSER_LENGTH) revert InvalidPayloadLength(payload.length);

        (amount, destinationToken, sender, recipient) = _decodeTokenTransfer(payload);

        assembly {
            let offset := payload.offset
            composer := and(calldataload(add(offset, COMPOSER_OFFSET)), ADDRESS_MASK)
            composedMessage.offset := add(offset, COMPOSED_MSG_OFFSET)
            composedMessage.length := sub(payload.length, COMPOSED_MSG_OFFSET)
        }
    }

    /// @dev Decodes the common fields shared by TokenTransfer and ComposedTokenTransfer payloads.
    function _decodeTokenTransfer(
        bytes calldata payload
    ) private pure returns (uint256 amount, address destinationToken, bytes32 sender, address recipient) {
        assembly {
            let offset := payload.offset
            amount := shr(UINT128_SHIFT, calldataload(add(offset, AMOUNT_OFFSET)))
            destinationToken := and(calldataload(add(offset, DESTINATION_TOKEN_OFFSET)), ADDRESS_MASK)
            sender := calldataload(add(offset, SENDER_OFFSET))
            recipient := and(calldataload(add(offset, RECIPIENT_OFFSET)), ADDRESS_MASK)
        }
    }

    /// @notice Generates a payload with empty data
    /// @dev    Used for estimating gas costs when the actual payload doesn't matter.
    function generateEmptyPayload() internal pure returns (bytes memory) {
        return encodeTokenTransfer(0, bytes32(0), bytes32(0), 0, bytes32(0), address(0), bytes32(0));
    }
}
