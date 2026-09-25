// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { ConfigurePortalBase } from "../../script/configure/ConfigurePortalBase.sol";
import { LayerZeroConfig } from "../../script/config/LayerZeroConfig.sol";
import { RouteConfig } from "../../script/config/RouteConfig.sol";
import { PlannedAction } from "../../script/libraries/ConfigurationPlan.sol";
import { Transaction } from "../../script/libraries/TransactionHelper.sol";

/// @notice Exposes ConfigurePortalBase's internal builder and config lookups for unit testing,
///         with an in-memory peer-adapter registry that replaces the deployment-file lookup.
contract ConfigurePortalHarness is ConfigurePortalBase {
    mapping(uint32 chainId => address adapter) internal _peerAdapters;

    /// @dev Replaces the `FORCE_REPLAY` environment read once `setForceReplay` is called, so a test
    ///      can exercise the override without mutating the process environment shared by every suite.
    bool internal _forceReplayOverride;
    bool internal _forceReplayOverridden;

    function setPeerAdapter(uint32 chainId, address adapter) external {
        _peerAdapters[chainId] = adapter;
    }

    function setForceReplay(bool value) external {
        _forceReplayOverride = value;
        _forceReplayOverridden = true;
    }

    function forceReplay() external view returns (bool) {
        return _forceReplay();
    }

    function planPeers(
        address portal,
        address localAdapter,
        uint32[] memory peerChainIds
    ) external view returns (PlannedAction[] memory) {
        return _planPeers(portal, localAdapter, peerChainIds);
    }

    function configurePeers(
        address portal,
        address localAdapter,
        uint32[] memory peerChainIds
    ) external view returns (Transaction[] memory) {
        return _configurePeers(portal, localAdapter, peerChainIds);
    }

    function getLayerZeroEndpointId(uint32 chainId) external pure returns (uint32) {
        return LayerZeroConfig.getLayerZeroEndpointId(chainId);
    }

    function getPayloadGasLimit(uint32 chainId) external pure returns (uint256) {
        return RouteConfig.getPayloadGasLimit(chainId);
    }

    function _getPeerAdapter(uint32 peerChainId) internal view override returns (address) {
        return _peerAdapters[peerChainId];
    }

    function _forceReplay() internal view override returns (bool) {
        return _forceReplayOverridden ? _forceReplayOverride : super._forceReplay();
    }
}
