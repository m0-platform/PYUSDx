// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Origin } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { TypeConverter } from "common/src/libs/TypeConverter.sol";

import { LayerZeroBridgeAdapterUnitTestBase } from "./LayerZeroBridgeAdapterUnitTestBase.sol";

contract AllowInitializePathUnitTest is LayerZeroBridgeAdapterUnitTestBase {
    using TypeConverter for *;

    function test_allowInitializePath_returnsTrueForConfiguredPeer() external view {
        Origin memory origin = Origin({ srcEid: SPOKE_LAYER_ZERO_EID, sender: peerAdapterAddress, nonce: 0 });

        assertTrue(adapter.allowInitializePath(origin));
    }

    function test_allowInitializePath_returnsFalseForUnknownEndpointId() external view {
        uint32 unknownEid = 99_999;
        Origin memory origin = Origin({ srcEid: unknownEid, sender: peerAdapterAddress, nonce: 0 });

        assertFalse(adapter.allowInitializePath(origin));
    }

    function test_allowInitializePath_returnsFalseForChainWithNoPeer() external {
        // Map a new chain ID to an endpoint ID but don't set a peer.
        uint32 noPeerChainId = 3;
        uint32 noPeerEid = 30_103;

        vm.prank(operator);
        adapter.setBridgeChainId(noPeerChainId, noPeerEid);

        Origin memory origin = Origin({ srcEid: noPeerEid, sender: peerAdapterAddress, nonce: 0 });

        assertFalse(adapter.allowInitializePath(origin));
    }

    function test_allowInitializePath_returnsFalseForWrongSender() external {
        bytes32 wrongSender = makeAddr("wrongSender").toBytes32();
        Origin memory origin = Origin({ srcEid: SPOKE_LAYER_ZERO_EID, sender: wrongSender, nonce: 0 });

        assertFalse(adapter.allowInitializePath(origin));
    }
}
