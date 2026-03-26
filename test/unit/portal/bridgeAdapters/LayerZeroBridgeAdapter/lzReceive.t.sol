// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IBridgeAdapter } from "../../../../../src/portal/interfaces/IBridgeAdapter.sol";
import { ILayerZeroBridgeAdapter } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroBridgeAdapter.sol";
import { IPortal } from "../../../../../src/portal/interfaces/IPortal.sol";
import { Origin } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { TypeConverter } from "common/src/libs/TypeConverter.sol";

import { LayerZeroBridgeAdapterUnitTestBase } from "./LayerZeroBridgeAdapterUnitTestBase.sol";

contract LzReceiveUnitTest is LayerZeroBridgeAdapterUnitTestBase {
    using TypeConverter for *;

    function test_lzReceive_forwardsToPortal() external {
        bytes memory payload = "test payload";
        Origin memory origin = Origin({ srcEid: SPOKE_LAYER_ZERO_EID, sender: peerAdapterAddress, nonce: 1 });

        vm.expectCall(address(portal), abi.encodeCall(IPortal.receiveMessage, (SPOKE_CHAIN_ID, payload)));

        vm.prank(address(lzEndpoint));
        adapter.lzReceive(origin, bytes32(0), payload, address(0), "");
    }

    function test_lzReceive_revertsIfNotCalledByEndpoint() external {
        bytes memory payload = "test payload";
        Origin memory origin = Origin({ srcEid: SPOKE_LAYER_ZERO_EID, sender: peerAdapterAddress, nonce: 1 });

        vm.expectRevert(ILayerZeroBridgeAdapter.NotEndpoint.selector);

        vm.prank(user);
        adapter.lzReceive(origin, bytes32(0), payload, address(0), "");
    }

    function test_lzReceive_revertsIfUnsupportedEndpointId() external {
        uint32 unsupportedEid = 99_999;
        bytes memory payload = "test payload";
        Origin memory origin = Origin({ srcEid: unsupportedEid, sender: peerAdapterAddress, nonce: 1 });

        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.UnsupportedBridgeChain.selector, unsupportedEid));

        vm.prank(address(lzEndpoint));
        adapter.lzReceive(origin, bytes32(0), payload, address(0), "");
    }

    function test_lzReceive_revertsIfPeerNotDefined() external {
        // Set up a chain ID mapping without a peer
        uint32 noPeerChainId = 3;
        uint32 noPeerEid = 30_103;

        vm.prank(operator);
        adapter.setBridgeChainId(noPeerChainId, noPeerEid);

        bytes memory payload = "test payload";
        Origin memory origin = Origin({ srcEid: noPeerEid, sender: peerAdapterAddress, nonce: 1 });

        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.UnsupportedChain.selector, noPeerChainId));

        vm.prank(address(lzEndpoint));
        adapter.lzReceive(origin, bytes32(0), payload, address(0), "");
    }

    function test_lzReceive_revertsIfUnsupportedSender() external {
        bytes32 unsupportedSender = makeAddr("unsupported").toBytes32();
        bytes memory payload = "test payload";
        Origin memory origin = Origin({ srcEid: SPOKE_LAYER_ZERO_EID, sender: unsupportedSender, nonce: 1 });

        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.UnsupportedSender.selector, unsupportedSender));

        vm.prank(address(lzEndpoint));
        adapter.lzReceive(origin, bytes32(0), payload, address(0), "");
    }
}
