// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";
import { IERC20Errors } from "../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

import { IBridgeAdapter } from "../../../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";
import { PayloadEncoder } from "../../../../src/portal/libraries/PayloadEncoder.sol";

import { MockBridgeAdapter } from "../../../mock/MockBridgeAdapter.sol";
import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract SendTokenWithPermitUnitTest is PortalUnitTestBase {
    using TypeConverter for address;

    bytes32 internal refundAddress = makeAddr("refundAddress").toBytes32();
    bytes32 internal recipient = makeAddr("recipient").toBytes32();
    uint256 internal amount = 10e6;
    uint256 internal deadline;
    bytes internal signature = "signature";

    function setUp() public override {
        super.setUp();

        // Mint tokens to user for testing
        pyusdx.mint(user, 100e6);
        // Fund extension with PYUSDX for unwrapping
        pyusdx.mint(address(extension), 100e6);

        extension.mint(user, 100e6);

        deadline = block.timestamp + 1 hours;
    }

    function test_sendTokenWithPermit_pyusdx() external {
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

        uint256 initialBalance = pyusdx.balanceOf(user);

        // NOTE: No prior approval — the allowance is granted via permit.
        vm.expectCall(
            address(pyusdx),
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,bytes)",
                user,
                address(portal),
                amount,
                deadline,
                signature
            )
        );
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

        vm.prank(user);
        portal.sendTokenWithPermit{ value: fee }(
            amount,
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            recipient,
            refundAddress,
            deadline,
            signature
        );

        assertEq(pyusdx.balanceOf(user), initialBalance - amount);
        assertEq(pyusdx.balanceOf(address(portal)), 0);
    }

    function test_sendTokenWithPermit_extension() external {
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

        vm.expectCall(
            address(extension),
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,bytes)",
                user,
                address(portal),
                amount,
                deadline,
                signature
            )
        );
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

        vm.prank(user);
        portal.sendTokenWithPermit{ value: fee }(
            amount,
            address(extension),
            CHAIN_ID_2,
            peerExtension,
            recipient,
            refundAddress,
            deadline,
            signature
        );

        assertEq(extension.balanceOf(user), initialBalance - amount);
        assertEq(pyusdx.balanceOf(address(portal)), 0);
    }

    function test_sendTokenWithPermit_withSpecificAdapter() external {
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

        vm.expectCall(
            address(pyusdx),
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,bytes)",
                user,
                address(portal),
                amount,
                deadline,
                signature
            )
        );
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

        vm.prank(user);
        portal.sendTokenWithPermit{ value: fee }(
            amount,
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            recipient,
            refundAddress,
            address(customAdapter),
            deadline,
            signature
        );
    }

    function test_sendTokenWithPermit_expiredPermitFallsBackToAllowance() external {
        uint256 fee = 1;
        uint256 expiredDeadline = block.timestamp - 1;

        uint256 initialBalance = pyusdx.balanceOf(user);

        // The failed permit is swallowed, so the transfer succeeds via the existing allowance.
        vm.startPrank(user);
        pyusdx.approve(address(portal), amount);

        portal.sendTokenWithPermit{ value: fee }(
            amount,
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            recipient,
            refundAddress,
            expiredDeadline,
            signature
        );
        vm.stopPrank();

        assertEq(pyusdx.balanceOf(user), initialBalance - amount);
    }

    function test_sendTokenWithPermit_revertsIfPermitFailsWithoutAllowance() external {
        uint256 expiredDeadline = block.timestamp - 1;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(portal), 0, amount)
        );
        vm.prank(user);
        portal.sendTokenWithPermit(
            amount,
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            recipient,
            refundAddress,
            expiredDeadline,
            signature
        );
    }

    function test_sendTokenWithPermit_revertsIfPaused() external {
        vm.prank(pauser);
        portal.pauseSend();

        vm.expectRevert(IPortal.SendingPaused.selector);
        vm.prank(user);
        portal.sendTokenWithPermit(
            amount,
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            recipient,
            refundAddress,
            deadline,
            signature
        );
    }

    function test_sendTokenWithPermit_revertsIfUnsupportedBridgeAdapter() external {
        address unsupportedAdapter = makeAddr("unsupported");

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, CHAIN_ID_2, unsupportedAdapter)
        );
        vm.prank(user);
        portal.sendTokenWithPermit(
            amount,
            address(pyusdx),
            CHAIN_ID_2,
            peerPYUSDX,
            recipient,
            refundAddress,
            unsupportedAdapter,
            deadline,
            signature
        );
    }
}
