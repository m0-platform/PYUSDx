// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

/// @title  StateReader
/// @notice Best-effort reads of on-chain configuration used to decide whether a setting is already
///         applied.
/// @dev Missing getters, failed calls, truncated data and a non-standard head offset return false.
///      Struct checks are preliminary: the caller's ABI decoder can still reject malformed inner
///      offsets, lengths or scalar encoding. Such data aborts planning rather than being skipped.
library StateReader {
    /// @dev Minimum length of an ABI-encoded `UlnConfig` return: the head offset, six struct words
    ///      (four scalars and two array offsets), and a length word for each of the two arrays.
    uint256 internal constant ULN_CONFIG_MIN_RETURN_LENGTH = 32 + (6 * 32) + (2 * 32);

    /// @dev Offset written by every standard ABI encoder for a single dynamic return value.
    bytes32 private constant _STANDARD_HEAD_OFFSET = bytes32(uint256(32));

    /// @notice Reads a getter that returns exactly one 32-byte value.
    /// @param  target The contract to read.
    /// @param  data   The ABI-encoded call.
    /// @return word   The returned word, or zero when the read failed.
    /// @return ok     Whether the call succeeded and returned exactly one word.
    function readWord(address target, bytes memory data) internal view returns (bytes32 word, bool ok) {
        (bool success, bytes memory returnData) = target.staticcall(data);

        if (!success || returnData.length != 32) return (bytes32(0), false);

        return (abi.decode(returnData, (bytes32)), true);
    }

    /// @notice Reads a getter that returns a single ABI-encoded struct, checking the return data is
    ///         long enough and starts with the standard head offset before it is decoded.
    /// @param  target       The contract to read.
    /// @param  data         The ABI-encoded call.
    /// @param  minLength    The minimum plausible return-data length for the expected struct.
    /// @return returnData   The raw return data, or empty when the read failed.
    /// @return ok           Whether the call succeeded and passed the preliminary shape checks.
    function readStruct(
        address target,
        bytes memory data,
        uint256 minLength
    ) internal view returns (bytes memory returnData, bool ok) {
        bool success;
        (success, returnData) = target.staticcall(data);

        if (!success || returnData.length < minLength) return ("", false);
        if (bytes32(returnData) != _STANDARD_HEAD_OFFSET) return ("", false);

        return (returnData, true);
    }
}
