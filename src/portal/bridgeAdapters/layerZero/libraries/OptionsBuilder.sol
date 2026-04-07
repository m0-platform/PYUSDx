// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import { SafeCast } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { ExecutorOptions } from "./ExecutorOptions.sol";

/// @title  OptionsBuilder
/// @author LayerZero Labs
/// @notice Library for building LayerZero V2 messaging options.
/// @dev    See full version at:
///         https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OptionsBuilder.sol
library OptionsBuilder {
    using SafeCast for uint256;

    // Constants for options types
    uint16 internal constant TYPE_1 = 1; // legacy options type 1
    uint16 internal constant TYPE_2 = 2; // legacy options type 2
    uint16 internal constant TYPE_3 = 3;

    error InvalidSize(uint256 max, uint256 actual);
    error InvalidOptionType(uint16 optionType);

    /// @dev Creates a new options container with type 3.
    function newOptions() internal pure returns (bytes memory) {
        return abi.encodePacked(TYPE_3);
    }

    /// @dev Adds an executor LZ receive option to the existing options.
    /// @param options The existing options container.
    /// @param gas     The gasLimit used on the lzReceive() function in the OApp.
    /// @param value   The msg.value passed to the lzReceive() function in the OApp.
    function addExecutorLzReceiveOption(
        bytes memory options,
        uint128 gas,
        uint128 value
    ) internal pure returns (bytes memory) {
        bytes memory option = ExecutorOptions.encodeLzReceiveOption(gas, value);
        return addExecutorOption(options, ExecutorOptions.OPTION_TYPE_LZRECEIVE, option);
    }

    /// @dev Adds an executor LZ compose option to the existing options.
    /// @param options The existing options container.
    /// @param index The index for the lzCompose() function call.
    /// @param gas The gasLimit for the lzCompose() function call.
    /// @param value The msg.value for the lzCompose() function call.
    /// @return options The updated options container.
    ///
    /// @dev When multiples of this option are added, they are summed PER index by the executor on the remote chain.
    /// @dev If the OApp sends N lzCompose calls on the remote, you must provide N incremented indexes starting with 0.
    /// i.e. When your remote OApp composes (N = 3) messages, you must set this option for index 0,1,2
    function addExecutorLzComposeOption(
        bytes memory options,
        uint16 index,
        uint128 gas,
        uint128 value
    ) internal pure returns (bytes memory) {
        bytes memory option = ExecutorOptions.encodeLzComposeOption(index, gas, value);
        return addExecutorOption(options, ExecutorOptions.OPTION_TYPE_LZCOMPOSE, option);
    }

    /// @dev Adds an executor option to the existing options.
    /// @param options    The existing options container.
    /// @param optionType The type of the executor option.
    /// @param option     The encoded data for the executor option.
    function addExecutorOption(
        bytes memory options,
        uint8 optionType,
        bytes memory option
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                options,
                ExecutorOptions.WORKER_ID,
                option.length.toUint16() + 1, // +1 for optionType
                optionType,
                option
            );
    }
}
