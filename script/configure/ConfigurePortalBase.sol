// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { TypeConverter } from "../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IBridgeAdapter } from "../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../src/portal/interfaces/IPortal.sol";

import { LayerZeroBridgeAdapterNotDeployed, LayerZeroConfig } from "../config/LayerZeroConfig.sol";
import { RouteConfig } from "../config/RouteConfig.sol";
import { ConfigurationPlan, PlannedAction } from "../libraries/ConfigurationPlan.sol";
import { StateReader } from "../libraries/StateReader.sol";
import { Transaction } from "../libraries/TransactionHelper.sol";
import { ScriptBase } from "../ScriptBase.s.sol";

/// @notice Thrown when the Portal on the active chain carries a zero address in its deployment record.
error PortalNotDeployed(uint32 chainId);

/// @notice Thrown when a peer chain's bridge adapter is missing from its deployment record.
error PeerAdapterNotDeployed(uint32 peerChainId);

/// @notice Thrown when wiring one peer's bridge chain ID would strip another peer in the same run.
/// @dev    `setBridgeChainId` keeps a 1-1 mapping: claiming a bridge chain ID that another internal
///         chain already holds deletes that chain's mapping and clears its peer. `LayerZeroConfig`
///         maps every supported chain to a distinct endpoint ID, so two peers in one run cannot
///         legitimately target the same one. Conflicting current mappings require explicit recovery:
///         configure the displaced holder first in a separate run, then the claiming peer.
error ConflictingBridgeChainId(uint32 peerChainId, uint32 conflictingChainId, uint256 bridgeChainId);

