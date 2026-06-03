// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { ILayerZeroBridgeAdapter } from "../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroBridgeAdapter.sol";

import { ILayerZeroEndpointV2Like, SetConfigParam } from "../interfaces/ILayerZeroEndpointV2Like.sol";
import {
    CONFIG_TYPE_ULN,
    LayerZeroBridgeAdapterNotDeployed,
    LayerZeroConfig,
    LayerZeroUlnConfig,
    UlnConfig
} from "../config/LayerZeroConfig.sol";
import { Transaction } from "../libraries/TransactionHelper.sol";
import { ScriptBase } from "../ScriptBase.s.sol";

/// @title  ConfigureLayerZeroBase
/// @notice Builds the LayerZero V2 ULN `setConfig` transactions for a list of remote peer chains.
/// @dev    Shared by the broadcast script (`ConfigureLayerZero`) and the Safe propose script
///         (`ProposeConfigureLayerZero`). For each peer it produces two `endpoint.setConfig` calls:
///         one on the send library (send-side ULN config) and one on the receive library.
///         The signer must be the LayerZeroBridgeAdapter's LayerZero delegate.
abstract contract ConfigureLayerZeroBase is ScriptBase, LayerZeroUlnConfig {
    /// @dev Transactions emitted per peer: one `setConfig` on the send library, one on the receive library.
    uint256 internal constant _TXS_PER_PEER = 2;

    /// @notice Builds the ULN `setConfig` transactions for each peer chain.
    /// @param  chainId      The local chain ID (where the config is applied).
    /// @param  adapter      The local LayerZeroBridgeAdapter address.
    /// @param  peerChainIds The remote chain IDs to configure routes for.
    /// @return transactions The ordered `endpoint.setConfig` calls (send + receive per peer).
    function _buildTransactions(
        uint32 chainId,
        address adapter,
        uint32[] memory peerChainIds
    ) internal view returns (Transaction[] memory transactions) {
        if (adapter == address(0)) revert LayerZeroBridgeAdapterNotDeployed(chainId);

        address endpoint = ILayerZeroBridgeAdapter(adapter).endpoint();

        transactions = new Transaction[](peerChainIds.length * _TXS_PER_PEER);
        uint256 txCount;

        for (uint256 i; i < peerChainIds.length; ++i) {
            (Transaction memory sendTx, Transaction memory receiveTx) = _buildPeerTxs(
                adapter,
                endpoint,
                chainId,
                peerChainIds[i]
            );

            transactions[txCount++] = sendTx;
            transactions[txCount++] = receiveTx;
        }
    }

    function _buildPeerTxs(
        address adapter,
        address endpoint,
        uint32 chainId,
        uint32 remoteChainId
    ) private view returns (Transaction memory sendTx, Transaction memory receiveTx) {
        uint32 remoteEid = LayerZeroConfig.getLayerZeroEndpointId(remoteChainId);

        address sendLib = ILayerZeroEndpointV2Like(endpoint).getSendLibrary(adapter, remoteEid);
        (address receiveLib, ) = ILayerZeroEndpointV2Like(endpoint).getReceiveLibrary(adapter, remoteEid);

        sendTx = _buildSetConfigTx(adapter, endpoint, sendLib, remoteEid, getSendUlnConfig(chainId, remoteChainId));
        receiveTx = _buildSetConfigTx(
            adapter,
            endpoint,
            receiveLib,
            remoteEid,
            getReceiveUlnConfig(chainId, remoteChainId)
        );
    }

    function _buildSetConfigTx(
        address adapter,
        address endpoint,
        address lib,
        uint32 remoteEid,
        UlnConfig memory ulnConfig
    ) private pure returns (Transaction memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({ eid: remoteEid, configType: CONFIG_TYPE_ULN, config: abi.encode(ulnConfig) });

        return
            Transaction({
                target: endpoint,
                data: abi.encodeCall(ILayerZeroEndpointV2Like.setConfig, (adapter, lib, params)),
                value: 0
            });
    }
}
