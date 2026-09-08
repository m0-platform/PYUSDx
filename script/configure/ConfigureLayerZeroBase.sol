// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { ILayerZeroBridgeAdapter } from "../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroBridgeAdapter.sol";

import { ILayerZeroEndpointV2Like, SetConfigParam } from "../interfaces/ILayerZeroEndpointV2Like.sol";
import { IUln302Like } from "../interfaces/IUln302Like.sol";
import {
    CONFIG_TYPE_ULN,
    LayerZeroBridgeAdapterNotDeployed,
    LayerZeroConfig,
    LayerZeroUlnConfig,
    UlnConfig
} from "../config/LayerZeroConfig.sol";
import { ConfigurationPlan, PlannedAction } from "../libraries/ConfigurationPlan.sol";
import { StateReader } from "../libraries/StateReader.sol";
import { Transaction } from "../libraries/TransactionHelper.sol";
import { ScriptBase } from "../ScriptBase.s.sol";

/// @title  ConfigureLayerZeroBase
/// @notice Builds the LayerZero V2 ULN `setConfig` transactions for a list of remote peer chains,
///         skipping the routes whose ULN config the adapter already pins.
/// @dev    Shared by the broadcast script (`ConfigureLayerZero`) and the Safe propose script
///         (`ProposeConfigureLayerZero`). For each peer it produces up to two `endpoint.setConfig`
///         calls: one on the send library (send-side ULN config) and one on the receive library.
///         The signer must be the LayerZeroBridgeAdapter's LayerZero delegate.
abstract contract ConfigureLayerZeroBase is ScriptBase, LayerZeroUlnConfig {
    using ConfigurationPlan for PlannedAction[];
    using StateReader for address;

    /// @dev Settings inspected, and at most emitted, per peer: one `setConfig` on the send library,
    ///      one on the receive library.
    uint256 internal constant _TXS_PER_PEER = 2;

    /// @notice Builds the ULN `setConfig` transactions still needed for each peer chain.
    /// @param  chainId      The local chain ID (where the config is applied).
    /// @param  adapter      The local LayerZeroBridgeAdapter address.
    /// @param  peerChainIds The remote chain IDs to configure routes for.
    /// @return transactions The ordered `endpoint.setConfig` calls, minus the already-pinned ones.
    function _buildTransactions(
        uint32 chainId,
        address adapter,
        uint32[] memory peerChainIds
    ) internal view returns (Transaction[] memory transactions) {
        return _planPeers(chainId, adapter, peerChainIds).compact();
    }

    /// @notice Builds the full intended ULN configuration for each peer chain, tagging each side of
    ///         the route with whether the adapter already pins that exact config.
    /// @dev    The comparison is against the adapter's *own* stored config on the message library,
    ///         not the effective config the endpoint reports: a route that merely inherits matching
    ///         library defaults is not pinned and is still planned. When the library does not expose
    ///         `getAppUlnConfig`, the current state is unknown and the setting stays planned.
    /// @param  chainId      The local chain ID (where the config is applied).
    /// @param  adapter      The local LayerZeroBridgeAdapter address.
    /// @param  peerChainIds The remote chain IDs to configure routes for.
    /// @return actions      Every intended setting, in transaction order, tagged applied or planned.
    function _planPeers(
        uint32 chainId,
        address adapter,
        uint32[] memory peerChainIds
    ) internal view returns (PlannedAction[] memory actions) {
        if (adapter == address(0)) revert LayerZeroBridgeAdapterNotDeployed(chainId);

        address endpoint = ILayerZeroBridgeAdapter(adapter).endpoint();

        actions = new PlannedAction[](peerChainIds.length * _TXS_PER_PEER);
        uint256 count;

        for (uint256 i; i < peerChainIds.length; ++i) {
            (PlannedAction memory sendAction, PlannedAction memory receiveAction) = _peerActions(
                adapter,
                endpoint,
                chainId,
                peerChainIds[i]
            );

            actions[count++] = sendAction;
            actions[count++] = receiveAction;
        }
    }

    /// @dev Builds the send-side and receive-side settings for one route. Split out of `_planPeers`
    ///      to keep the loop body's stack shallow.
    function _peerActions(
        address adapter,
        address endpoint,
        uint32 chainId,
        uint32 remoteChainId
    ) private view returns (PlannedAction memory sendAction, PlannedAction memory receiveAction) {
        uint32 remoteEid = LayerZeroConfig.getLayerZeroEndpointId(remoteChainId);
        string memory eid = vm.toString(uint256(remoteEid));

        address sendLib = ILayerZeroEndpointV2Like(endpoint).getSendLibrary(adapter, remoteEid);
        (address receiveLib, ) = ILayerZeroEndpointV2Like(endpoint).getReceiveLibrary(adapter, remoteEid);

        sendAction = _action(
            adapter,
            endpoint,
            sendLib,
            remoteEid,
            getSendUlnConfig(chainId, remoteChainId),
            string.concat("endpoint.setConfig(send, eid ", eid, ")")
        );

        receiveAction = _action(
            adapter,
            endpoint,
            receiveLib,
            remoteEid,
            getReceiveUlnConfig(chainId, remoteChainId),
            string.concat("endpoint.setConfig(receive, eid ", eid, ")")
        );
    }

    /// @dev Whether the operator asked for every setting to be re-sent regardless of current state.
    ///      Overridable so tests can exercise both paths without the environment.
    function _forceReplay() internal view virtual returns (bool) {
        return vm.envOr("FORCE_REPLAY", false);
    }

    function _action(
        address adapter,
        address endpoint,
        address lib,
        uint32 remoteEid,
        UlnConfig memory ulnConfig,
        string memory description
    ) private view returns (PlannedAction memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({ eid: remoteEid, configType: CONFIG_TYPE_ULN, config: abi.encode(ulnConfig) });

        (bool applied, bool readable) = _pinState(adapter, lib, remoteEid, ulnConfig);

        return
            PlannedAction({
                transaction: Transaction({
                    target: endpoint,
                    data: abi.encodeCall(ILayerZeroEndpointV2Like.setConfig, (adapter, lib, params)),
                    value: 0
                }),
                description: readable ? description : string.concat(description, " [current state unreadable]"),
                applied: applied
            });
    }

    /// @dev Reads the route's current app-level ULN config off the message library. `applied` is true
    ///      only when that config is identical to the intended one; `readable` reports whether the
    ///      library answered at all, so a library that does not expose `getAppUlnConfig` produces a
    ///      labelled, re-sent route rather than a silent degradation. `FORCE_REPLAY` forces every
    ///      route back into the batch without suppressing the read.
    function _pinState(
        address adapter,
        address lib,
        uint32 remoteEid,
        UlnConfig memory intended
    ) private view returns (bool applied, bool readable) {
        bytes memory returnData;

        (returnData, readable) = lib.readStruct(
            abi.encodeCall(IUln302Like.getAppUlnConfig, (adapter, remoteEid)),
            StateReader.ULN_CONFIG_MIN_RETURN_LENGTH
        );

        if (!readable) return (false, false);

        applied = _ulnConfigsMatch(abi.decode(returnData, (UlnConfig)), intended) && !_forceReplay();
    }

    /// @dev Field-by-field equality, including DVN list order. `_buildUlnConfig` sorts both DVN
    ///      lists ascending and ULN302 stores the config as submitted, so an unchanged rerun reads
    ///      back exactly what the previous run wrote.
    function _ulnConfigsMatch(UlnConfig memory current, UlnConfig memory intended) private pure returns (bool) {
        if (current.confirmations != intended.confirmations) return false;
        if (current.requiredDVNCount != intended.requiredDVNCount) return false;
        if (current.optionalDVNCount != intended.optionalDVNCount) return false;
        if (current.optionalDVNThreshold != intended.optionalDVNThreshold) return false;
        if (!_dvnsMatch(current.requiredDVNs, intended.requiredDVNs)) return false;

        return _dvnsMatch(current.optionalDVNs, intended.optionalDVNs);
    }

    function _dvnsMatch(address[] memory current, address[] memory intended) private pure returns (bool) {
        if (current.length != intended.length) return false;

        for (uint256 i; i < current.length; ++i) {
            if (current[i] != intended[i]) return false;
        }

        return true;
    }
}
