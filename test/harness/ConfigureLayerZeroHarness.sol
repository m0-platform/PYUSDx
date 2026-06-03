// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { ConfigureLayerZeroBase } from "../../script/configure/ConfigureLayerZeroBase.sol";
import { UlnConfig } from "../../script/config/LayerZeroConfig.sol";
import { Transaction } from "../../script/libraries/TransactionHelper.sol";

/// @notice Exposes ConfigureLayerZeroBase's internal ULN builder and config registry for unit testing.
contract ConfigureLayerZeroHarness is ConfigureLayerZeroBase {
    function buildTransactions(
        uint32 chainId,
        address adapter,
        uint32[] memory peerChainIds
    ) external view returns (Transaction[] memory) {
        return _buildTransactions(chainId, adapter, peerChainIds);
    }

    function sendUlnConfig(uint32 currentChainId, uint32 remoteChainId) external view returns (UlnConfig memory) {
        return getSendUlnConfig(currentChainId, remoteChainId);
    }

    function receiveUlnConfig(uint32 currentChainId, uint32 remoteChainId) external view returns (UlnConfig memory) {
        return getReceiveUlnConfig(currentChainId, remoteChainId);
    }
}
