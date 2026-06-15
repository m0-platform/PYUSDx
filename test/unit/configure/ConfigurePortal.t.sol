// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { TypeConverter } from "../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IBridgeAdapter } from "../../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../../src/portal/interfaces/IPortal.sol";

import { Chains } from "../../../script/config/Chains.sol";
import { LayerZeroBridgeAdapterNotDeployed, LayerZeroConfig } from "../../../script/config/LayerZeroConfig.sol";
import { RouteConfig } from "../../../script/config/RouteConfig.sol";
import { Transaction } from "../../../script/libraries/TransactionHelper.sol";

import { PeerAdapterNotDeployed, PortalNotDeployed } from "../../../script/configure/ConfigurePortalBase.sol";
import { ConfigurePortalHarness } from "../../harness/ConfigurePortalHarness.sol";

contract ConfigurePortalTest is Test {
    using TypeConverter for address;

    ConfigurePortalHarness internal harness;

    address internal portal = makeAddr("portal");
    address internal localAdapter = makeAddr("localAdapter");
    address internal arbitrumAdapter = makeAddr("arbitrumAdapter");

    function setUp() external {
        harness = new ConfigurePortalHarness();
    }

    function _peers(uint32 chainId) internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = chainId;
    }

    /* ============ _configurePeers ============ */

    function test_configurePeers_buildsAdapterAndPortalCalls() external {
        harness.setPeerAdapter(Chains.ARBITRUM, arbitrumAdapter);

        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 5);

        // adapter.setPeer(ARBITRUM, arbitrumAdapter)
        assertEq(txs[0].target, localAdapter);
        assertEq(txs[0].data, abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, arbitrumAdapter.toBytes32())));

        // adapter.setBridgeChainId(ARBITRUM, 30110)
        assertEq(txs[1].target, localAdapter);
        assertEq(txs[1].data, abi.encodeCall(IBridgeAdapter.setBridgeChainId, (Chains.ARBITRUM, uint256(30110))));

        // portal.setSupportedBridgeAdapter(ARBITRUM, localAdapter, true)
        assertEq(txs[2].target, portal);
        assertEq(txs[2].data, abi.encodeCall(IPortal.setSupportedBridgeAdapter, (Chains.ARBITRUM, localAdapter, true)));

        // portal.setPayloadGasLimit(ARBITRUM, gasLimit)
        assertEq(txs[3].target, portal);
        assertEq(
            txs[3].data,
            abi.encodeCall(
                IPortal.setPayloadGasLimit,
                (Chains.ARBITRUM, RouteConfig.getPayloadGasLimit(Chains.ARBITRUM))
            )
        );

        // portal.setDefaultBridgeAdapter(ARBITRUM, localAdapter)
        assertEq(txs[4].target, portal);
        assertEq(txs[4].data, abi.encodeCall(IPortal.setDefaultBridgeAdapter, (Chains.ARBITRUM, localAdapter)));
    }

    function test_configurePeers_peerAdapterNotDeployed() external {
        // No adapter registered for the peer -> reverts instead of silently skipping.
        vm.expectRevert(abi.encodeWithSelector(PeerAdapterNotDeployed.selector, Chains.ARBITRUM));

        harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));
    }

    function test_configurePeers_portalNotDeployed() external {
        harness.setPeerAdapter(Chains.ARBITRUM, arbitrumAdapter);

        vm.expectRevert(abi.encodeWithSelector(PortalNotDeployed.selector, uint32(block.chainid)));

        harness.configurePeers(address(0), localAdapter, _peers(Chains.ARBITRUM));
    }

    function test_configurePeers_localAdapterNotDeployed() external {
        harness.setPeerAdapter(Chains.ARBITRUM, arbitrumAdapter);

        vm.expectRevert(abi.encodeWithSelector(LayerZeroBridgeAdapterNotDeployed.selector, uint32(block.chainid)));

        harness.configurePeers(portal, address(0), _peers(Chains.ARBITRUM));
    }

    function test_configurePeers_buildsForMultiplePeers() external {
        address ethereumAdapter = makeAddr("ethereumAdapter");
        harness.setPeerAdapter(Chains.ARBITRUM, arbitrumAdapter);
        harness.setPeerAdapter(Chains.ETHEREUM, ethereumAdapter);

        uint32[] memory peers = new uint32[](2);
        peers[0] = Chains.ARBITRUM;
        peers[1] = Chains.ETHEREUM;

        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, peers);

        assertEq(txs.length, 10);
        assertEq(txs[0].data, abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, arbitrumAdapter.toBytes32())));
        assertEq(txs[5].data, abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ETHEREUM, ethereumAdapter.toBytes32())));
    }

    /* ============ getLayerZeroEndpointId ============ */

    function test_getLayerZeroEndpointId() external view {
        assertEq(harness.getLayerZeroEndpointId(Chains.ETHEREUM), 30101);
        assertEq(harness.getLayerZeroEndpointId(Chains.ARBITRUM), 30110);
        assertEq(harness.getLayerZeroEndpointId(Chains.SEPOLIA), 40161);
        assertEq(harness.getLayerZeroEndpointId(Chains.ARBITRUM_SEPOLIA), 40231);
    }

    function test_getLayerZeroEndpointId_unsupportedChain() external {
        vm.expectRevert(abi.encodeWithSelector(Chains.UnsupportedChain.selector, uint32(999)));

        harness.getLayerZeroEndpointId(999);
    }

    /* ============ getPayloadGasLimit ============ */

    function test_getPayloadGasLimit() external view {
        assertEq(harness.getPayloadGasLimit(Chains.ETHEREUM), 500_000);
        assertEq(harness.getPayloadGasLimit(Chains.ARBITRUM), 500_000);
        assertEq(harness.getPayloadGasLimit(Chains.SEPOLIA), 500_000);
        assertEq(harness.getPayloadGasLimit(Chains.ARBITRUM_SEPOLIA), 500_000);
    }

    function test_getPayloadGasLimit_unsupportedChain() external {
        vm.expectRevert(abi.encodeWithSelector(Chains.UnsupportedChain.selector, uint32(999)));

        harness.getPayloadGasLimit(999);
    }
}
