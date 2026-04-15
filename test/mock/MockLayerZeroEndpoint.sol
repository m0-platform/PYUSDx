// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.34;

import {
    Origin,
    MessagingFee,
    MessagingReceipt,
    MessagingParams,
    SetConfigParam
} from "../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";

contract MockLayerZeroEndpoint {
    mapping(address oapp => address delegate) public delegates;

    function quote(
        MessagingParams calldata /* params */,
        address /* sender */
    ) external view returns (MessagingFee memory fee) {
        return MessagingFee({ nativeFee: 0, lzTokenFee: 0 });
    }

    function send(
        MessagingParams calldata /* params */,
        address /* refundAddress */
    ) external payable returns (MessagingReceipt memory receipt) {}

    function setDelegate(address delegate) external {
        delegates[msg.sender] = delegate;
    }

    /// @notice Allows the contract to receive ETH for fee handling.
    receive() external payable {}

    function sendCompose(address to, bytes32 guid, uint16 index, bytes calldata message) external {}
}
