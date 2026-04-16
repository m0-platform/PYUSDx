// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IFreezable } from "../../../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";

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

    function setUp() public override {
        super.setUp();

        // Mark the recipient as not frozen on PYUSDX
        vm.mockCall(address(pyusdx), abi.encodeCall(IFreezable.isFrozen, (recipient)), abi.encode(false));
    }

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

    function test_receiveMessage_tokenTransfer_frozenRecipient_pyusdx() external {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(pyusdx).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        // Mark the recipient as frozen on PYUSDX
        vm.mockCall(address(pyusdx), abi.encodeCall(IFreezable.isFrozen, (recipient)), abi.encode(true));

        vm.expectEmit();
        emit IPortal.RedirectedToFallbackRecipient(
            CHAIN_ID_2,
            address(pyusdx),
            sender.toBytes32(),
            recipient,
            amount,
            messageId,
            fallbackRecipient
        );

        // TokenReceived is emitted with the effective recipient (the fallback)
        vm.expectEmit();
        emit IPortal.TokenReceived(
            CHAIN_ID_2,
            address(pyusdx),
            sender.toBytes32(),
            fallbackRecipient,
            amount,
            messageId
        );

        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, payload);

        // Fallback recipient receives the tokens; frozen recipient does not
        assertEq(pyusdx.balanceOf(fallbackRecipient), amount);
        assertEq(pyusdx.balanceOf(recipient), 0);
    }

    function test_receiveMessage_tokenTransfer_frozenRecipient_extension() external {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(extension).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        // Mark the recipient as frozen on PYUSDX
        vm.mockCall(address(pyusdx), abi.encodeCall(IFreezable.isFrozen, (recipient)), abi.encode(true));

        vm.expectEmit();
        emit IPortal.RedirectedToFallbackRecipient(
            CHAIN_ID_2,
            address(extension),
            sender.toBytes32(),
            recipient,
            amount,
            messageId,
            fallbackRecipient
        );

        // TokenReceived is emitted with the effective recipient (the fallback)
        vm.expectEmit();
        emit IPortal.TokenReceived(
            CHAIN_ID_2,
            address(extension),
            sender.toBytes32(),
            fallbackRecipient,
            amount,
            messageId
        );

        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, payload);

        // Fallback recipient receives the wrapped extension token; frozen recipient does not
        assertEq(extension.balanceOf(fallbackRecipient), amount);
        assertEq(extension.balanceOf(recipient), 0);
        assertEq(pyusdx.balanceOf(recipient), 0);
    }

    function test_receiveMessage_tokenTransfer_frozenRecipient_extension_wrapFailed() external {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(extension).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        // Mark the recipient as frozen on PYUSDX
        vm.mockCall(address(pyusdx), abi.encodeCall(IFreezable.isFrozen, (recipient)), abi.encode(true));

        // Make swapFacility.swapIn revert so _wrap fails for the fallback recipient
        vm.mockCallRevert(address(swapFacility), abi.encodeWithSelector(ISwapFacility.swapIn.selector), "swap failed");

        vm.expectEmit();
        emit IPortal.RedirectedToFallbackRecipient(
            CHAIN_ID_2,
            address(extension),
            sender.toBytes32(),
            recipient,
            amount,
            messageId,
            fallbackRecipient
        );

        vm.expectEmit();
        emit IPortal.TokenReceived(
            CHAIN_ID_2,
            address(extension),
            sender.toBytes32(),
            fallbackRecipient,
            amount,
            messageId
        );

        vm.expectEmit();
        emit IPortal.WrapFailed(address(extension), fallbackRecipient, amount);

        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, payload);

        // Fallback recipient receives PYUSDX directly since wrap failed
        assertEq(pyusdx.balanceOf(fallbackRecipient), amount);
        assertEq(extension.balanceOf(fallbackRecipient), 0);
        assertEq(pyusdx.balanceOf(recipient), 0);
        assertEq(extension.balanceOf(recipient), 0);
    }

    function test_receiveMessage_tokenTransfer_frozenRecipient_revertsIfFallbackFrozen() external {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(pyusdx).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        // Both the intended recipient and the fallback are frozen
        vm.mockCall(address(pyusdx), abi.encodeCall(IFreezable.isFrozen, (recipient)), abi.encode(true));
        vm.mockCall(address(pyusdx), abi.encodeCall(IFreezable.isFrozen, (fallbackRecipient)), abi.encode(true));

        // MockERC20.mint does not enforce freeze, so simulate the real PYUSDX behavior by making
        // the mint call to the frozen fallback revert.
        vm.mockCallRevert(
            address(pyusdx),
            abi.encodeWithSignature("mint(address,uint256)", fallbackRecipient, amount),
            "FrozenAccount"
        );

        vm.prank(address(bridgeAdapter));
        vm.expectRevert();
        portal.receiveMessage(CHAIN_ID_2, payload);

        // The whole tx reverted — message should not be marked processed, so it can be retried
        // once the fallback is replaced or unfrozen.
        bytes memory retryPayload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(pyusdx).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        // Replace the fallback with an unfrozen address and retry
        address newFallback = makeAddr("newFallback");
        vm.mockCall(address(pyusdx), abi.encodeCall(IFreezable.isFrozen, (newFallback)), abi.encode(false));

        vm.prank(admin);
        portal.setFallbackRecipient(newFallback);

        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, retryPayload);

        assertEq(pyusdx.balanceOf(newFallback), amount);
    }

    function test_receiveMessage_tokenTransfer_frozenRecipient_cannotBeReplayed() external {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            address(bridgeAdapter).toBytes32(),
            messageId,
            amount,
            address(pyusdx).toBytes32(),
            sender,
            recipient.toBytes32()
        );

        vm.mockCall(address(pyusdx), abi.encodeCall(IFreezable.isFrozen, (recipient)), abi.encode(true));

        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, payload);

        assertEq(pyusdx.balanceOf(fallbackRecipient), amount);

        // Replaying the same message must revert even though it was redirected to the fallback
        vm.expectRevert(abi.encodeWithSelector(IPortal.MessageAlreadyProcessed.selector, messageId));
        vm.prank(address(bridgeAdapter));
        portal.receiveMessage(CHAIN_ID_2, payload);
    }
}
