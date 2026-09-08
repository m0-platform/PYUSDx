// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { TypeConverter } from "../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IBridgeAdapter } from "../../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../../src/portal/interfaces/IPortal.sol";

import { Chains } from "../../../script/config/Chains.sol";
import { LayerZeroConfig } from "../../../script/config/LayerZeroConfig.sol";
import { RouteConfig } from "../../../script/config/RouteConfig.sol";
import { ConfigurationPlan, PlannedAction } from "../../../script/libraries/ConfigurationPlan.sol";
import { Transaction } from "../../../script/libraries/TransactionHelper.sol";

import { ConfigurePortalHarness } from "../../harness/ConfigurePortalHarness.sol";
import { SafeProposerHarness } from "../../harness/SafeProposerHarness.sol";

/// @title  ConfigurePortalRerunsTest
/// @notice Covers INT-471 for the Portal builder: a rerun against an already-wired chain emits no
///         transactions, a partially wired chain emits only what is missing, and a changed route
///         emits only the settings that changed.
/// @dev    Current state is served through `vm.mockCall` on the Portal and adapter getters, which is
///         what the builder staticcalls. A getter left unmocked returns empty data from an address
///         with no code, which is exactly how a never-configured chain reads.
contract ConfigurePortalRerunsTest is Test {
    using ConfigurationPlan for PlannedAction[];
    using TypeConverter for address;

    ConfigurePortalHarness internal harness;

    address internal portal = makeAddr("portal");
    address internal localAdapter = makeAddr("localAdapter");
    address internal arbitrumAdapter = makeAddr("arbitrumAdapter");
    address internal monadAdapter = makeAddr("monadAdapter");

    uint256 internal arbitrumEid = LayerZeroConfig.getLayerZeroEndpointId(Chains.ARBITRUM);
    uint256 internal arbitrumGasLimit = RouteConfig.getPayloadGasLimit(Chains.ARBITRUM);

    function setUp() external {
        harness = new ConfigurePortalHarness();
        harness.setPeerAdapter(Chains.ARBITRUM, arbitrumAdapter);
        harness.setPeerAdapter(Chains.MONAD, monadAdapter);
    }

    /* ============ helpers ============ */

    function _peers(uint32 chainId) internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = chainId;
    }

    function _peers(uint32 first, uint32 second) internal pure returns (uint32[] memory peers) {
        peers = new uint32[](2);
        peers[0] = first;
        peers[1] = second;
    }

    /// @dev Makes every Portal and adapter getter report the state a completed run leaves behind.
    function _mockFullyConfigured(uint32 peerChainId, address peerAdapter) internal {
        _mockPeer(peerChainId, peerAdapter.toBytes32());
        _mockBridgeChainId(peerChainId, LayerZeroConfig.getLayerZeroEndpointId(peerChainId));
        _mockSupportedAdapter(peerChainId, true);
        _mockPayloadGasLimit(peerChainId, RouteConfig.getPayloadGasLimit(peerChainId));
        _mockDefaultAdapter(peerChainId, localAdapter);
    }

    function _mockPeer(uint32 peerChainId, bytes32 peer) internal {
        vm.mockCall(localAdapter, abi.encodeCall(IBridgeAdapter.getPeer, (peerChainId)), abi.encode(peer));
    }

    function _mockBridgeChainId(uint32 peerChainId, uint256 bridgeChainId) internal {
        vm.mockCall(
            localAdapter,
            abi.encodeCall(IBridgeAdapter.getBridgeChainId, (peerChainId)),
            abi.encode(bridgeChainId)
        );
    }

    function _mockSupportedAdapter(uint32 peerChainId, bool supported) internal {
        vm.mockCall(
            portal,
            abi.encodeCall(IPortal.supportedBridgeAdapter, (peerChainId, localAdapter)),
            abi.encode(supported)
        );
    }

    function _mockPayloadGasLimit(uint32 peerChainId, uint256 gasLimit) internal {
        vm.mockCall(portal, abi.encodeCall(IPortal.payloadGasLimit, (peerChainId)), abi.encode(gasLimit));
    }

    function _mockDefaultAdapter(uint32 peerChainId, address adapter) internal {
        vm.mockCall(portal, abi.encodeCall(IPortal.defaultBridgeAdapter, (peerChainId)), abi.encode(adapter));
    }

    function _plan(uint32[] memory peers) internal view returns (PlannedAction[] memory) {
        return harness.planPeers(portal, localAdapter, peers);
    }

    function _appliedFlags(PlannedAction[] memory actions) internal pure returns (bool[] memory flags) {
        flags = new bool[](actions.length);
        for (uint256 i; i < actions.length; ++i) {
            flags[i] = actions[i].applied;
        }
    }

    function _assertApplied(PlannedAction[] memory actions, bool[5] memory expected) internal pure {
        assertEq(actions.length, 5);
        for (uint256 i; i < 5; ++i) {
            assertEq(actions[i].applied, expected[i], actions[i].description);
        }
    }

    /* ============ unconfigured chain ============ */

    function test_planPeers_unconfiguredChain_plansEverySetting() external view {
        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [false, false, false, false, false]);
        assertEq(plan.plannedCount(), 5);
        assertEq(plan.skippedCount(), 0);

        // The compacted batch is the same full wiring the builder emitted before INT-471.
        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 5);
        assertEq(txs[0].data, abi.encodeCall(IBridgeAdapter.setBridgeChainId, (Chains.ARBITRUM, arbitrumEid)));
        assertEq(txs[1].data, abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, arbitrumAdapter.toBytes32())));
        assertEq(txs[4].data, abi.encodeCall(IPortal.setDefaultBridgeAdapter, (Chains.ARBITRUM, localAdapter)));
    }

    /* ============ fully configured chain ============ */

    function test_planPeers_fullyConfigured_plansNothing() external {
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [true, true, true, true, true]);
        assertEq(plan.skippedCount(), 5);

        // An unchanged rerun broadcasts nothing and proposes nothing.
        assertEq(harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM)).length, 0);
    }

    function test_planPeers_fullyConfiguredMultiplePeers_plansNothing() external {
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        _mockFullyConfigured(Chains.MONAD, monadAdapter);

        assertEq(harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM, Chains.MONAD)).length, 0);
    }

    /* ============ partially configured chain ============ */

    function test_planPeers_partiallyConfigured_plansOnlyTheMissingSettings() external {
        // The adapter side was wired; the Portal side was never reached.
        _mockPeer(Chains.ARBITRUM, arbitrumAdapter.toBytes32());
        _mockBridgeChainId(Chains.ARBITRUM, arbitrumEid);

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [true, true, false, false, false]);

        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 3);
        assertEq(txs[0].target, portal);
        assertEq(txs[0].data, abi.encodeCall(IPortal.setSupportedBridgeAdapter, (Chains.ARBITRUM, localAdapter, true)));
        assertEq(txs[1].data, abi.encodeCall(IPortal.setPayloadGasLimit, (Chains.ARBITRUM, arbitrumGasLimit)));
        assertEq(txs[2].data, abi.encodeCall(IPortal.setDefaultBridgeAdapter, (Chains.ARBITRUM, localAdapter)));
    }

    function test_planPeers_newPeerAlongsideConfiguredPeer_plansOnlyTheNewPeer() external {
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);

        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM, Chains.MONAD));

        assertEq(txs.length, 5);
        assertEq(
            txs[0].data,
            abi.encodeCall(
                IBridgeAdapter.setBridgeChainId,
                (Chains.MONAD, LayerZeroConfig.getLayerZeroEndpointId(Chains.MONAD))
            )
        );
        assertEq(txs[1].data, abi.encodeCall(IBridgeAdapter.setPeer, (Chains.MONAD, monadAdapter.toBytes32())));
        assertEq(txs[4].data, abi.encodeCall(IPortal.setDefaultBridgeAdapter, (Chains.MONAD, localAdapter)));
    }

    /* ============ changed routes ============ */

    function test_planPeers_peerAdapterRedeployed_plansOnlyThePeerUpdate() external {
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        // The peer chain redeployed its adapter, so the recorded peer no longer matches.
        _mockPeer(Chains.ARBITRUM, makeAddr("oldArbitrumAdapter").toBytes32());

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [true, false, true, true, true]);

        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 1);
        assertEq(txs[0].data, abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, arbitrumAdapter.toBytes32())));
    }

    function test_planPeers_gasLimitRaised_plansOnlyTheGasLimit() external {
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        _mockPayloadGasLimit(Chains.ARBITRUM, arbitrumGasLimit - 1);

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [true, true, true, false, true]);

        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 1);
        assertEq(txs[0].data, abi.encodeCall(IPortal.setPayloadGasLimit, (Chains.ARBITRUM, arbitrumGasLimit)));
    }

    function test_planPeers_bridgeChainIdChanged_alsoReassertsThePeer() external {
        // `setBridgeChainId` clears the peer when it moves the mapping off a non-zero value, so the
        // peer must be re-sent behind it even though it currently matches. Sending the peer first,
        // or skipping it as already applied, would end the run with a zero peer.
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        _mockBridgeChainId(Chains.ARBITRUM, arbitrumEid + 1);

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [false, false, true, true, true]);
        assertTrue(vm.contains(plan[1].description, "re-asserted"));

        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 2);
        assertEq(txs[0].data, abi.encodeCall(IBridgeAdapter.setBridgeChainId, (Chains.ARBITRUM, arbitrumEid)));
        assertEq(txs[1].data, abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, arbitrumAdapter.toBytes32())));
    }

    function test_planPeers_bridgeChainIdFirstAssignment_doesNotReassertThePeer() external {
        // A first assignment (current mapping is zero) removes nothing, so a matching peer stays
        // skipped. Only a mapping moving off a non-zero value takes the peer with it.
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        _mockBridgeChainId(Chains.ARBITRUM, 0);

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [false, true, true, true, true]);
        assertFalse(vm.contains(plan[1].description, "re-asserted"));
    }

    function test_planPeers_bridgeChainIdUnreadable_reassertsThePeer() external {
        // Unknown mapping state must not be assumed harmless: it might be about to clear the peer.
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        vm.mockCallRevert(
            localAdapter,
            abi.encodeCall(IBridgeAdapter.getBridgeChainId, (Chains.ARBITRUM)),
            "unreadable"
        );

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [false, false, true, true, true]);
        assertTrue(vm.contains(plan[0].description, "[current state unreadable]"));
        assertTrue(vm.contains(plan[1].description, "re-asserted"));
    }

    function test_planPeers_localAdapterRotated_plansThePortalSideOnly() external {
        // The Portal still points at the previous local adapter, while the adapter itself is new.
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        _mockSupportedAdapter(Chains.ARBITRUM, false);
        _mockDefaultAdapter(Chains.ARBITRUM, makeAddr("previousLocalAdapter"));

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [true, true, false, true, false]);

        Transaction[] memory txs = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 2);
        assertEq(txs[0].data, abi.encodeCall(IPortal.setSupportedBridgeAdapter, (Chains.ARBITRUM, localAdapter, true)));
        assertEq(txs[1].data, abi.encodeCall(IPortal.setDefaultBridgeAdapter, (Chains.ARBITRUM, localAdapter)));
    }

    /* ============ unreadable state ============ */

    function test_planPeers_getterReverts_keepsTheSettingPlanned() external {
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        vm.mockCallRevert(localAdapter, abi.encodeCall(IBridgeAdapter.getPeer, (Chains.ARBITRUM)), "unreadable");

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        // Unknown state is never treated as applied.
        _assertApplied(plan, [true, false, true, true, true]);
    }

    function test_planPeers_getterReturnsUnexpectedShape_keepsTheSettingPlanned() external {
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        vm.mockCall(portal, abi.encodeCall(IPortal.payloadGasLimit, (Chains.ARBITRUM)), "");

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [true, true, true, false, true]);
    }

    /* ============ replay override ============ */

    function test_forceReplay_defaultsToFalse() external view {
        assertFalse(harness.forceReplay());
    }

    function test_planPeers_forceReplay_plansEverySettingAgain() external {
        _mockFullyConfigured(Chains.ARBITRUM, arbitrumAdapter);
        harness.setForceReplay(true);

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        _assertApplied(plan, [false, false, false, false, false]);
        assertEq(harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM)).length, 5);
    }

    /* ============ plan output ============ */

    function test_planLog_printsPlannedAndSkippedSettings() external {
        // The plan is printed before anything is broadcast or proposed, so the operator sees what a
        // rerun dropped. Console output is not assertable; this pins that logging a mixed plan runs.
        _mockPeer(Chains.ARBITRUM, arbitrumAdapter.toBytes32());
        _mockBridgeChainId(Chains.ARBITRUM, arbitrumEid);

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        plan.log("Portal configuration plan (test):");

        assertEq(plan.plannedCount(), 3);
        assertEq(plan.skippedCount(), 2);
    }

    function test_planDescriptions_markUnreadableState() external {
        vm.mockCallRevert(localAdapter, abi.encodeCall(IBridgeAdapter.getPeer, (Chains.ARBITRUM)), "unreadable");

        PlannedAction[] memory plan = _plan(_peers(Chains.ARBITRUM));

        assertTrue(vm.contains(plan[1].description, "[current state unreadable]"));
        // A readable getter that simply holds nothing yet is not marked unreadable.
        _mockBridgeChainId(Chains.ARBITRUM, 0);
        assertFalse(vm.contains(_plan(_peers(Chains.ARBITRUM))[0].description, "unreadable"));
    }

    /* ============ direct / proposal parity ============ */

    function test_compactedPlan_matchesTheProposedSafeBatch() external {
        // Both `ConfigurePortal` and `ProposeConfigurePortal` submit `_planPeers(...).compact()`;
        // this pins that the compacted batch is what reaches the Safe JSON, transaction for
        // transaction, so a skipped setting cannot reappear on the proposal path.
        _mockPeer(Chains.ARBITRUM, arbitrumAdapter.toBytes32());
        _mockBridgeChainId(Chains.ARBITRUM, arbitrumEid);

        Transaction[] memory direct = harness.configurePeers(portal, localAdapter, _peers(Chains.ARBITRUM));
        Transaction[] memory proposed = _plan(_peers(Chains.ARBITRUM)).compact();

        assertEq(direct.length, proposed.length);

        for (uint256 i; i < direct.length; ++i) {
            assertEq(direct[i].target, proposed[i].target);
            assertEq(direct[i].data, proposed[i].data);
            assertEq(direct[i].value, proposed[i].value);
        }

        SafeProposerHarness proposer = new SafeProposerHarness();
        proposer.writeSafeBatch("configure-portal-rerun-test", proposed);

        string memory path = string.concat(
            vm.projectRoot(),
            "/safe/",
            vm.toString(block.chainid),
            "-configure-portal-rerun-test.json"
        );
        string memory json = vm.readFile(path);
        vm.removeFile(path);

        for (uint256 i; i < proposed.length; ++i) {
            assertTrue(vm.contains(json, vm.toString(proposed[i].data)));
        }

        // The two settings the chain already carries are absent from the proposal.
        assertFalse(
            vm.contains(
                json,
                vm.toString(abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, arbitrumAdapter.toBytes32())))
            )
        );
        assertFalse(
            vm.contains(
                json,
                vm.toString(abi.encodeCall(IBridgeAdapter.setBridgeChainId, (Chains.ARBITRUM, arbitrumEid)))
            )
        );
    }
}
