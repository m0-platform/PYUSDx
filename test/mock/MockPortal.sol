// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

contract MockPortal {
    address public immutable pyusdx;

    struct ReceiveMessageCall {
        uint32 sourceChainId;
        bytes payload;
    }

    constructor(address pyusdx_) {
        pyusdx = pyusdx_;
    }

    function currentChainId() external view returns (uint32) {
        return 0;
    }

    function receiveMessage(
        uint32 sourceChainId,
        bytes memory payload
    ) external returns (address composer, bytes memory composedMessage) {}
}
