// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.34;

/// @title  BytesParser
/// @author Wormhole Labs
/// @notice Parses tightly packed data.
/// @dev    Modified from
///         https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/main/src/libraries/BytesParsing.sol
library BytesParser {
    error LengthMismatch(uint256 encodedLength, uint256 expectedLength);
    error InvalidBool(uint8 value);

    function checkLength(bytes memory encoded, uint256 expected) internal pure {
        if (encoded.length != expected) revert LengthMismatch(encoded.length, expected);
    }

    function asUint8Unchecked(
        bytes memory encoded,
        uint256 offset
    ) internal pure returns (uint8 value, uint256 nextOffset) {
        assembly ("memory-safe") {
            nextOffset := add(offset, 1)
            value := mload(add(encoded, nextOffset))
        }
    }

    function asUint256Unchecked(
        bytes memory encoded,
        uint256 offset
    ) internal pure returns (uint256 value, uint256 nextOffset) {
        assembly ("memory-safe") {
            nextOffset := add(offset, 32)
            value := mload(add(encoded, nextOffset))
        }
    }

    function asUint128Unchecked(
        bytes memory encoded,
        uint256 offset
    ) internal pure returns (uint128 value, uint256 nextOffset) {
        assembly ("memory-safe") {
            nextOffset := add(offset, 16)
            value := mload(add(encoded, nextOffset))
        }
    }

    function asUint32Unchecked(
        bytes memory encoded,
        uint256 offset
    ) internal pure returns (uint32 value, uint256 nextOffset) {
        assembly ("memory-safe") {
            nextOffset := add(offset, 4)
            value := mload(add(encoded, nextOffset))
        }
    }

    function asBytes32Unchecked(
        bytes memory encoded,
        uint256 offset
    ) internal pure returns (bytes32 value, uint256 nextOffset) {
        uint256 uint256Value;
        (uint256Value, nextOffset) = asUint256Unchecked(encoded, offset);
        value = bytes32(uint256Value);
    }
}
