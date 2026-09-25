// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { TypeConverter } from "../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IBridgeAdapter } from "../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../src/portal/interfaces/IPortal.sol";

import { Chains } from "../../script/config/Chains.sol";
import { LayerZeroConfig } from "../../script/config/LayerZeroConfig.sol";
import { ConfigurationPlan, PlannedAction } from "../../script/libraries/ConfigurationPlan.sol";
import { Transaction, TransactionHelper } from "../../script/libraries/TransactionHelper.sol";

import { ConfigureLayerZeroHarness } from "../harness/ConfigureLayerZeroHarness.sol";
import { ConfigurePortalHarness } from "../harness/ConfigurePortalHarness.sol";
import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @title  ConfigureRerunsIntegrationTests
/// @notice Proves INT-471 against real contracts on a mainnet fork: once the Portal, the
///         LayerZeroBridgeAdapter and the live LayerZero ULN302 libraries carry the intended
///         configuration, rerunning either builder produces an empty batch, and a route that changed
///         produces only the settings that changed.
/// @dev    The LayerZero case is the one that cannot be proven with mocks: it exercises the real
///         ULN302 `getAppUlnConfig` read the builder relies on to tell a route it pinned from a
///         route that merely inherits matching library defaults. Requires `MAINNET_RPC_URL`
///         (`make integration`).
contract ConfigureRerunsIntegrationTests is IntegrationForkTest {
    using ConfigurationPlan for PlannedAction[];
    using TypeConverter for address;

    ConfigurePortalHarness internal portalConfigurer;
    ConfigureLayerZeroHarness internal layerZeroConfigurer;

    address internal arbitrumPeerAdapter = makeAddr("arbitrumPeerAdapter");

    function setUp() public override {
        super.setUp();

        portalConfigurer = new ConfigurePortalHarness();
        portalConfigurer.setPeerAdapter(Chains.ARBITRUM, arbitrumPeerAdapter);

        layerZeroConfigurer = new ConfigureLayerZeroHarness();
    }

    function _arbitrumPeer() internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = Chains.ARBITRUM;
    }

    function _executeAsOperator(Transaction[] memory transactions) internal {
        for (uint256 i; i < transactions.length; ++i) {
            vm.prank(operator);
            TransactionHelper.execute(transactions[i]);
        }
    }

    function _portalTransactions() internal view returns (Transaction[] memory) {
        return portalConfigurer.configurePeers(address(portal), address(layerZeroBridgeAdapter), _arbitrumPeer());
    }

    function _layerZeroTransactions() internal view returns (Transaction[] memory) {
        return layerZeroConfigurer.buildTransactions(Chains.ETHEREUM, address(layerZeroBridgeAdapter), _arbitrumPeer());
    }

    /* ============ Portal ============ */

    function test_configurePortal_rerunAfterWiring_emitsNothing() public {
        Transaction[] memory first = _portalTransactions();
        assertEq(first.length, 5);

        _executeAsOperator(first);

        assertEq(_portalTransactions().length, 0);
    }

    function test_configurePortal_rerunAfterPeerRedeployment_emitsOnlyThePeerUpdate() public {
        _executeAsOperator(_portalTransactions());

        // The peer chain redeployed its adapter; only the peer pointer is stale.
        address redeployedPeerAdapter = makeAddr("redeployedArbitrumPeerAdapter");
        portalConfigurer.setPeerAdapter(Chains.ARBITRUM, redeployedPeerAdapter);

        Transaction[] memory rerun = _portalTransactions();

        assertEq(rerun.length, 1);
        assertEq(rerun[0].target, address(layerZeroBridgeAdapter));
        assertEq(
            rerun[0].data,
            abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, redeployedPeerAdapter.toBytes32()))
        );

        _executeAsOperator(rerun);

        assertEq(layerZeroBridgeAdapter.getPeer(Chains.ARBITRUM), redeployedPeerAdapter.toBytes32());
        assertEq(_portalTransactions().length, 0);
    }

    function test_configurePortal_rerunAfterGasLimitDrift_emitsOnlyTheGasLimit() public {
        _executeAsOperator(_portalTransactions());

        vm.prank(operator);
        portal.setPayloadGasLimit(Chains.ARBITRUM, 123_456);

        Transaction[] memory rerun = _portalTransactions();

        assertEq(rerun.length, 1);
        assertEq(rerun[0].target, address(portal));
        assertEq(
            rerun[0].data,
            abi.encodeCall(
                IPortal.setPayloadGasLimit,
                (Chains.ARBITRUM, portalConfigurer.getPayloadGasLimit(Chains.ARBITRUM))
            )
        );
    }

    function test_configurePortal_changedBridgeChainId_leavesThePeerConfigured() public {
        // The real adapter clears a chain's peer when its bridge chain ID moves off a non-zero
        // value. Wire the route against a superseded endpoint ID first, so the rerun has to correct
        // the mapping while keeping the peer — the ordering INT-471's planner depends on.
        uint256 supersededEid = LayerZeroConfig.getLayerZeroEndpointId(Chains.ARBITRUM) + 1;

        vm.prank(operator);
        layerZeroBridgeAdapter.setBridgeChainId(Chains.ARBITRUM, supersededEid);

        vm.prank(operator);
        layerZeroBridgeAdapter.setPeer(Chains.ARBITRUM, arbitrumPeerAdapter.toBytes32());

        Transaction[] memory planned = _portalTransactions();

        assertEq(
            planned[0].data,
            abi.encodeCall(
                IBridgeAdapter.setBridgeChainId,
                (Chains.ARBITRUM, uint256(LayerZeroConfig.getLayerZeroEndpointId(Chains.ARBITRUM)))
            )
        );
        assertEq(
            planned[1].data,
            abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, arbitrumPeerAdapter.toBytes32()))
        );

        _executeAsOperator(planned);

        // The peer survived the mapping change.
        assertEq(layerZeroBridgeAdapter.getPeer(Chains.ARBITRUM), arbitrumPeerAdapter.toBytes32());
        assertEq(
            layerZeroBridgeAdapter.getBridgeChainId(Chains.ARBITRUM),
            LayerZeroConfig.getLayerZeroEndpointId(Chains.ARBITRUM)
        );
        assertEq(layerZeroBridgeAdapter.getChainId(supersededEid), 0);

        assertEq(_portalTransactions().length, 0);
    }

    function test_configurePortal_forceReplay_reemitsEverySetting() public {
        _executeAsOperator(_portalTransactions());
        portalConfigurer.setForceReplay(true);

        assertEq(_portalTransactions().length, 5);
    }

    /* ============ LayerZero ============ */

    function test_configureLayerZero_rerunAfterConfig_emitsNothing() public {
        Transaction[] memory first = _layerZeroTransactions();
        assertEq(first.length, 2);

        _executeAsOperator(first);

        // Reads the adapter's own stored config back off the live ULN302 send and receive libraries.
        assertEq(_layerZeroTransactions().length, 0);
    }

    function test_configureLayerZero_planLabelsBothRoutesApplied() public {
        _executeAsOperator(_layerZeroTransactions());

        PlannedAction[] memory plan = layerZeroConfigurer.planPeers(
            Chains.ETHEREUM,
            address(layerZeroBridgeAdapter),
            _arbitrumPeer()
        );

        assertEq(plan.length, 2);
        assertEq(plan.skippedCount(), 2);
        // A readable state never carries the unreadable marker.
        assertFalse(vm.contains(plan[0].description, "unreadable"));
        assertFalse(vm.contains(plan[1].description, "unreadable"));
    }

    function test_configureLayerZero_forceReplay_reemitsBothSides() public {
        _executeAsOperator(_layerZeroTransactions());
        layerZeroConfigurer.setForceReplay(true);

        assertEq(_layerZeroTransactions().length, 2);
    }
}
