// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice A stateful stand-in for `BridgeAdapter`'s configuration surface, without the access
///         control, proxy or messaging paths.
/// @dev    `setPeer`, `setBridgeChainId` and the three getters mirror
///         `src/portal/bridgeAdapters/BridgeAdapter.sol` line for line, including the part the
///         rerun planner has to respect: `setBridgeChainId` maintains a 1-1 mapping, and any chain
///         that loses its side of that mapping also has its peer cleared. Reruns are planned from
///         these getters and executed against these setters, so a plan that gets the ordering wrong
///         ends the run with a zero peer here exactly as it would on chain.
contract MockConfigurableBridgeAdapter {
    mapping(uint32 internalChainId => uint256 bridgeChainId) internal _internalToBridgeChainId;
    mapping(uint32 internalChainId => bytes32 peer) internal _remotePeer;
    mapping(uint256 bridgeChainId => uint32 internalChainId) internal _bridgeToInternalChainId;

    address public endpoint;

    error ZeroChain();
    error ZeroBridgeChain();

    constructor(address endpoint_) {
        endpoint = endpoint_;
    }

    function setPeer(uint32 chainId, bytes32 peer) external {
        if (chainId == 0) revert ZeroChain();

        if (_remotePeer[chainId] == peer) return;

        _remotePeer[chainId] = peer;
    }

    function setBridgeChainId(uint32 chainId, uint256 bridgeChainId) external {
        if (chainId == 0) revert ZeroChain();
        if (bridgeChainId == 0) revert ZeroBridgeChain();

        if (_internalToBridgeChainId[chainId] == bridgeChainId) return;

        uint32 oldInternalChainId = _bridgeToInternalChainId[bridgeChainId];
        if (oldInternalChainId != 0 && oldInternalChainId != chainId) {
            delete _internalToBridgeChainId[oldInternalChainId];
            delete _remotePeer[oldInternalChainId];
        }

        uint256 oldBridgeChainId = _internalToBridgeChainId[chainId];
        if (oldBridgeChainId != 0 && oldBridgeChainId != bridgeChainId) {
            delete _bridgeToInternalChainId[oldBridgeChainId];
            delete _remotePeer[chainId];
        }

        _internalToBridgeChainId[chainId] = bridgeChainId;
        _bridgeToInternalChainId[bridgeChainId] = chainId;
    }

    function getPeer(uint32 chainId) external view returns (bytes32) {
        return _remotePeer[chainId];
    }

    function getBridgeChainId(uint32 chainId) external view returns (uint256) {
        return _internalToBridgeChainId[chainId];
    }

    function getChainId(uint256 bridgeChainId) external view returns (uint32) {
        return _bridgeToInternalChainId[bridgeChainId];
    }
}