/// @title  ConfigurePortalBase
/// @notice Builds the Portal + LayerZeroBridgeAdapter wiring transactions for a list of peer chains,
///         skipping the settings the chain already carries.
/// @dev    Shared by the broadcast script (`ConfigurePortal`) and the Safe propose script
///         (`ProposeConfigurePortal`). `_planPeers` inspects the live Portal and adapter and returns
///         every intended setting tagged as applied or planned; `_configurePeers` compacts that plan
///         to the transactions that still need to be sent. Both are `view` and return plain data, so
///         the exact calls can be unit-tested without broadcasting, and a rerun that changes nothing
///         produces an empty batch.
abstract contract ConfigurePortalBase is ScriptBase {
    using ConfigurationPlan for PlannedAction[];
    using StateReader for address;
    using TypeConverter for address;

    /// @dev Number of settings inspected, and at most emitted, per configured peer.
    uint256 internal constant _TXS_PER_PEER = 5;

    /// @notice Builds the wiring transactions still needed to enable bridging to each peer chain.
    /// @param  portal       The local Portal address.
    /// @param  localAdapter The local LayerZeroBridgeAdapter address.
    /// @param  peerChainIds The remote chain IDs to wire as peers.
    /// @return transactions The ordered Portal/adapter configuration calls, minus the applied ones.
    function _configurePeers(
        address portal,
        address localAdapter,
        uint32[] memory peerChainIds
    ) internal view returns (Transaction[] memory transactions) {
        return _planPeers(portal, localAdapter, peerChainIds).compact();
    }

    /// @notice Builds the full intended wiring for each peer chain, tagging each setting with whether
    ///         the live Portal and adapter already carry it.
    /// @dev    A setting is only tagged applied when its current value was read back successfully and
    ///         matches. Settings whose current value cannot be read are left planned.
    /// @param  portal       The local Portal address.
    /// @param  localAdapter The local LayerZeroBridgeAdapter address.
    /// @param  peerChainIds The remote chain IDs to wire as peers.
    /// @return actions      Every intended setting, in transaction order, tagged applied or planned.
    function _planPeers(
        address portal,
        address localAdapter,
        uint32[] memory peerChainIds
    ) internal view returns (PlannedAction[] memory actions) {
        if (portal == address(0)) revert PortalNotDeployed(uint32(block.chainid));
        if (localAdapter == address(0)) revert LayerZeroBridgeAdapterNotDeployed(uint32(block.chainid));

        uint256 peersCount = peerChainIds.length;

        actions = new PlannedAction[](peersCount * _TXS_PER_PEER);
        uint256 count;

        for (uint256 i; i < peersCount; ++i) {
            PlannedAction[] memory peerActions = _peerActions(portal, localAdapter, peerChainIds[i], peerChainIds);

            for (uint256 j; j < peerActions.length; ++j) {
                actions[count++] = peerActions[j];
            }
        }
    }

    /// @dev Builds every setting for one peer, in the order they must be sent. Split out of
    ///      `_planPeers`, one setting per helper, to keep each stack frame shallow.
    ///
    ///      `setBridgeChainId` comes first and `setPeer` second, and the order is load-bearing:
    ///      reassigning a chain's bridge chain ID clears that chain's peer as a side effect (see
    ///      `BridgeAdapter.setBridgeChainId`). Sending `setPeer` first would leave the adapter with
    ///      no peer whenever the mapping also changed, and a rerun that skipped `setPeer` because
    ///      the peer already matched would wipe it and not put it back. `_setPeerAction` is
    ///      therefore forced back into the batch whenever the mapping change ahead of it will clear
    ///      the peer.
    function _peerActions(
        address portal,
        address localAdapter,
        uint32 peerChainId,
        uint32[] memory peerChainIds
    ) private view returns (PlannedAction[] memory peerActions) {
        address peerAdapter = _getPeerAdapter(peerChainId);
        if (peerAdapter == address(0)) revert PeerAdapterNotDeployed(peerChainId);

        (PlannedAction memory bridgeChainIdAction, bool clearsPeer) = _setBridgeChainIdAction(
            localAdapter,
            peerChainId,
            peerChainIds
        );

        peerActions = new PlannedAction[](_TXS_PER_PEER);

        peerActions[0] = bridgeChainIdAction;
        peerActions[1] = _setPeerAction(localAdapter, peerChainId, peerAdapter, clearsPeer);
        peerActions[2] = _setSupportedBridgeAdapterAction(portal, localAdapter, peerChainId);
        peerActions[3] = _setPayloadGasLimitAction(portal, peerChainId);
        peerActions[4] = _setDefaultBridgeAdapterAction(portal, localAdapter, peerChainId);
    }

    /// @param forced True when the `setBridgeChainId` call ahead of this one will clear the peer, so
    ///               the peer must be re-asserted even though it currently matches.
    function _setPeerAction(
        address localAdapter,
        uint32 peerChainId,
        address peerAdapter,
        bool forced
    ) private view returns (PlannedAction memory) {
        bytes32 peer = peerAdapter.toBytes32();

        (bool applied, bool readable) = _settingState(
            localAdapter,
            abi.encodeCall(IBridgeAdapter.getPeer, (peerChainId)),
            peer
        );

        string memory description = string.concat(
            "adapter.setPeer(",
            _label(peerChainId),
            vm.toString(peerAdapter),
            ")"
        );

        if (forced) {
            applied = false;
            description = string.concat(description, " [re-asserted: the bridge chain ID change clears it]");
        }

        return
            _action(
                localAdapter,
                abi.encodeCall(IBridgeAdapter.setPeer, (peerChainId, peer)),
                description,
                applied,
                readable
            );
    }

    /// @return action     The `setBridgeChainId` setting for this peer.
    /// @return clearsPeer Whether executing it will clear this chain's peer. True when the mapping
    ///                    is changing away from a non-zero value, and when the current mapping could
    ///                    not be read at all, because unknown state must not be assumed harmless.
    function _setBridgeChainIdAction(
        address localAdapter,
        uint32 peerChainId,
        uint32[] memory peerChainIds
    ) private view returns (PlannedAction memory action, bool clearsPeer) {
        uint256 endpointId = LayerZeroConfig.getLayerZeroEndpointId(peerChainId);

        (bytes32 current, bool readable) = localAdapter.readWord(
            abi.encodeCall(IBridgeAdapter.getBridgeChainId, (peerChainId))
        );

        bool applied = readable && current == bytes32(endpointId) && !_forceReplay();
        uint32 displacedChainId;

        if (!applied) {
            displacedChainId = _revertIfBridgeChainIdConflicts(localAdapter, peerChainId, endpointId, peerChainIds);

            // A mapping moving off a non-zero value takes the peer with it; a first assignment
            // (current == 0) does not. An unreadable mapping is treated as if it did.
            clearsPeer = !readable || (current != bytes32(0) && current != bytes32(endpointId));
        }

        action = _action(
            localAdapter,
            abi.encodeCall(IBridgeAdapter.setBridgeChainId, (peerChainId, endpointId)),
            string.concat(
                "adapter.setBridgeChainId(",
                _label(peerChainId),
                vm.toString(endpointId),
                ")",
                displacedChainId == 0
                    ? ""
                    : string.concat(" [also clears chain ", vm.toString(displacedChainId), " mapping and peer]")
            ),
            applied,
            readable
        );
    }

    /// @dev Refuses a batch that would strip a peer configured in the same run. Recover by
    ///      configuring the displaced holder in a separate run first. A holder outside this run
    ///      is returned so the plan discloses the collateral mapping and peer teardown.
    function _revertIfBridgeChainIdConflicts(
        address localAdapter,
        uint32 peerChainId,
        uint256 endpointId,
        uint32[] memory peerChainIds
    ) private view returns (uint32 displacedChainId) {
        (bytes32 holder, bool readable) = localAdapter.readWord(
            abi.encodeCall(IBridgeAdapter.getChainId, (endpointId))
        );

        if (!readable) return 0;

        uint32 holderChainId = uint32(uint256(holder));
        if (holderChainId == 0 || holderChainId == peerChainId) return 0;

        for (uint256 i; i < peerChainIds.length; ++i) {
            if (peerChainIds[i] == holderChainId) {
                revert ConflictingBridgeChainId(peerChainId, holderChainId, endpointId);
            }
        }

        return holderChainId;
    }

    function _setSupportedBridgeAdapterAction(
        address portal,
        address localAdapter,
        uint32 peerChainId
    ) private view returns (PlannedAction memory) {
        (bool applied, bool readable) = _settingState(
            portal,
            abi.encodeCall(IPortal.supportedBridgeAdapter, (peerChainId, localAdapter)),
            bytes32(uint256(1))
        );

        return
            _action(
                portal,
                abi.encodeCall(IPortal.setSupportedBridgeAdapter, (peerChainId, localAdapter, true)),
                string.concat("portal.setSupportedBridgeAdapter(", _label(peerChainId), vm.toString(localAdapter), ")"),
                applied,
                readable
            );
    }

    function _setPayloadGasLimitAction(address portal, uint32 peerChainId) private view returns (PlannedAction memory) {
        uint256 gasLimit = RouteConfig.getPayloadGasLimit(peerChainId);

        (bool applied, bool readable) = _settingState(
            portal,
            abi.encodeCall(IPortal.payloadGasLimit, (peerChainId)),
            bytes32(gasLimit)
        );

        return
            _action(
                portal,
                abi.encodeCall(IPortal.setPayloadGasLimit, (peerChainId, gasLimit)),
                string.concat("portal.setPayloadGasLimit(", _label(peerChainId), vm.toString(gasLimit), ")"),
                applied,
                readable
            );
    }

    function _setDefaultBridgeAdapterAction(
        address portal,
        address localAdapter,
        uint32 peerChainId
    ) private view returns (PlannedAction memory) {
        (bool applied, bool readable) = _settingState(
            portal,
            abi.encodeCall(IPortal.defaultBridgeAdapter, (peerChainId)),
            bytes32(uint256(uint160(localAdapter)))
        );

        return
            _action(
                portal,
                abi.encodeCall(IPortal.setDefaultBridgeAdapter, (peerChainId, localAdapter)),
                string.concat("portal.setDefaultBridgeAdapter(", _label(peerChainId), vm.toString(localAdapter), ")"),
                applied,
                readable
            );
    }

    /// @dev Renders the `<peerChainId> -> ` prefix shared by every setting's log line.
    function _label(uint32 peerChainId) private view returns (string memory) {
        return string.concat(vm.toString(uint256(peerChainId)), " -> ");
    }

    /// @dev Resolves the bridge adapter address on a peer chain. Overridable for testing.
    function _getPeerAdapter(uint32 peerChainId) internal view virtual returns (address) {
        return _readDeployment(peerChainId).layerZeroBridgeAdapter;
    }

    /// @dev Whether the operator asked for every setting to be re-sent regardless of current state.
    ///      Overridable so tests can exercise both paths without the environment.
    function _forceReplay() internal view virtual returns (bool) {
        return vm.envOr("FORCE_REPLAY", false);
    }

    /// @dev Reads one setting's current value. `applied` is true only when the getter could be read
    ///      and already holds `expected`; `readable` reports whether the read succeeded at all, so an
    ///      unreadable setting can be labelled rather than silently re-sent. `FORCE_REPLAY` forces
    ///      every setting back into the batch without suppressing the read.
    function _settingState(
        address target,
        bytes memory data,
        bytes32 expected
    ) private view returns (bool applied, bool readable) {
        bytes32 word;
        (word, readable) = target.readWord(data);

        applied = readable && word == expected && !_forceReplay();
    }

    function _action(
        address target,
        bytes memory data,
        string memory description,
        bool applied,
        bool readable
    ) private pure returns (PlannedAction memory) {
        return
            PlannedAction({
                transaction: Transaction({ target: target, data: data, value: 0 }),
                description: readable ? description : string.concat(description, " [current state unreadable]"),
                applied: applied
            });
    }
}
