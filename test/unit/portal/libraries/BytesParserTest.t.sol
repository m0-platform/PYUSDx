// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import { BytesParser } from "../../../../src/portal/libraries/BytesParser.sol";

contract BytesParserTest is Test {
    using BytesParser for bytes;

    function test_asUint256Unchecked() external pure {
        bytes memory data = abi.encodePacked(uint256(1));

        (uint256 value, uint256 nextOffset) = data.asUint256Unchecked(0);
        assertEq(value, 1);
        assertEq(nextOffset, 32);
    }

    function testFuzz_asUint256Unchecked(uint256 inputValue) external pure {
        bytes memory data = abi.encodePacked(inputValue);

        (uint256 value, uint256 nextOffset) = data.asUint256Unchecked(0);
        assertEq(value, inputValue);
        assertEq(nextOffset, 32);
    }

    function test_asUint128Unchecked() external pure {
        bytes memory data = abi.encodePacked(uint128(1));

        (uint128 value, uint256 nextOffset) = data.asUint128Unchecked(0);
        assertEq(value, 1);
        assertEq(nextOffset, 16);
    }

    function testFuzz_asUint128Unchecked(uint128 inputValue) external pure {
        bytes memory data = abi.encodePacked(inputValue);

        (uint128 value, uint256 nextOffset) = data.asUint128Unchecked(0);
        assertEq(value, inputValue);
        assertEq(nextOffset, 16);
    }

    function test_asUint32Unchecked() external pure {
        bytes memory data = abi.encodePacked(uint32(1));

        (uint32 value, uint256 nextOffset) = data.asUint32Unchecked(0);
        assertEq(value, 1);
        assertEq(nextOffset, 4);
    }

    function testFuzz_asUint32Unchecked(uint32 inputValue) external pure {
        bytes memory data = abi.encodePacked(inputValue);

        (uint32 value, uint256 nextOffset) = data.asUint32Unchecked(0);
        assertEq(value, inputValue);
        assertEq(nextOffset, 4);
    }

    function test_asBytes32Unchecked() external pure {
        bytes memory data = abi.encodePacked(bytes32(uint256(1)));

        (bytes32 value, uint256 nextOffset) = data.asBytes32Unchecked(0);
        assertEq(value, bytes32(uint256(1)));
        assertEq(nextOffset, 32);
    }

    function testFuzz_asBytes32Unchecked(bytes32 inputValue) external pure {
        bytes memory data = abi.encodePacked(inputValue);

        (bytes32 value, uint256 nextOffset) = data.asBytes32Unchecked(0);
        assertEq(value, inputValue);
        assertEq(nextOffset, 32);
    }
}
