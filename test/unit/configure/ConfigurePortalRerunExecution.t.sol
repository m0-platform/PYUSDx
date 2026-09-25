// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { TypeConverter } from "../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IBridgeAdapter } from "../../../src/portal/interfaces/IBridgeAdapter.sol";

import { Chains } from "../../../script/config/Chains.sol";
import { LayerZeroConfig } from "../../../script/config/LayerZeroConfig.sol";
import { RouteConfig } from "../../../script/config/RouteConfig.sol";
import { ConfigurationPlan, PlannedAction } from "../../../script/libraries/ConfigurationPlan.sol";
import { Transaction, TransactionHelper } from "../../../script/libraries/TransactionHelper.sol";

import { ConflictingBridgeChainId } from "../../../script/configure/ConfigurePortalBase.sol";
import { ConfigurePortalHarness } from "../../harness/ConfigurePortalHarness.sol";
import { MockConfigurableBridgeAdapter } from "../../mock/MockConfigurableBridgeAdapter.sol";
import { MockConfigurablePortal } from "../../mock/MockConfigurablePortal.sol";

/// @title  ConfigurePortalRerunExecutionTest
/// @notice Execution-based regression for INT-471: the plan is not just inspected, it is executed
///         against stateful adapter and Portal mocks that mirror the real setters, and the resulting
///         state is asserted.
/// @dev    This is what catches an ordering bug that a calldata-only test cannot.
///         `BridgeAdapter.setBridgeChainId` clears a chain's peer whenever it moves that chain's
///         mapping off a non-zero value, so a plan that sends `setPeer` before `setBridgeChainId` —
///         or that skips `setPeer` because the peer already matched — ends the run with a zero peer.
///         Every test here finishes by asserting the final `getPeer`/`getBridgeChainId` and that a
///         second run is empty.
contract ConfigurePortalRerunExecutionTest is Test {
    using ConfigurationPlan for PlannedAction[];
    using TypeConverter for address;

    ConfigurePortalHarness internal harness;
    MockConfigurableBridgeAdapter internal adapter;
    MockConfigurablePortal internal portal;

    address internal arbitrumAdapter = makeAddr("arbitrumAdapter");
    address internal monadAdapter = makeAddr("monadAdapter");

    uint256 internal arbitrumEid = LayerZeroConfig.getLayerZeroEndpointId(Chains.ARBITRUM);
    uint256 internal monadEid = LayerZeroConfig.getLayerZeroEndpointId(Chains.MONAD);

    function setUp() external {
        harness = new ConfigurePortalHarness();
        harness.setPeerAdapter(Chains.ARBITRUM, arbitrumAdapter);
        harness.setPeerAdapter(Chains.MONAD, monadAdapter);

        adapter = new MockConfigurableBridgeAdapter(makeAddr("endpoint"));
        portal = new MockConfigurablePortal();
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

    function _transactions(uint32[] memory peers) internal view returns (Transaction[] memory) {
        return harness.configurePeers(address(portal), address(adapter), peers);
    }

    function _run(uint32[] memory peers) internal returns (uint256 executed) {
        Transaction[] memory transactions = _transactions(peers);
        executed = transactions.length;

        for (uint256 i; i < transactions.length; ++i) {
            TransactionHelper.execute(transactions[i]);
        }
    }

    function _assertArbitrumWired() internal view {
        assertEq(adapter.getPeer(Chains.ARBITRUM), arbitrumAdapter.toBytes32());
        assertEq(adapter.getBridgeChainId(Chains.ARBITRUM), arbitrumEid);
        assertEq(adapter.getChainId(arbitrumEid), Chains.ARBITRUM);
        assertEq(portal.defaultBridgeAdapter(Chains.ARBITRUM), address(adapter));
        assertTrue(portal.supportedBridgeAdapter(Chains.ARBITRUM, address(adapter)));
        assertEq(portal.payloadGasLimit(Chains.ARBITRUM), RouteConfig.getPayloadGasLimit(Chains.ARBITRUM));
    }

    /* ============ first run then rerun ============ */

    function test_execution_wiresRouteThenRerunEmitsNothing() external {
        assertEq(_run(_peers(Chains.ARBITRUM)), 5);

        _assertArbitrumWired();

        assertEq(_transactions(_peers(Chains.ARBITRUM)).length, 0);
    }

    function test_execution_addingASecondPeerLeavesTheFirstIntact() external {
        _run(_peers(Chains.ARBITRUM));

        assertEq(_run(_peers(Chains.ARBITRUM, Chains.MONAD)), 5);

        _assertArbitrumWired();
        assertEq(adapter.getPeer(Chains.MONAD), monadAdapter.toBytes32());
        assertEq(adapter.getBridgeChainId(Chains.MONAD), monadEid);

        assertEq(_transactions(_peers(Chains.ARBITRUM, Chains.MONAD)).length, 0);
    }

    /* ============ changed bridge chain ID ============ */

    function test_execution_changedBridgeChainId_leavesThePeerConfigured() external {
        // The route was configured against a superseded endpoint ID — the situation the Monad EID
        // migration produced — so the peer is already correct but the mapping is not.
        adapter.setBridgeChainId(Chains.ARBITRUM, arbitrumEid + 1);
        adapter.setPeer(Chains.ARBITRUM, arbitrumAdapter.toBytes32());

        Transaction[] memory planned = _transactions(_peers(Chains.ARBITRUM));

        // The mapping is corrected first and the peer is re-asserted behind it.
        assertEq(planned.length, 5);
        assertEq(planned[0].data, abi.encodeCall(IBridgeAdapter.setBridgeChainId, (Chains.ARBITRUM, arbitrumEid)));
        assertEq(
            planned[1].data,
            abi.encodeCall(IBridgeAdapter.setPeer, (Chains.ARBITRUM, arbitrumAdapter.toBytes32()))
        );

        _run(_peers(Chains.ARBITRUM));

        // The peer survived the mapping change, and the superseded mapping is gone.
        _assertArbitrumWired();
        assertEq(adapter.getChainId(arbitrumEid + 1), 0);

        assertEq(_transactions(_peers(Chains.ARBITRUM)).length, 0);
    }

    function test_execution_peerFirstOrderingWouldHaveLostThePeer() external {
        // Pins why the order matters, by executing the same calls the other way round.
        adapter.setBridgeChainId(Chains.ARBITRUM, arbitrumEid + 1);
        adapter.setPeer(Chains.ARBITRUM, arbitrumAdapter.toBytes32());

        adapter.setPeer(Chains.ARBITRUM, arbitrumAdapter.toBytes32());
        adapter.setBridgeChainId(Chains.ARBITRUM, arbitrumEid);

        assertEq(adapter.getPeer(Chains.ARBITRUM), bytes32(0));

        // The planner's ordering recovers from it in a single run.
        _run(_peers(Chains.ARBITRUM));

        _assertArbitrumWired();
        assertEq(_transactions(_peers(Chains.ARBITRUM)).length, 0);
    }

    /* ============ replay override ============ */

    function test_execution_forceReplay_reappliesEverythingAndStaysCorrect() external {
        _run(_peers(Chains.ARBITRUM));

        harness.setForceReplay(true);
        assertEq(_run(_peers(Chains.ARBITRUM)), 5);
        _assertArbitrumWired();

        harness.setForceReplay(false);
        assertEq(_transactions(_peers(Chains.ARBITRUM)).length, 0);
    }

    /* ============ conflicting bridge chain IDs ============ */

    function test_planPeers_bridgeChainIdHeldByAnotherPeerInTheRun_reverts() external {
        // Two peers in one run cannot legitimately share an endpoint ID — `LayerZeroConfig` maps each
        // chain to a distinct one — but if the adapter reports it, wiring Monad would strip Arbitrum's
        // mapping and peer. Require explicit, separate recovery runs rather than reordering automatically.
        adapter.setBridgeChainId(Chains.ARBITRUM, monadEid);

        vm.expectRevert(
            abi.encodeWithSelector(ConflictingBridgeChainId.selector, Chains.MONAD, Chains.ARBITRUM, monadEid)
        );

        harness.planPeers(address(portal), address(adapter), _peers(Chains.MONAD, Chains.ARBITRUM));
    }

    function test_planPeers_bridgeChainIdHeldByAChainOutsideTheRun_isPlanned() external {
        // A retired chain still holding the endpoint ID is the operator's to clean up; refusing here
        // would block a legitimate endpoint-ID migration.
        uint32 retiredChainId = 999;
        adapter.setBridgeChainId(retiredChainId, monadEid);

        PlannedAction[] memory plan = harness.planPeers(address(portal), address(adapter), _peers(Chains.MONAD));
        assertTrue(vm.contains(plan[0].description, "also clears chain 999 mapping and peer"));
        assertEq(_run(_peers(Chains.MONAD)), 5);

        assertEq(adapter.getPeer(Chains.MONAD), monadAdapter.toBytes32());
        assertEq(adapter.getBridgeChainId(Chains.MONAD), monadEid);
        assertEq(adapter.getBridgeChainId(retiredChainId), 0);

        assertEq(_transactions(_peers(Chains.MONAD)).length, 0);
    }
}
