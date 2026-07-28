// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TransparentUpgradeableProxy } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { TypeConverter } from "../../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import {
    MessagingFee,
    MessagingReceipt
} from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { LayerZeroBridgeAdapter } from "../../../../../src/portal/bridgeAdapters/layerZero/LayerZeroBridgeAdapter.sol";
import { PortalOFTWrapper } from "../../../../../src/portal/oft/PortalOFTWrapper.sol";
import { OFTReceipt } from "../../../../../src/portal/oft/interfaces/IOFT.sol";

import { MockLayerZeroEndpoint } from "../../../../mock/MockLayerZeroEndpoint.sol";
import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

/// @notice Exercises the wrapper against the real LayerZeroBridgeAdapter (with a mock endpoint),
///         covering the complete EID -> chain ID -> EID round trip that MockBridgeAdapter cannot:
///         the wrapper derives the chain ID from the adapter's reverse mapping, and the adapter
///         resolves its outbound Endpoint ID from the forward mapping of the same
///         `setBridgeChainId` configuration, so the message provably leaves on the quoted EID.
contract SendViaLayerZeroBridgeAdapterUnitTest is PortalOFTWrapperUnitTestBase {
    using TypeConverter for address;

    uint256 internal constant AMOUNT = 10e6;
    uint256 internal constant ENDPOINT_FEE = 0.001 ether;

    MockLayerZeroEndpoint internal endpoint;
    LayerZeroBridgeAdapter internal layerZeroAdapter;
    PortalOFTWrapper internal layerZeroWrapper;

    function setUp() public override {
        super.setUp();

        endpoint = new MockLayerZeroEndpoint();
        endpoint.setFee(ENDPOINT_FEE);

        layerZeroAdapter = LayerZeroBridgeAdapter(
            address(
                new TransparentUpgradeableProxy(
                    address(new LayerZeroBridgeAdapter(address(endpoint), address(portal))),
                    admin,
                    abi.encodeCall(LayerZeroBridgeAdapter.initialize, (admin, operator))
                )
            )
        );

        vm.startPrank(operator);
        // One `setBridgeChainId` call configures both directions of the EID <-> chain ID mapping.
        layerZeroAdapter.setBridgeChainId(CHAIN_ID_2, DESTINATION_EID);
        layerZeroAdapter.setPeer(CHAIN_ID_2, peerBridgeAdapter);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, address(layerZeroAdapter), true);
        vm.stopPrank();

        layerZeroWrapper = _deployWrapperProxy(
            new PortalOFTWrapper(address(portal), address(pyusdx), address(layerZeroAdapter))
        );

        vm.prank(operator);
        layerZeroWrapper.setDestinationToken(DESTINATION_EID, peerPYUSDX);

        // Prank Portal as in MockPYUSDX it's set as an issuer
        vm.prank(address(portal));
        pyusdx.mint(user, 100e6);
    }

    function test_send_roundTripsEidThroughAdapter() external {
        vm.startPrank(user);
        pyusdx.approve(address(layerZeroWrapper), AMOUNT);

        layerZeroWrapper.send{ value: ENDPOINT_FEE }(
            _sendParam(AMOUNT, AMOUNT),
            MessagingFee({ nativeFee: ENDPOINT_FEE, lzTokenFee: 0 }),
            user
        );
        vm.stopPrank();

        // The message left the endpoint on the same Endpoint ID the caller quoted with,
        // addressed to the configured peer, with the full fee forwarded.
        assertEq(endpoint.lastDstEid(), DESTINATION_EID);
        assertEq(endpoint.lastReceiver(), peerBridgeAdapter);
        assertEq(endpoint.lastValue(), ENDPOINT_FEE);
        assertEq(endpoint.sendCount(), 1);
        assertEq(address(endpoint).balance, ENDPOINT_FEE);

        assertEq(pyusdx.balanceOf(user), 100e6 - AMOUNT);
        assertEq(pyusdx.balanceOf(address(layerZeroWrapper)), 0);
    }

    function test_quoteSend_matchesEndpointFee() external view {
        MessagingFee memory fee = layerZeroWrapper.quoteSend(_sendParam(AMOUNT, AMOUNT), false);

        assertEq(fee.nativeFee, ENDPOINT_FEE);
    }

    function test_send_revertsIfUnderpaid() external {
        vm.startPrank(user);
        pyusdx.approve(address(layerZeroWrapper), AMOUNT);

        // The declared fee matches `msg.value`, so the wrapper's own fee check passes and the
        // underpayment is caught by the endpoint itself.
        vm.expectRevert(
            abi.encodeWithSelector(MockLayerZeroEndpoint.InsufficientFee.selector, ENDPOINT_FEE, ENDPOINT_FEE - 1)
        );
        layerZeroWrapper.send{ value: ENDPOINT_FEE - 1 }(
            _sendParam(AMOUNT, AMOUNT),
            MessagingFee({ nativeFee: ENDPOINT_FEE - 1, lzTokenFee: 0 }),
            user
        );
        vm.stopPrank();

        // The whole transaction unwound: no tokens moved.
        assertEq(pyusdx.balanceOf(user), 100e6);
    }

    function test_send_refundsExcessToRefundAddress() external {
        uint256 excess = 0.5 ether;
        address refundRecipient = makeAddr("refundRecipient");

        vm.startPrank(user);
        pyusdx.approve(address(layerZeroWrapper), AMOUNT);

        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) = layerZeroWrapper.send{
            value: ENDPOINT_FEE + excess
        }(_sendParam(AMOUNT, AMOUNT), MessagingFee({ nativeFee: ENDPOINT_FEE, lzTokenFee: 0 }), refundRecipient);
        vm.stopPrank();

        assertEq(refundRecipient.balance, excess);
        assertEq(address(endpoint).balance, ENDPOINT_FEE);

        // The receipt reports what was paid in, not the net fee after refund.
        assertEq(receipt.fee.nativeFee, ENDPOINT_FEE + excess);
        assertEq(oftReceipt.amountSentLD, AMOUNT);
    }
}
