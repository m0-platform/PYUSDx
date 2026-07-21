// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import {
    MessagingFee,
    MessagingReceipt
} from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { IBridgeAdapter } from "../../../../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../../../../src/portal/interfaces/IPortal.sol";
import { PayloadEncoder } from "../../../../../src/portal/libraries/PayloadEncoder.sol";
import { IOFT, SendParam, OFTReceipt } from "../../../../../src/portal/oft/interfaces/IOFT.sol";
import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";

import { MockBridgeAdapter } from "../../../../mock/MockBridgeAdapter.sol";
import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

contract SendUnitTest is PortalOFTWrapperUnitTestBase {
    using TypeConverter for address;

    uint256 internal constant AMOUNT = 10e6;

    function setUp() public override {
        super.setUp();

        // Prank Portal as in MockPYUSDX it's set as an issuer
        vm.startPrank(address(portal));
        // Mint tokens to user for testing
        pyusdx.mint(user, 100e6);
        // Fund extension with PYUSDX tokens for unwrapping
        pyusdx.mint(address(extension), 100e6);
        vm.stopPrank();

        extension.mint(user, 100e6);
    }

    function test_send() external {
        bytes32 messageId = _getMessageId();
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            AMOUNT,
            peerPYUSDX,
            address(wrapper),
            recipient
        );

        uint256 initialBalance = pyusdx.balanceOf(user);
        uint256 initialSupply = pyusdx.totalSupply();

        vm.startPrank(user);
        pyusdx.approve(address(wrapper), AMOUNT);

        vm.expectCall(
            address(bridgeAdapter),
            abi.encodeCall(
                IBridgeAdapter.sendMessage,
                (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, user.toBytes32(), payload)
            )
        );
        vm.expectEmit();
        emit IPortal.TokenSent(
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            address(wrapper),
            recipient,
            AMOUNT,
            address(bridgeAdapter),
            messageId
        );
        vm.expectEmit();
        emit IOFT.OFTSent(messageId, DESTINATION_EID, user, AMOUNT, AMOUNT);

        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) = wrapper.send{ value: FEE }(
            _sendParam(AMOUNT, AMOUNT),
            MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }),
            user
        );
        vm.stopPrank();

        // The Portal message ID is reported as the OFT guid; the nonce is not populated.
        assertEq(receipt.guid, messageId);
        assertEq(receipt.nonce, 0);
        assertEq(receipt.fee.nativeFee, FEE);
        assertEq(receipt.fee.lzTokenFee, 0);
        assertEq(oftReceipt.amountSentLD, AMOUNT);
        assertEq(oftReceipt.amountReceivedLD, AMOUNT);

        // Tokens were pulled from the user and burned by the Portal
        assertEq(pyusdx.balanceOf(user), initialBalance - AMOUNT);
        assertEq(pyusdx.balanceOf(address(wrapper)), 0);
        assertEq(pyusdx.balanceOf(address(portal)), 0);
        assertEq(pyusdx.totalSupply(), initialSupply - AMOUNT);

        // The fee was forwarded to the bridge adapter
        assertEq(address(bridgeAdapter).balance, FEE);
    }

    function test_send_extension() external {
        bytes32 messageId = _getMessageId();
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            AMOUNT,
            peerExtension,
            address(extensionWrapper),
            recipient
        );

        uint256 initialBalance = extension.balanceOf(user);

        vm.startPrank(user);
        extension.approve(address(extensionWrapper), AMOUNT);

        vm.expectCall(
            address(bridgeAdapter),
            abi.encodeCall(
                IBridgeAdapter.sendMessage,
                (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, user.toBytes32(), payload)
            )
        );
        vm.expectEmit();
        emit IPortal.TokenSent(
            address(extension),
            CHAIN_ID_2,
            peerExtension,
            address(extensionWrapper),
            recipient,
            AMOUNT,
            address(bridgeAdapter),
            messageId
        );
        vm.expectEmit();
        emit IOFT.OFTSent(messageId, DESTINATION_EID, user, AMOUNT, AMOUNT);

        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) = extensionWrapper.send{ value: FEE }(
            _sendParam(AMOUNT, AMOUNT),
            MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }),
            user
        );
        vm.stopPrank();

        assertEq(receipt.guid, messageId);
        assertEq(oftReceipt.amountSentLD, AMOUNT);
        assertEq(oftReceipt.amountReceivedLD, AMOUNT);

        // The extension was pulled from the user and unwrapped, and the PYUSDX was burned
        assertEq(extension.balanceOf(user), initialBalance - AMOUNT);
        assertEq(extension.balanceOf(address(extensionWrapper)), 0);
        assertEq(extension.balanceOf(address(portal)), 0);
        assertEq(pyusdx.balanceOf(address(portal)), 0);
    }

    function test_send_usesPinnedBridgeAdapter() external {
        // Even if the Portal's default adapter changes, the wrapper still routes through the
        // pinned LayerZero bridge adapter so that delivery stays over LayerZero.
        MockBridgeAdapter otherAdapter = new MockBridgeAdapter();
        otherAdapter.setPortal(address(portal));

        vm.prank(operator);
        portal.setDefaultBridgeAdapter(CHAIN_ID_2, address(otherAdapter));

        bytes32 messageId = _getMessageId();
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            AMOUNT,
            peerPYUSDX,
            address(wrapper),
            recipient
        );

        vm.startPrank(user);
        pyusdx.approve(address(wrapper), AMOUNT);

        vm.expectCall(
            address(bridgeAdapter),
            abi.encodeCall(
                IBridgeAdapter.sendMessage,
                (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, user.toBytes32(), payload)
            )
        );
        wrapper.send{ value: FEE }(_sendParam(AMOUNT, AMOUNT), MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
        vm.stopPrank();

        assertEq(address(bridgeAdapter).balance, FEE);
        assertEq(address(otherAdapter).balance, 0);
    }

    function test_send_revertsIfPinnedBridgeAdapterUnsupported() external {
        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, address(bridgeAdapter), false);

        vm.prank(user);
        pyusdx.approve(address(wrapper), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, CHAIN_ID_2, address(bridgeAdapter))
        );
        vm.prank(user);
        wrapper.send{ value: FEE }(_sendParam(AMOUNT, AMOUNT), MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
    }

    function test_send_ignoresWrapperBalance() external {
        // The full send amount is always pulled from the caller: tokens already held by the
        // wrapper are never credited toward a send.
        uint256 stranded = AMOUNT / 4;

        vm.startPrank(user);
        pyusdx.transfer(address(wrapper), stranded);
        pyusdx.approve(address(wrapper), AMOUNT);

        wrapper.send{ value: FEE }(_sendParam(AMOUNT, AMOUNT), MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
        vm.stopPrank();

        assertEq(pyusdx.balanceOf(address(wrapper)), stranded);
        assertEq(pyusdx.allowance(user, address(wrapper)), 0);
    }

    function test_send_revertsIfPreFundedWithoutAllowance() external {
        // Pre-pushing tokens into the wrapper does not fund a send: the amount is pulled from
        // the caller, so a caller without an allowance reverts even when the wrapper holds the
        // full send amount.
        vm.prank(user);
        pyusdx.transfer(address(wrapper), AMOUNT);

        vm.expectRevert();
        vm.prank(user);
        wrapper.send{ value: FEE }(_sendParam(AMOUNT, AMOUNT), MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
    }

    function test_send_revertsIfAmountExceedsUint128() external {
        vm.expectRevert(TypeConverter.Uint128Overflow.selector);
        vm.prank(user);
        wrapper.send{ value: FEE }(
            _sendParam(uint256(type(uint128).max) + 1, 0),
            MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }),
            user
        );
    }

    function test_send_revertsIfSlippageExceeded() external {
        vm.expectRevert(abi.encodeWithSelector(IOFT.SlippageExceeded.selector, AMOUNT, AMOUNT + 1));
        vm.prank(user);
        wrapper.send{ value: FEE }(
            _sendParam(AMOUNT, AMOUNT + 1),
            MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }),
            user
        );
    }

    function test_send_revertsIfLzTokenFee() external {
        vm.expectRevert(IPortalOFTWrapper.LayerZeroTokenUnsupported.selector);
        vm.prank(user);
        wrapper.send{ value: FEE }(_sendParam(AMOUNT, AMOUNT), MessagingFee({ nativeFee: FEE, lzTokenFee: 1 }), user);
    }

    function test_send_revertsIfUnsupportedEid() external {
        SendParam memory sendParam = _sendParam(AMOUNT, AMOUNT);
        sendParam.dstEid = 1;

        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, 1));
        vm.prank(user);
        wrapper.send{ value: FEE }(sendParam, MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
    }

    function test_send_revertsIfEidUnknownToBridgeAdapter() external {
        // A destination token is configured, but the bridge adapter has no chain ID mapping
        // for the Endpoint ID, so the chain ID derivation fails.
        uint32 unknownEid = 30101;

        vm.prank(operator);
        wrapper.setDestinationToken(unknownEid, peerPYUSDX);

        SendParam memory sendParam = _sendParam(AMOUNT, AMOUNT);
        sendParam.dstEid = unknownEid;

        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, unknownEid));
        vm.prank(user);
        wrapper.send{ value: FEE }(sendParam, MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
    }

    function test_send_revertsIfNoAllowance() external {
        vm.expectRevert();
        vm.prank(user);
        wrapper.send{ value: FEE }(_sendParam(AMOUNT, AMOUNT), MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
    }

    function test_send_revertsIfZeroAmount() external {
        vm.expectRevert(IPortal.ZeroAmount.selector);
        vm.prank(user);
        wrapper.send{ value: FEE }(_sendParam(0, 0), MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
    }

    function test_send_revertsIfZeroRefundAddress() external {
        vm.prank(user);
        pyusdx.approve(address(wrapper), AMOUNT);

        vm.expectRevert(IPortal.ZeroRefundAddress.selector);
        vm.prank(user);
        wrapper.send{ value: FEE }(
            _sendParam(AMOUNT, AMOUNT),
            MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }),
            address(0)
        );
    }

    function test_send_revertsIfSendingPaused() external {
        vm.prank(user);
        pyusdx.approve(address(wrapper), AMOUNT);

        vm.prank(pauser);
        portal.pauseSend();

        vm.expectRevert(IPortal.SendingPaused.selector);
        vm.prank(user);
        wrapper.send{ value: FEE }(_sendParam(AMOUNT, AMOUNT), MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), user);
    }
}
