// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.34;

import { AccessControlUpgradeable } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { IBridgeAdapter } from "../interfaces/IBridgeAdapter.sol";

abstract contract BridgeAdapterStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.BridgeAdapter
    struct BridgeAdapterStorageStruct {
        /// @notice Maps M0 internal chain IDs to bridge-specific chain IDs.
        mapping(uint32 internalChainId => uint256 bridgeChainId) internalToBridgeChainId;
        /// @notice Maps M0 internal chain IDs to remote Bridge Adapter addresses.
        mapping(uint32 internalChainId => bytes32 peer) remotePeer;
        /// @notice Maps bridge-specific chain IDs to M0 internal chain IDs.
        mapping(uint256 bridgeChainId => uint32 internalChainId) bridgeToInternalChainId;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.BridgeAdapter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant BRIDGE_ADAPTER_STORAGE_LOCATION =
        0xd75c6d13973e9e8153b1592a6580d542ea215862c7c5b523d53847b2e2d63d00;

    function _getBridgeAdapterStorageLocation() internal pure returns (BridgeAdapterStorageStruct storage $) {
        assembly {
            $.slot := BRIDGE_ADAPTER_STORAGE_LOCATION
        }
    }
}

/// @title  BridgeAdapter abstract contract
/// @author M0 Labs
/// @notice Base contract for bridge adapters implementing cross-chain messaging functionality.
abstract contract BridgeAdapter is IBridgeAdapter, BridgeAdapterStorageLayout, AccessControlUpgradeable {
    /// @inheritdoc IBridgeAdapter
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @inheritdoc IBridgeAdapter
    address public immutable portal;

    /// @notice Constructs the Implementation contract
    /// @dev    Sets immutable storage.
    /// @param  portal_ The address of Portal.
    constructor(address portal_) {
        _disableInitializers();

        if ((portal = portal_) == address(0)) revert ZeroPortal();
    }

    /// @notice Initializes the Proxy's storage
    /// @param  admin    The address of the admin.
    /// @param  operator The address of the operator.
    function _initialize(address admin, address operator) internal onlyInitializing {
        if (admin == address(0)) revert ZeroAdmin();
        if (operator == address(0)) revert ZeroOperator();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
    }

    /* ============ Privileged Functions ============ */

    /// @inheritdoc IBridgeAdapter
    function setPeer(uint32 chainId, bytes32 peer) external onlyRole(OPERATOR_ROLE) {
        _revertIfZeroChain(chainId);

        BridgeAdapterStorageStruct storage $ = _getBridgeAdapterStorageLocation();

        if ($.remotePeer[chainId] == peer) return;

        $.remotePeer[chainId] = peer;
        emit PeerSet(chainId, peer);
    }

    /// @inheritdoc IBridgeAdapter
    /// @dev Maintains the 1-1 chain ID mapping. Any chain that loses its existing pair as a side
    ///      effect — the reassigned chain and the orphaned chain — also has its peer cleared, so
    ///      a stale peer can never be combined with an updated bridge chain ID: sends to that
    ///      chain revert with `UnsupportedChain` until the operator re-asserts the peer via
    ///      `setPeer`. A fresh assignment leaves the chain's peer untouched.
    function setBridgeChainId(uint32 chainId, uint256 bridgeChainId) external onlyRole(OPERATOR_ROLE) {
        _revertIfZeroChain(chainId);
        _revertIfZeroBridgeChain(bridgeChainId);

        BridgeAdapterStorageStruct storage $ = _getBridgeAdapterStorageLocation();

        if ($.internalToBridgeChainId[chainId] == bridgeChainId) return;

        // Clean up old forward mapping if this bridge chain was mapped to a different internal chain
        uint32 oldInternalChainId = $.bridgeToInternalChainId[bridgeChainId];
        if (oldInternalChainId != 0 && oldInternalChainId != chainId) {
            delete $.internalToBridgeChainId[oldInternalChainId];
            emit BridgeChainIdRemoved(oldInternalChainId, bridgeChainId);
            _removePeer($, oldInternalChainId);
        }

        // Clean up old reverse mapping if this internal chain was mapped to a different bridge chain
        uint256 oldBridgeChainId = $.internalToBridgeChainId[chainId];
        if (oldBridgeChainId != 0 && oldBridgeChainId != bridgeChainId) {
            delete $.bridgeToInternalChainId[oldBridgeChainId];
            emit BridgeChainIdRemoved(chainId, oldBridgeChainId);
            _removePeer($, chainId);
        }

        $.internalToBridgeChainId[chainId] = bridgeChainId;
        $.bridgeToInternalChainId[bridgeChainId] = chainId;

        emit BridgeChainIdSet(chainId, bridgeChainId);
    }

    /// @dev Clears the peer of a chain whose `(chainId, bridgeChainId)` pair was removed by
    ///      `setBridgeChainId`, emitting `PeerSet` with a zero peer.
    function _removePeer(BridgeAdapterStorageStruct storage $, uint32 chainId) private {
        if ($.remotePeer[chainId] == bytes32(0)) return;

        delete $.remotePeer[chainId];
        emit PeerSet(chainId, bytes32(0));
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IBridgeAdapter
    function getPeer(uint32 chainId) external view returns (bytes32) {
        return _getPeer(chainId);
    }

    /// @inheritdoc IBridgeAdapter
    function getBridgeChainId(uint32 chainId) external view returns (uint256) {
        return _getBridgeChainId(chainId);
    }

    /// @inheritdoc IBridgeAdapter
    function getChainId(uint256 bridgeChainId) external view returns (uint32) {
        return _getChainId(bridgeChainId);
    }

    /// @notice Returns the configured peer for the given internal chain ID.
    /// @param  chainId The M0 internal chain ID.
    function _getPeer(uint32 chainId) internal view returns (bytes32) {
        return _getBridgeAdapterStorageLocation().remotePeer[chainId];
    }

    /// @notice Returns the bridge-specific chain ID for the given internal chain ID.
    /// @param  chainId The M0 internal chain ID.
    function _getBridgeChainId(uint32 chainId) internal view returns (uint256) {
        return _getBridgeAdapterStorageLocation().internalToBridgeChainId[chainId];
    }

    /// @notice Returns the internal chain ID for the given bridge-specific chain ID.
    /// @param  bridgeChainId The bridge-specific chain ID.
    function _getChainId(uint256 bridgeChainId) internal view returns (uint32) {
        return _getBridgeAdapterStorageLocation().bridgeToInternalChainId[bridgeChainId];
    }

    /// @notice Returns the configured peer for the given internal chain ID or reverts if not found.
    /// @param  chainId The M0 internal chain ID.
    function _getPeerOrRevert(uint32 chainId) internal view returns (bytes32) {
        bytes32 peer = _getPeer(chainId);
        if (peer == bytes32(0)) revert UnsupportedChain(chainId);
        return peer;
    }

    /// @notice Returns the bridge-specific chain ID for the given internal chain ID or reverts if not found.
    /// @param  chainId The M0 internal chain ID.
    function _getBridgeChainIdOrRevert(uint32 chainId) internal view returns (uint256) {
        uint256 bridgeChainId = _getBridgeChainId(chainId);
        if (bridgeChainId == 0) revert UnsupportedChain(chainId);
        return bridgeChainId;
    }

    /// @notice Returns the internal chain ID for the given bridge-specific chain ID or reverts if not found.
    /// @param  bridgeChainId The bridge-specific chain ID.
    function _getChainIdOrRevert(uint256 bridgeChainId) internal view returns (uint32) {
        uint32 chainId = _getChainId(bridgeChainId);
        if (chainId == 0) revert UnsupportedBridgeChain(bridgeChainId);
        return chainId;
    }

    /// @notice Reverts if the given chain ID is zero.
    /// @param  chainId The M0 internal chain ID.
    function _revertIfZeroChain(uint32 chainId) internal pure {
        if (chainId == 0) revert ZeroChain();
    }

    /// @notice Reverts if the given bridge-specific chain ID is zero.
    /// @param  bridgeChainId The bridge-specific chain ID.
    function _revertIfZeroBridgeChain(uint256 bridgeChainId) internal pure {
        if (bridgeChainId == 0) revert ZeroBridgeChain();
    }

    /// @notice Reverts if `msg.sender` is not the Portal.
    function _revertIfNotPortal() internal view {
        if (msg.sender != portal) revert NotPortal();
    }
}
