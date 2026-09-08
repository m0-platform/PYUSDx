// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice A stateful stand-in for the Portal's per-destination configuration surface, without the
///         access control or bridging paths.
/// @dev    Mirrors `src/portal/Portal.sol`'s setters and getters for the three settings the
///         configuration scripts write, so a plan can be executed against it and re-planned.
contract MockConfigurablePortal {
    mapping(uint32 destinationChainId => address bridgeAdapter) public defaultBridgeAdapter;
    mapping(uint32 destinationChainId => mapping(address bridgeAdapter => bool)) public supportedBridgeAdapter;
    mapping(uint32 destinationChainId => uint256 gasLimit) public payloadGasLimit;

    function setDefaultBridgeAdapter(uint32 destinationChainId, address bridgeAdapter) external {
        defaultBridgeAdapter[destinationChainId] = bridgeAdapter;
    }

    function setSupportedBridgeAdapter(uint32 destinationChainId, address bridgeAdapter, bool supported) external {
        supportedBridgeAdapter[destinationChainId][bridgeAdapter] = supported;
    }

    function setPayloadGasLimit(uint32 destinationChainId, uint256 gasLimit) external {
        payloadGasLimit[destinationChainId] = gasLimit;
    }
}
