// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.34;

/// @title  ExecutorOptions
/// @author LayerZero Labs
/// @notice Library for encoding LayerZero V2 executor options.
/// @dev    See full version at:
///         https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/protocol/contracts/messagelib/libs/ExecutorOptions.sol
library ExecutorOptions {
    uint8 internal constant WORKER_ID = 1;

    uint8 internal constant OPTION_TYPE_LZRECEIVE = 1;
    uint8 internal constant OPTION_TYPE_NATIVE_DROP = 2;
    uint8 internal constant OPTION_TYPE_LZCOMPOSE = 3;
    uint8 internal constant OPTION_TYPE_ORDERED_EXECUTION = 4;

    function encodeLzReceiveOption(uint128 gas, uint128 value) internal pure returns (bytes memory) {
        return value == 0 ? abi.encodePacked(gas) : abi.encodePacked(gas, value);
    }
}
