// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.34;

import { IBridgeAdapter } from "../../src/portal/interfaces/IBridgeAdapter.sol";

contract MockBridgeAdapter is IBridgeAdapter {
    address public portal;
    uint256 public quoteValue;

    function setPortal(address portal_) external {
        portal = portal_;
    }

    function sendMessage(
        uint32 destinationChainId,
        uint256 gasLimit,
        bytes32 refundAddress,
        bytes memory payload
    ) external payable {}

    function setQuote(uint256 quote_) external {
        quoteValue = quote_;
    }

    function quote(uint32 destinationChainId, uint256 gasLimit, bytes memory payload) external view returns (uint256) {
        return quoteValue;
    }

    function getPeer(uint32 chainId) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getBridgeChainId(uint32 chainId) external pure returns (uint256) {
        return 0;
    }

    function getChainId(uint256 bridgeChainId) external pure returns (uint32) {
        return 0;
    }

    function setPeer(uint32 destinationChainId, bytes32 destinationPeer) external {
        // Mock implementation
    }

    function setBridgeChainId(uint32 chainId, uint256 bridgeChainId) external {
        // Mock implementation
    }

    function initialize(address admin, address operator) external {
        // Mock implementation
    }
}
