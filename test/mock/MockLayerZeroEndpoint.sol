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

    /// @notice The native fee required by `send` and returned by `quote`. Defaults to 0.
    uint256 public fee;

    uint32 public lastDstEid;
    bytes32 public lastReceiver;
    bytes public lastMessage;
    bytes public lastOptions;
    address public lastRefundAddress;
    uint256 public lastValue;
    uint64 public sendCount;

    error InsufficientFee(uint256 required, uint256 provided);
    error RefundFailed();

    function setFee(uint256 fee_) external {
        fee = fee_;
    }

    function quote(
        MessagingParams calldata /* params */,
        address /* sender */
    ) external view returns (MessagingFee memory) {
        return MessagingFee({ nativeFee: fee, lzTokenFee: 0 });
    }

    /// @notice Mirrors the real endpoint's fee handling: reverts if underpaid and
    ///         refunds the excess over the required fee to the refund address.
    function send(
        MessagingParams calldata params,
        address refundAddress
    ) external payable returns (MessagingReceipt memory receipt) {
        if (msg.value < fee) revert InsufficientFee(fee, msg.value);

        lastDstEid = params.dstEid;
        lastReceiver = params.receiver;
        lastMessage = params.message;
        lastOptions = params.options;
        lastRefundAddress = refundAddress;
        lastValue = msg.value;
        sendCount++;

        if (msg.value > fee) {
            (bool success, ) = refundAddress.call{ value: msg.value - fee }("");
            if (!success) revert RefundFailed();
        }

        return
            MessagingReceipt({
                guid: keccak256(abi.encode(sendCount)),
                nonce: sendCount,
                fee: MessagingFee({ nativeFee: fee, lzTokenFee: 0 })
            });
    }

    function setDelegate(address delegate) external {
        delegates[msg.sender] = delegate;
    }

    /// @notice Allows the contract to receive ETH for fee handling.
    receive() external payable {}
}
