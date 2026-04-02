// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IBridgeAdapter } from "../../../../../src/portal/interfaces/IBridgeAdapter.sol";
import { ILayerZeroEndpointV2 } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { TypeConverter } from "../../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { LayerZeroBridgeAdapterUnitTestBase } from "./LayerZeroBridgeAdapterUnitTestBase.sol";

contract SendMessageUnitTest is LayerZeroBridgeAdapterUnitTestBase {
    using TypeConverter for *;

    function test_sendMessage_sendsToEndpoint() external {
        uint256 gasLimit = 250_000;
        bytes32 refundAddress = makeAddr("refund").toBytes32();
        bytes memory payload = "test payload";
        uint256 fee = 0.001 ether;

        // Expect the endpoint send to be called with the fee
        vm.expectCall(address(lzEndpoint), fee, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector));

        vm.prank(address(portal));
        adapter.sendMessage{ value: fee }(SPOKE_CHAIN_ID, gasLimit, refundAddress, payload);
    }

    function test_sendMessage_revertsIfNotCalledByPortal() external {
        uint256 gasLimit = 250_000;
        bytes32 refundAddress = makeAddr("refund").toBytes32();
        bytes memory payload = "test payload";

        vm.expectRevert(IBridgeAdapter.NotPortal.selector);

        vm.prank(user);
        adapter.sendMessage{ value: 0.001 ether }(SPOKE_CHAIN_ID, gasLimit, refundAddress, payload);
    }

    function test_sendMessage_revertsIfChainNotConfigured() external {
        uint32 unconfiguredChain = 999;
        uint256 gasLimit = 250_000;
        bytes32 refundAddress = makeAddr("refund").toBytes32();
        bytes memory payload = "test payload";

        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.UnsupportedChain.selector, unconfiguredChain));

        vm.prank(address(portal));
        adapter.sendMessage{ value: 0.001 ether }(unconfiguredChain, gasLimit, refundAddress, payload);
    }

    function test_sendMessage_revertsIfBridgeChainIdNotSet() external {
        uint32 newChainId = 3;
        bytes32 newPeer = makeAddr("newPeer").toBytes32();

        // Set peer but not bridge chain ID
        vm.prank(operator);
        adapter.setPeer(newChainId, newPeer);

        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.UnsupportedChain.selector, newChainId));

        vm.prank(address(portal));
        adapter.sendMessage{ value: 0.001 ether }(newChainId, 250_000, makeAddr("refund").toBytes32(), "test");
    }

    function test_sendMessage_revertsIfPeerNotSet() external {
        uint32 newChainId = 3;

        // Set bridge chain ID but not peer
        vm.prank(operator);
        adapter.setBridgeChainId(newChainId, 30_103);

        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.UnsupportedChain.selector, newChainId));

        vm.prank(address(portal));
        adapter.sendMessage{ value: 0.001 ether }(newChainId, 250_000, makeAddr("refund").toBytes32(), "test");
    }
}
