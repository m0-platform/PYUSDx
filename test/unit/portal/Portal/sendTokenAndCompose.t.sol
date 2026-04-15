// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IBridgeAdapter } from "../../../../src/portal/interfaces/IBridgeAdapter.sol";
import { TokenTransferParams, ComposeMessageParams, IPortal } from "../../../../src/portal/interfaces/IPortal.sol";
import { PayloadEncoder } from "../../../../src/portal/libraries/PayloadEncoder.sol";

import { MockBridgeAdapter } from "../../../mock/MockBridgeAdapter.sol";
import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract SendTokenAndComposeUnitTest is PortalUnitTestBase {
    using TypeConverter for address;

    bytes32 internal refundAddress = makeAddr("refundAddress").toBytes32();
    bytes32 internal recipient = makeAddr("recipient").toBytes32();
    bytes32 internal composer = makeAddr("composer").toBytes32();
    uint256 internal amount = 10e6;
    uint256 internal composedGasLimit = 100_000;
    bytes internal composedMessage = "hello composer";

    function setUp() public override {
        super.setUp();

        vm.startPrank(address(portal));
        pyusdx.mint(user, 100e6);
        pyusdx.mint(address(extension), 100e6);
        vm.stopPrank();

        extension.mint(user, 100e6);
    }

    function _composeParams() internal view returns (ComposeMessageParams memory) {
        return ComposeMessageParams({ composer: composer, message: composedMessage, gasLimit: composedGasLimit });
    }

    function test_sendTokenAndCompose_pyusdx() external {
        uint256 fee = 1;
        bytes32 messageId = _getMessageId();
        ComposeMessageParams memory composeParams = _composeParams();

        bytes memory payload = PayloadEncoder.encodeComposedTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            amount,
            peerPYUSDX,
            user,
            recipient,
            composer,
            composedMessage
        );
        address defaultAdapter = portal.defaultBridgeAdapter(CHAIN_ID_2);

        uint256 initialBalance = pyusdx.balanceOf(user);
        vm.startPrank(user);
        pyusdx.approve(address(portal), amount);

        vm.expectCall(
            defaultAdapter,
            abi.encodeCall(
                IBridgeAdapter.sendMessage,
                (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, composedGasLimit, refundAddress, payload)
            )
        );
        vm.expectEmit();
        emit IPortal.TokenSent(
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            user,
            recipient,
            amount,
            defaultAdapter,
            messageId
        );
        vm.expectEmit();
        emit IPortal.ComposedMessageSent(CHAIN_ID_2, messageId, composer, composedMessage);

        portal.sendTokenAndCompose{ value: fee }(
            TokenTransferParams(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress, address(0)),
            composeParams
        );
        vm.stopPrank();

        assertEq(pyusdx.balanceOf(user), initialBalance - amount);
        assertEq(pyusdx.balanceOf(address(portal)), 0);
    }

    function test_sendTokenAndCompose_extension() external {
        uint256 fee = 1;
        bytes32 messageId = _getMessageId();
        ComposeMessageParams memory composeParams = _composeParams();

        bytes memory payload = PayloadEncoder.encodeComposedTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            amount,
            peerExtension,
            user,
            recipient,
            composer,
            composedMessage
        );
        address defaultAdapter = portal.defaultBridgeAdapter(CHAIN_ID_2);

        uint256 initialBalance = extension.balanceOf(user);
        vm.startPrank(user);
        extension.approve(address(portal), amount);

        vm.expectCall(
            defaultAdapter,
            abi.encodeCall(
                IBridgeAdapter.sendMessage,
                (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, composedGasLimit, refundAddress, payload)
            )
        );
        vm.expectEmit();
        emit IPortal.TokenSent(
            address(extension),
            CHAIN_ID_2,
            peerExtension,
            user,
            recipient,
            amount,
            defaultAdapter,
            messageId
        );
        vm.expectEmit();
        emit IPortal.ComposedMessageSent(CHAIN_ID_2, messageId, composer, composedMessage);

        portal.sendTokenAndCompose{ value: fee }(
            TokenTransferParams(
                amount,
                address(extension),
                CHAIN_ID_2,
                peerExtension,
                recipient,
                refundAddress,
                address(0)
            ),
            composeParams
        );
        vm.stopPrank();

        assertEq(extension.balanceOf(user), initialBalance - amount);
        assertEq(pyusdx.balanceOf(address(portal)), 0);
    }

    function test_sendTokenAndCompose_withSpecificAdapter() external {
        uint256 fee = 1;
        bytes32 messageId = _getMessageId();
        ComposeMessageParams memory composeParams = _composeParams();

        MockBridgeAdapter customAdapter = new MockBridgeAdapter();
        customAdapter.setPortal(address(portal));

        vm.mockCall(
            address(customAdapter),
            abi.encodeCall(MockBridgeAdapter.getPeer, (CHAIN_ID_2)),
            abi.encode(peerBridgeAdapter)
        );

        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, address(customAdapter), true);

        bytes memory payload = PayloadEncoder.encodeComposedTokenTransfer(
            CHAIN_ID_2,
            peerBridgeAdapter,
            messageId,
            amount,
            peerPYUSDX,
            user,
            recipient,
            composer,
            composedMessage
        );

        vm.startPrank(user);
        pyusdx.approve(address(portal), amount);

        vm.expectCall(
            address(customAdapter),
            abi.encodeCall(
                IBridgeAdapter.sendMessage,
                (CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT, composedGasLimit, refundAddress, payload)
            )
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
        vm.expectEmit();
        emit IPortal.ComposedMessageSent(CHAIN_ID_2, messageId, composer, composedMessage);

        portal.sendTokenAndCompose{ value: fee }(
            TokenTransferParams(
                amount,
                address(pyusdx),
                CHAIN_ID_2,
                peerPYUSDX,
                recipient,
                refundAddress,
                address(customAdapter)
            ),
            composeParams
        );
        vm.stopPrank();
    }

    function test_sendTokenAndCompose_revertsIfPaused() external {
        vm.prank(pauser);
        portal.pauseSend();

        vm.expectRevert(IPortal.SendingPaused.selector);
        vm.prank(user);
        portal.sendTokenAndCompose(
            TokenTransferParams(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress, address(0)),
            _composeParams()
        );
    }

    function test_sendTokenAndCompose_revertsIfZeroComposer() external {
        ComposeMessageParams memory composeParams = ComposeMessageParams({
            composer: bytes32(0),
            message: composedMessage,
            gasLimit: composedGasLimit
        });

        vm.startPrank(user);
        pyusdx.approve(address(portal), amount);

        vm.expectRevert(IPortal.ZeroComposer.selector);
        portal.sendTokenAndCompose(
            TokenTransferParams(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress, address(0)),
            composeParams
        );
        vm.stopPrank();
    }

    function test_sendTokenAndCompose_revertsIfZeroComposedGasLimit() external {
        ComposeMessageParams memory composeParams = ComposeMessageParams({
            composer: composer,
            message: composedMessage,
            gasLimit: 0
        });

        vm.startPrank(user);
        pyusdx.approve(address(portal), amount);

        vm.expectRevert(IPortal.ZeroComposedGasLimit.selector);
        portal.sendTokenAndCompose(
            TokenTransferParams(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress, address(0)),
            composeParams
        );
        vm.stopPrank();
    }

    function test_sendTokenAndCompose_revertsIfZeroComposedMessage() external {
        ComposeMessageParams memory composeParams = ComposeMessageParams({
            composer: composer,
            message: "",
            gasLimit: composedGasLimit
        });

        vm.startPrank(user);
        pyusdx.approve(address(portal), amount);

        vm.expectRevert(IPortal.ZeroComposedMessage.selector);
        portal.sendTokenAndCompose(
            TokenTransferParams(amount, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress, address(0)),
            composeParams
        );
        vm.stopPrank();
    }

    function test_sendTokenAndCompose_revertsIfZeroAmount() external {
        vm.expectRevert(IPortal.ZeroAmount.selector);
        vm.prank(user);
        portal.sendTokenAndCompose(
            TokenTransferParams(0, address(pyusdx), CHAIN_ID_2, peerPYUSDX, recipient, refundAddress, address(0)),
            _composeParams()
        );
    }

    function test_sendTokenAndCompose_revertsIfUnsupportedBridgeAdapter() external {
        address unsupportedAdapter = makeAddr("unsupported");

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, CHAIN_ID_2, unsupportedAdapter)
        );
        vm.prank(user);
        portal.sendTokenAndCompose(
            TokenTransferParams(
                amount,
                address(pyusdx),
                CHAIN_ID_2,
                peerPYUSDX,
                recipient,
                refundAddress,
                unsupportedAdapter
            ),
            _composeParams()
        );
    }
}
