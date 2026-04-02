// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";
import { ISwapFacility } from "../../../../src/swap/interfaces/ISwapFacility.sol";
import { TypeConverter } from "../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";
import { PayloadEncoder } from "../../../../src/portal/libraries/PayloadEncoder.sol";

import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract ReceiveMessageUnitTest is PortalUnitTestBase {
    using TypeConverter for *;

    address internal sender = makeAddr("sender");
    address internal recipient = makeAddr("recipient");
    uint256 internal amount = 10e6;
    bytes32 internal messageId = bytes32(uint256(1));

    function test_receiveMessage_tokenTransfer_pyusdx() external {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(pyusdx).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        vm.expectEmit();
        emit IPortal.TokenReceived(CHAIN_ID_2, address(pyusdx), sender.toBytes32(), recipient, amount, messageId);

        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, payload);

        assertEq(pyusdx.balanceOf(recipient), amount);
    }

    function test_receiveMessage_tokenTransfer_extension() external {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(extension).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        vm.expectEmit();
        emit IPortal.TokenReceived(CHAIN_ID_2, address(extension), sender.toBytes32(), recipient, amount, messageId);

        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, payload);

        assertEq(extension.balanceOf(recipient), amount);
    }

    function test_receiveMessage_tokenTransfer_wrapFailed() external {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(extension).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        // Make swapFacility.swapIn revert so _wrap fails
        vm.mockCallRevert(address(swapFacility), abi.encodeWithSelector(ISwapFacility.swapIn.selector), "swap failed");

        vm.expectEmit();
        emit IPortal.TokenReceived(CHAIN_ID_2, address(extension), sender.toBytes32(), recipient, amount, messageId);

        vm.expectEmit();
        emit IPortal.WrapFailed(address(extension), recipient, amount);

        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, payload);

        // PYUSDX should be transferred directly to recipient instead of wrapping
        assertEq(pyusdx.balanceOf(recipient), amount);
        // Extension balance should remain zero
        assertEq(extension.balanceOf(recipient), 0);
    }
}
