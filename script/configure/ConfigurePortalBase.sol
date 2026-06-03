// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { TypeConverter } from "../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IBridgeAdapter } from "../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../src/portal/interfaces/IPortal.sol";

import { LayerZeroConfig } from "../config/LayerZeroConfig.sol";
import { RouteConfig } from "../config/RouteConfig.sol";
import { Transaction } from "../libraries/TransactionHelper.sol";
import { ScriptBase } from "../ScriptBase.s.sol";

/// @title  ConfigurePortalBase
/// @notice Builds the Portal + LayerZeroBridgeAdapter wiring transactions for a list of peer chains.
/// @dev    Shared by the broadcast script (`ConfigurePortal`) and the Safe propose script
///         (`ProposeConfigurePortal`). The builder is `view` and returns a `Transaction[]` so the
///         exact calls can be unit-tested without broadcasting.
abstract contract ConfigurePortalBase is ScriptBase {
    using TypeConverter for address;

    /// @dev Number of transactions emitted per configured peer.
    uint256 internal constant _TXS_PER_PEER = 5;

    /// @notice Builds the wiring transactions to enable bridging to each peer chain.
    /// @param  portal       The local Portal address.
    /// @param  localAdapter The local LayerZeroBridgeAdapter address.
    /// @param  peerChainIds The remote chain IDs to wire as peers.
    /// @return transactions The ordered Portal/adapter configuration calls.
    function _configurePeers(
        address portal,
        address localAdapter,
        uint32[] memory peerChainIds
    ) internal view returns (Transaction[] memory transactions) {
        uint256 peersCount = peerChainIds.length;

        // Resolve peer adapters once and count the peers that are actually deployed.
        address[] memory peerAdapters = new address[](peersCount);
        uint256 validCount;

        for (uint256 i; i < peersCount; ++i) {
            peerAdapters[i] = _getPeerAdapter(peerChainIds[i]);
            if (peerAdapters[i] != address(0)) ++validCount;
        }

        transactions = new Transaction[](validCount * _TXS_PER_PEER);
        uint256 txCount;

        for (uint256 i; i < peersCount; ++i) {
            address peerAdapter = peerAdapters[i];
            if (peerAdapter == address(0)) continue;

            uint32 peerChainId = peerChainIds[i];
            uint256 endpointId = LayerZeroConfig.getLayerZeroEndpointId(peerChainId);
            uint256 gasLimit = RouteConfig.getPayloadGasLimit(peerChainId);

            transactions[txCount++] = _tx(
                localAdapter,
                abi.encodeCall(IBridgeAdapter.setPeer, (peerChainId, peerAdapter.toBytes32()))
            );

            transactions[txCount++] = _tx(
                localAdapter,
                abi.encodeCall(IBridgeAdapter.setBridgeChainId, (peerChainId, endpointId))
            );

            transactions[txCount++] = _tx(
                portal,
                abi.encodeCall(IPortal.setSupportedBridgeAdapter, (peerChainId, localAdapter, true))
            );

            transactions[txCount++] = _tx(portal, abi.encodeCall(IPortal.setPayloadGasLimit, (peerChainId, gasLimit)));

            transactions[txCount++] = _tx(
                portal,
                abi.encodeCall(IPortal.setDefaultBridgeAdapter, (peerChainId, localAdapter))
            );
        }
    }

    /// @dev Resolves the bridge adapter address on a peer chain. Overridable for testing.
    function _getPeerAdapter(uint32 peerChainId) internal view virtual returns (address) {
        return _readDeployment(peerChainId).layerZeroBridgeAdapter;
    }

    function _tx(address target, bytes memory data) private pure returns (Transaction memory) {
        return Transaction({ target: target, data: data, value: 0 });
    }
}
