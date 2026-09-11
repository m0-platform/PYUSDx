// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { ConfigureLayerZeroBase } from "../../script/configure/ConfigureLayerZeroBase.sol";
import { UlnConfig } from "../../script/config/LayerZeroConfig.sol";
import { PlannedAction } from "../../script/libraries/ConfigurationPlan.sol";
import { Transaction } from "../../script/libraries/TransactionHelper.sol";

/// @notice Exposes ConfigureLayerZeroBase's internal ULN builder and config registry for unit testing.
contract ConfigureLayerZeroHarness is ConfigureLayerZeroBase {
    /// @dev Replaces the `FORCE_REPLAY` environment read once `setForceReplay` is called, so a test
    ///      can exercise the override without mutating the process environment shared by every suite.
    bool internal _forceReplayOverride;
    bool internal _forceReplayOverridden;

    function setForceReplay(bool value) external {
        _forceReplayOverride = value;
        _forceReplayOverridden = true;
    }

    function forceReplay() external view returns (bool) {
        return _forceReplay();
    }

    function planPeers(
        uint32 chainId,
        address adapter,
        uint32[] memory peerChainIds
    ) external view returns (PlannedAction[] memory) {
        return _planPeers(chainId, adapter, peerChainIds);
    }

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

    function _forceReplay() internal view override returns (bool) {
        return _forceReplayOverridden ? _forceReplayOverride : super._forceReplay();
    }
}
