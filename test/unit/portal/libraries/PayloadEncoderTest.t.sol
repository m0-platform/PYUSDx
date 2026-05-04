// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";
import { TypeConverter } from "../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";
import { PayloadEncoder } from "../../../../src/portal/libraries/PayloadEncoder.sol";

contract PayloadEncoderTest is Test {
    using PayloadEncoder for bytes;
    using TypeConverter for *;

    uint32 DESTINATION_CHAIN_ID = 1;
    address DESTINATION_PEER = makeAddr("peer");
    bytes32 MESSAGE_ID = "message id";

    function test_encodeTokenTransfer() external {
        uint256 amount = 1e6;
        bytes32 token = "destinationToken";
        bytes32 recipient = "recipient";
        address sender = makeAddr("sender");

        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            DESTINATION_CHAIN_ID,
            DESTINATION_PEER.toBytes32(),
            MESSAGE_ID,
            amount,
            token,
            sender,
            recipient
        );

        assertEq(
            payload,
            abi.encodePacked(
                DESTINATION_CHAIN_ID,
                DESTINATION_PEER.toBytes32(),
                MESSAGE_ID,
                amount.toUint128(),
                token,
                sender.toBytes32(),
                recipient
            )
        );
    }

    function testFuzz_encodeTokenTransfer(
        bytes32 messageId,
        uint256 amount,
        bytes32 token,
        address sender,
        bytes32 recipient
    ) external view {
        vm.assume(amount < type(uint128).max);
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            DESTINATION_CHAIN_ID,
            DESTINATION_PEER.toBytes32(),
            messageId,
            amount,
            token,
            sender,
            recipient
        );
        assertEq(
            payload,
            abi.encodePacked(
                DESTINATION_CHAIN_ID,
                DESTINATION_PEER.toBytes32(),
                messageId,
                amount.toUint128(),
                token,
                sender.toBytes32(),
                recipient
            )
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_decodeTokenTransfer_invalidPayloadLength() external {
        bytes memory payload = "";

        vm.expectRevert(abi.encodeWithSelector(PayloadEncoder.InvalidPayloadLength.selector, payload.length));
        PayloadEncoder.decodeTokenTransfer(payload);
    }

    function test_decodeTokenTransfer() external {
        bytes32 messageId = "messageId";
        uint256 amount = 1e6;
        address token = makeAddr("destinationToken");
        address recipient = makeAddr("recipient");
        address sender = makeAddr("sender");

        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            DESTINATION_CHAIN_ID,
            DESTINATION_PEER.toBytes32(),
            messageId,
            amount,
            token.toBytes32(),
            sender,
            recipient.toBytes32()
        );

        (
            uint32 decodedDestinationChainId,
            address decodedDestinationPeer,
            bytes32 decodedMessageId,
            uint256 decodedAmount,
            address decodedToken,
            bytes32 decodedSender,
            address decodedRecipient
        ) = PayloadEncoder.decodeTokenTransfer(payload);

        assertEq(decodedDestinationChainId, DESTINATION_CHAIN_ID);
        assertEq(decodedDestinationPeer, DESTINATION_PEER);
        assertEq(decodedMessageId, messageId);
        assertEq(decodedAmount, amount);
        assertEq(decodedToken, token);
        assertEq(decodedSender, sender.toBytes32());
        assertEq(decodedRecipient, recipient);
    }

    function testFuzz_decodeTokenTransfer(
        bytes32 messageId,
        uint256 amount,
        address token,
        address sender,
        address recipient
    ) external view {
        vm.assume(amount < type(uint128).max);

        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            DESTINATION_CHAIN_ID,
            DESTINATION_PEER.toBytes32(),
            messageId,
            amount,
            token.toBytes32(),
            sender,
            recipient.toBytes32()
        );
        (
            uint32 decodedDestinationChainId,
            address decodedDestinationPeer,
            bytes32 decodedMessageId,
            uint256 decodedAmount,
            address decodedToken,
            bytes32 decodedSender,
            address decodedRecipient
        ) = PayloadEncoder.decodeTokenTransfer(payload);

        assertEq(decodedDestinationChainId, DESTINATION_CHAIN_ID);
        assertEq(decodedDestinationPeer, DESTINATION_PEER);
        assertEq(decodedMessageId, messageId);
        assertEq(decodedAmount, amount);
        assertEq(decodedToken, token);
        assertEq(decodedSender, sender.toBytes32());
        assertEq(decodedRecipient, recipient);
    }
}
