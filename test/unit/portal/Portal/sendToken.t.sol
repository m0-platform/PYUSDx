// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IBridgeAdapter } from "../../../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";
import { PayloadEncoder } from "../../../../src/portal/libraries/PayloadEncoder.sol";

import { MockBridgeAdapter } from "../../../mock/MockBridgeAdapter.sol";
import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract SendTokenUnitTest is PortalUnitTestBase {
    using TypeConverter for address;

    bytes32 internal refundAddress = makeAddr("refundAddress").toBytes32();
    bytes internal bridgeAdapterArgs = "";
    bytes32 internal recipient = makeAddr("recipient").toBytes32();
    uint256 internal amount = 10e6;
    uint32 currentChainId;

    function setUp() public override {
        super.setUp();

        // Prank Portal as in MockPYSDDX it's set as an issuer
        vm.startPrank(address(portal));
        // Mint tokens to user for testing
        pyusdx.mint(user, 100e6);
        // Fund extension with M tokens for unwrapping
        pyusdx.mint(address(extension), 100e6);
        vm.stopPrank();

        extension.mint(user, 100e6);

        currentChainId = portal.currentChainId();
    }

    function test_sendToken_pyusdx() external {
        uint256 fee = 1;
        bytes32 messageId = _getMessageId();
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            amount,
            peerPYUSDX,
            user,
            recipient
        );
        address defaultBridgeAdapter = portal.defaultBridgeAdapter(CHAIN_ID_2);

        uint256 initialBalance = extension.balanceOf(user);
        vm.startPrank(user);
        pyusdx.approve(address(portal), amount);

        vm.expectCall(
            defaultBridgeAdapter,
            abi.encodeCall(IBridgeAdapter.sendMessage, (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, refundAddress, payload))
        );
        vm.expectEmit();
        emit IPortal.TokenSent(
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            user,
            recipient,
            amount,
            defaultBridgeAdapter,
            messageId
        );

        portal.sendToken{ value: fee }(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress);
        vm.stopPrank();

        assertEq(pyusdx.balanceOf(user), initialBalance - amount);
        assertEq(pyusdx.balanceOf(address(portal)), 0);
    }

    function test_sendToken_extension() external {
        uint256 fee = 1;
        bytes32 messageId = _getMessageId();
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            amount,
            peerExtension,
            user,
            recipient
        );
        address defaultBridgeAdapter = portal.defaultBridgeAdapter(CHAIN_ID_2);

        uint256 initialBalance = extension.balanceOf(user);
        vm.startPrank(user);
        extension.approve(address(portal), amount);

        vm.expectCall(
            defaultBridgeAdapter,
            abi.encodeCall(IBridgeAdapter.sendMessage, (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, refundAddress, payload))
        );
        vm.expectEmit();
        emit IPortal.TokenSent(
            address(extension),
            CHAIN_ID_2,
            peerExtension,
            user,
            recipient,
            amount,
            defaultBridgeAdapter,
            messageId
        );

        portal.sendToken{ value: fee }(amount, address(extension), CHAIN_ID_2, peerExtension, recipient, refundAddress);
        vm.stopPrank();

        assertEq(extension.balanceOf(user), initialBalance - amount);
        assertEq(pyusdx.balanceOf(address(portal)), 0);
    }

    function test_sendToken_withSpecificAdapter() external {
        uint256 fee = 1;
        bytes32 messageId = _getMessageId();
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            amount,
            peerPYUSDX,
            user,
            recipient
        );

        // Deploy a new mock adapter
        MockBridgeAdapter customAdapter = new MockBridgeAdapter();
        customAdapter.setPortal(address(portal));

        // Mock fetching peer bridge adapter
        vm.mockCall(
            address(customAdapter),
            abi.encodeCall(MockBridgeAdapter.getPeer, (CHAIN_ID_2)),
            abi.encode(peerBridgeAdapter)
        );

        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, address(customAdapter), true);

        vm.startPrank(user);
        pyusdx.approve(address(portal), amount);

        vm.expectCall(
            address(customAdapter),
            abi.encodeCall(IBridgeAdapter.sendMessage, (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, refundAddress, payload))
        );
        vm.expectEmit();
        emit IPortal.TokenSent(
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            user,
            recipient,
            amount,
            address(customAdapter),
            messageId
        );

        portal.sendToken{ value: fee }(
            amount,
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            recipient,
            refundAddress,
            address(customAdapter)
        );
        vm.stopPrank();
    }

    function test_sendToken_revertsIfPaused() external {
        vm.prank(pauser);
        portal.pauseSend();

        vm.expectRevert(IPortal.SendingPaused.selector);
        vm.prank(user);
        portal.sendToken(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress);
    }

    function test_sendToken_revertsIfZeroAmount() external {
        vm.expectRevert(IPortal.ZeroAmount.selector);
        vm.prank(user);
        portal.sendToken(0, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress);
    }

    function test_sendToken_revertsIfZeroRefundAddress() external {
        vm.expectRevert(IPortal.ZeroRefundAddress.selector);
        vm.prank(user);
        portal.sendToken(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, bytes32(0));
    }

    function test_sendToken_revertsIfZeroSourceToken() external {
        vm.expectRevert(IPortal.ZeroSourceToken.selector);
        vm.prank(user);
        portal.sendToken(amount, address(0), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress);
    }

    function test_sendToken_revertsIfZeroDestinationToken() external {
        vm.expectRevert(IPortal.ZeroDestinationToken.selector);
        vm.prank(user);
        portal.sendToken(amount, address(pyusdx), CHAIN_ID_2, bytes32(0), recipient, refundAddress);
    }

    function test_sendToken_revertsIfZeroRecipient() external {
        vm.expectRevert(IPortal.ZeroRecipient.selector);
        vm.prank(user);
        portal.sendToken(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, bytes32(0), refundAddress);
    }

    function test_sendToken_revertsIfNoBridgeAdapterSet() external {
        uint32 unconfiguredChain = 999;

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, unconfiguredChain, address(0))
        );
        vm.prank(user);
        portal.sendToken(amount, address(pyusdx), unconfiguredChain, peerPYUSDX, recipient, refundAddress);
    }

    function test_sendToken_revertsIfUnsupportedBridgeAdapter() external {
        address unsupportedAdapter = makeAddr("unsupported");

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, CHAIN_ID_2, unsupportedAdapter)
        );

        vm.prank(user);
        portal.sendToken(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress, unsupportedAdapter);
    }

    function test_sendToken_revertsIfSendToSelf() external {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, CHAIN_ID_1, address(0)));
        portal.sendToken(amount, address(pyusdx), CHAIN_ID_1, peerPYUSDX, recipient, refundAddress);
        vm.stopPrank();
    }
}
