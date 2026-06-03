// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { TypeConverter } from "../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { Chains } from "../../script/config/Chains.sol";
import { LayerZeroConfig } from "../../script/config/LayerZeroConfig.sol";
import { RouteConfig } from "../../script/config/RouteConfig.sol";
import { Transaction, TransactionHelper } from "../../script/libraries/TransactionHelper.sol";

import { ConfigurePortalHarness } from "../harness/ConfigurePortalHarness.sol";
import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @title  ConfigurePortalIntegrationTests
/// @notice Validates that the ConfigurePortal builder's transactions, when executed by the operator,
///         wire the deployed Portal + LayerZeroBridgeAdapter for a peer chain.
contract ConfigurePortalIntegrationTests is IntegrationForkTest {
    using TypeConverter for address;

    ConfigurePortalHarness internal configurer;
    address internal arbitrumPeerAdapter = makeAddr("arbitrumPeerAdapter");

    function setUp() public override {
        super.setUp();
        configurer = new ConfigurePortalHarness();
        configurer.setPeerAdapter(Chains.ARBITRUM, arbitrumPeerAdapter);
    }

    function _wireArbitrum() internal {
        Transaction[] memory transactions = configurer.configurePeers(
            address(portal),
            address(layerZeroBridgeAdapter),
            _arbitrumPeer()
        );

        for (uint256 i; i < transactions.length; ++i) {
            vm.prank(operator);
            TransactionHelper.execute(transactions[i]);
        }
    }

    function _arbitrumPeer() internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = Chains.ARBITRUM;
    }

    function test_configurePortal_wiresPeerRoute() public {
        _wireArbitrum();

        assertEq(layerZeroBridgeAdapter.getPeer(Chains.ARBITRUM), arbitrumPeerAdapter.toBytes32());
        assertEq(
            layerZeroBridgeAdapter.getBridgeChainId(Chains.ARBITRUM),
            LayerZeroConfig.getLayerZeroEndpointId(Chains.ARBITRUM)
        );
        assertEq(portal.defaultBridgeAdapter(Chains.ARBITRUM), address(layerZeroBridgeAdapter));
        assertTrue(portal.supportedBridgeAdapter(Chains.ARBITRUM, address(layerZeroBridgeAdapter)));
        assertEq(portal.payloadGasLimit(Chains.ARBITRUM), RouteConfig.getPayloadGasLimit(Chains.ARBITRUM));
    }

    function test_configurePortal_isIdempotent() public {
        _wireArbitrum();
        // Re-running the same wiring must not revert and must leave identical state.
        _wireArbitrum();

        assertEq(layerZeroBridgeAdapter.getPeer(Chains.ARBITRUM), arbitrumPeerAdapter.toBytes32());
        assertEq(portal.defaultBridgeAdapter(Chains.ARBITRUM), address(layerZeroBridgeAdapter));
        assertTrue(portal.supportedBridgeAdapter(Chains.ARBITRUM, address(layerZeroBridgeAdapter)));
    }
}
