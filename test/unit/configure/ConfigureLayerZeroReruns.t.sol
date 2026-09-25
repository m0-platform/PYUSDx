// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { ILayerZeroBridgeAdapter } from "../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroBridgeAdapter.sol";

import { ILayerZeroEndpointV2Like, SetConfigParam } from "../../../script/interfaces/ILayerZeroEndpointV2Like.sol";
import { IUln302Like } from "../../../script/interfaces/IUln302Like.sol";
import { Chains } from "../../../script/config/Chains.sol";
import { CONFIG_TYPE_ULN, LayerZeroConfig, UlnConfig } from "../../../script/config/LayerZeroConfig.sol";
import { ConfigurationPlan, PlannedAction } from "../../../script/libraries/ConfigurationPlan.sol";
import { Transaction } from "../../../script/libraries/TransactionHelper.sol";

import { ConfigureLayerZeroHarness } from "../../harness/ConfigureLayerZeroHarness.sol";
import { SafeProposerHarness } from "../../harness/SafeProposerHarness.sol";

/// @title  ConfigureLayerZeroRerunsTest
/// @notice Covers INT-471 for the LayerZero ULN builder: a rerun against an adapter that already
///         pins the intended ULN config emits no `setConfig`, a half-configured route emits only the
///         missing side, and a changed security stack emits only what changed.
/// @dev    The comparison reads the adapter's own stored config off the message library
///         (`getAppUlnConfig`), not the endpoint's merged view. The default-inheritance tests below
///         pin why: PYUSDX deliberately pins LayerZero's own default stack on several routes, so a
///         merged read cannot tell a pinned route from an unpinned one that inherits the same values.
contract ConfigureLayerZeroRerunsTest is Test {
    using ConfigurationPlan for PlannedAction[];

    uint32 internal constant _ARBITRUM_EID = 30110;
    uint32 internal constant _MONAD_EID = 30390;

    ConfigureLayerZeroHarness internal harness;

    address internal adapter = makeAddr("adapter");
    address internal endpoint = makeAddr("endpoint");
    address internal sendLib = makeAddr("sendLib");
    address internal receiveLib = makeAddr("receiveLib");
    address internal monadSendLib = makeAddr("monadSendLib");
    address internal monadReceiveLib = makeAddr("monadReceiveLib");

    function setUp() external {
        harness = new ConfigureLayerZeroHarness();

        vm.mockCall(adapter, abi.encodeCall(ILayerZeroBridgeAdapter.endpoint, ()), abi.encode(endpoint));
        _mockLibraries(_ARBITRUM_EID, sendLib, receiveLib);
        _mockLibraries(_MONAD_EID, monadSendLib, monadReceiveLib);
    }

    /* ============ helpers ============ */

    function _mockLibraries(uint32 eid, address sendLibrary, address receiveLibrary) internal {
        vm.mockCall(
            endpoint,
            abi.encodeCall(ILayerZeroEndpointV2Like.getSendLibrary, (adapter, eid)),
            abi.encode(sendLibrary)
        );
        vm.mockCall(
            endpoint,
            abi.encodeCall(ILayerZeroEndpointV2Like.getReceiveLibrary, (adapter, eid)),
            abi.encode(receiveLibrary, false)
        );
    }

    function _peers(uint32 chainId) internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = chainId;
    }

    function _peers(uint32 first, uint32 second) internal pure returns (uint32[] memory peers) {
        peers = new uint32[](2);
        peers[0] = first;
        peers[1] = second;
    }

    /// @dev Makes a message library report `config` as the adapter's own stored config for `eid`.
    function _mockAppUlnConfig(address lib, uint32 eid, UlnConfig memory config) internal {
        vm.mockCall(lib, abi.encodeCall(IUln302Like.getAppUlnConfig, (adapter, eid)), abi.encode(config));
    }

    /// @dev Pins both sides of the Ethereum -> Arbitrum route exactly as a completed run leaves them.
    function _mockArbitrumRoutePinned() internal {
        _mockAppUlnConfig(sendLib, _ARBITRUM_EID, harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM));
        _mockAppUlnConfig(receiveLib, _ARBITRUM_EID, harness.receiveUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM));
    }

    function _plan() internal view returns (PlannedAction[] memory) {
        return harness.planPeers(Chains.ETHEREUM, adapter, _peers(Chains.ARBITRUM));
    }

    function _assertApplied(PlannedAction[] memory actions, bool sendApplied, bool receiveApplied) internal pure {
        assertEq(actions.length, 2);
        assertEq(actions[0].applied, sendApplied, actions[0].description);
        assertEq(actions[1].applied, receiveApplied, actions[1].description);
    }

    function _setConfigCall(address lib, uint32 eid, UlnConfig memory config) internal view returns (bytes memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({ eid: eid, configType: CONFIG_TYPE_ULN, config: abi.encode(config) });

        return abi.encodeCall(ILayerZeroEndpointV2Like.setConfig, (adapter, lib, params));
    }

    /* ============ unconfigured route ============ */

    function test_planPeers_libraryWithoutAppConfigGetter_plansBothSides() external view {
        // Nothing mocked on the libraries: the read fails, the state is unknown, both sides stay planned.
        PlannedAction[] memory plan = _plan();

        _assertApplied(plan, false, false);
        assertEq(harness.buildTransactions(Chains.ETHEREUM, adapter, _peers(Chains.ARBITRUM)).length, 2);
    }

    function test_planPeers_neverConfiguredRoute_plansBothSides() external {
        // ULN302 returns a zero-valued config for an OApp that has never called setConfig.
        UlnConfig memory unset;
        _mockAppUlnConfig(sendLib, _ARBITRUM_EID, unset);
        _mockAppUlnConfig(receiveLib, _ARBITRUM_EID, unset);

        _assertApplied(_plan(), false, false);
    }

    /* ============ fully configured route ============ */

    function test_planPeers_pinnedRoute_plansNothing() external {
        _mockArbitrumRoutePinned();

        PlannedAction[] memory plan = _plan();

        _assertApplied(plan, true, true);
        assertEq(plan.skippedCount(), 2);

        // An unchanged rerun broadcasts nothing and proposes nothing.
        assertEq(harness.buildTransactions(Chains.ETHEREUM, adapter, _peers(Chains.ARBITRUM)).length, 0);
    }

    /* ============ inheritance / default semantics ============ */

    function test_planPeers_configInheritedFromLibraryDefaults_stillPlansTheRoute() external {
        // What a merged/effective read reports for a route that pins nothing but inherits the
        // library defaults: identical DVNs and confirmations, but the "no optional DVNs" marker is
        // reported as 0 rather than the NIL_DVN_COUNT the intended config carries. PYUSDX pins
        // LayerZero's own default stack on this route, so every other field matches — only the
        // explicit-vs-inherited distinction separates the two.
        UlnConfig memory intended = harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM);
        UlnConfig memory inherited = UlnConfig({
            confirmations: intended.confirmations,
            requiredDVNCount: intended.requiredDVNCount,
            optionalDVNCount: 0,
            optionalDVNThreshold: intended.optionalDVNThreshold,
            requiredDVNs: intended.requiredDVNs,
            optionalDVNs: intended.optionalDVNs
        });

        assertEq(intended.optionalDVNCount, 255); // NIL_DVN_COUNT: "no optional DVNs", set explicitly

        _mockAppUlnConfig(sendLib, _ARBITRUM_EID, inherited);
        _mockAppUlnConfig(receiveLib, _ARBITRUM_EID, harness.receiveUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM));

        // The send side is not pinned, so it is planned even though the effective DVN stack matches.
        _assertApplied(_plan(), false, true);
    }

    function test_planPeers_requiredDvnCountInheritedAsZero_stillPlansTheRoute() external {
        UlnConfig memory intended = harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM);
        UlnConfig memory inherited = UlnConfig({
            confirmations: intended.confirmations,
            requiredDVNCount: 0,
            optionalDVNCount: intended.optionalDVNCount,
            optionalDVNThreshold: intended.optionalDVNThreshold,
            requiredDVNs: intended.requiredDVNs,
            optionalDVNs: intended.optionalDVNs
        });

        _mockAppUlnConfig(sendLib, _ARBITRUM_EID, inherited);

        _assertApplied(_plan(), false, false);
    }

    /* ============ changed route ============ */

    function test_planPeers_confirmationsChanged_plansOnlyThatSide() external {
        _mockArbitrumRoutePinned();

        UlnConfig memory stale = harness.receiveUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM);
        stale.confirmations -= 1;
        _mockAppUlnConfig(receiveLib, _ARBITRUM_EID, stale);

        PlannedAction[] memory plan = _plan();

        _assertApplied(plan, true, false);

        Transaction[] memory txs = harness.buildTransactions(Chains.ETHEREUM, adapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 1);
        assertEq(txs[0].target, endpoint);
        assertEq(
            txs[0].data,
            _setConfigCall(receiveLib, _ARBITRUM_EID, harness.receiveUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM))
        );
    }

    function test_planPeers_dvnSetChanged_plansOnlyThatSide() external {
        _mockArbitrumRoutePinned();

        // A DVN was rotated out of the required set on the send side.
        UlnConfig memory stale = harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM);
        stale.requiredDVNs[1] = makeAddr("retiredDVN");
        _mockAppUlnConfig(sendLib, _ARBITRUM_EID, stale);

        _assertApplied(_plan(), false, true);

        Transaction[] memory txs = harness.buildTransactions(Chains.ETHEREUM, adapter, _peers(Chains.ARBITRUM));

        assertEq(txs.length, 1);
        assertEq(
            txs[0].data,
            _setConfigCall(sendLib, _ARBITRUM_EID, harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM))
        );
    }

    function test_planPeers_dvnCountChanged_plansOnlyThatSide() external {
        _mockArbitrumRoutePinned();

        // A route that was pinned to a single required DVN before the second one was added.
        UlnConfig memory intended = harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM);
        address[] memory single = new address[](1);
        single[0] = intended.requiredDVNs[0];

        _mockAppUlnConfig(
            sendLib,
            _ARBITRUM_EID,
            UlnConfig({
                confirmations: intended.confirmations,
                requiredDVNCount: 1,
                optionalDVNCount: intended.optionalDVNCount,
                optionalDVNThreshold: intended.optionalDVNThreshold,
                requiredDVNs: single,
                optionalDVNs: intended.optionalDVNs
            })
        );

        _assertApplied(_plan(), false, true);
    }

    /* ============ partially configured peer set ============ */

    function test_planPeers_newPeerAlongsidePinnedPeer_plansOnlyTheNewPeer() external {
        _mockArbitrumRoutePinned();

        PlannedAction[] memory plan = harness.planPeers(
            Chains.ETHEREUM,
            adapter,
            _peers(Chains.ARBITRUM, Chains.MONAD)
        );

        assertEq(plan.length, 4);
        assertTrue(plan[0].applied);
        assertTrue(plan[1].applied);
        assertFalse(plan[2].applied);
        assertFalse(plan[3].applied);

        Transaction[] memory txs = harness.buildTransactions(
            Chains.ETHEREUM,
            adapter,
            _peers(Chains.ARBITRUM, Chains.MONAD)
        );

        assertEq(txs.length, 2);
        assertEq(
            txs[0].data,
            _setConfigCall(monadSendLib, _MONAD_EID, harness.sendUlnConfig(Chains.ETHEREUM, Chains.MONAD))
        );
        assertEq(
            txs[1].data,
            _setConfigCall(monadReceiveLib, _MONAD_EID, harness.receiveUlnConfig(Chains.ETHEREUM, Chains.MONAD))
        );
    }

    /* ============ unreadable state ============ */

    function test_planPeers_appConfigGetterReverts_keepsTheRoutePlanned() external {
        _mockArbitrumRoutePinned();
        vm.mockCallRevert(sendLib, abi.encodeCall(IUln302Like.getAppUlnConfig, (adapter, _ARBITRUM_EID)), "no getter");

        _assertApplied(_plan(), false, true);
    }

    function test_planPeers_appConfigGetterReturnsUnexpectedShape_keepsTheRoutePlanned() external {
        _mockArbitrumRoutePinned();
        vm.mockCall(
            sendLib,
            abi.encodeCall(IUln302Like.getAppUlnConfig, (adapter, _ARBITRUM_EID)),
            abi.encode(uint256(1))
        );

        _assertApplied(_plan(), false, true);
    }

    /* ============ replay override ============ */

    function test_forceReplay_defaultsToFalse() external view {
        assertFalse(harness.forceReplay());
    }

    function test_planPeers_forceReplay_plansBothSidesAgain() external {
        _mockArbitrumRoutePinned();
        harness.setForceReplay(true);

        _assertApplied(_plan(), false, false);
        assertEq(harness.buildTransactions(Chains.ETHEREUM, adapter, _peers(Chains.ARBITRUM)).length, 2);
    }

    /* ============ direct / proposal parity ============ */

    function test_compactedPlan_matchesTheProposedSafeBatch() external {
        // `ConfigureLayerZero` and `ProposeConfigureLayerZero` both submit `_planPeers(...).compact()`.
        _mockAppUlnConfig(sendLib, _ARBITRUM_EID, harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM));

        Transaction[] memory direct = harness.buildTransactions(Chains.ETHEREUM, adapter, _peers(Chains.ARBITRUM));
        Transaction[] memory proposed = _plan().compact();

        assertEq(direct.length, 1);
        assertEq(direct.length, proposed.length);
        assertEq(direct[0].target, proposed[0].target);
        assertEq(direct[0].data, proposed[0].data);

        SafeProposerHarness proposer = new SafeProposerHarness();
        proposer.writeSafeBatch("configure-lz-rerun-test", proposed);

        string memory path = string.concat(
            vm.projectRoot(),
            "/safe/",
            vm.toString(block.chainid),
            "-configure-lz-rerun-test.json"
        );
        string memory json = vm.readFile(path);
        vm.removeFile(path);

        assertTrue(vm.contains(json, vm.toString(proposed[0].data)));
        // The already-pinned send side never reaches the proposal.
        assertFalse(
            vm.contains(
                json,
                vm.toString(
                    _setConfigCall(sendLib, _ARBITRUM_EID, harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM))
                )
            )
        );
    }
}
