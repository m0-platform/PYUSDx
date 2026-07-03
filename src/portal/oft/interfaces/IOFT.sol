// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import { MessagingFee, MessagingReceipt } from "../../bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";

/// @notice Struct representing token parameters for the OFT send() operation.
struct SendParam {
    /// @dev Destination LayerZero Endpoint ID.
    uint32 dstEid;
    /// @dev Recipient address on the destination chain.
    bytes32 to;
    /// @dev Amount to send in local decimals.
    uint256 amountLD;
    /// @dev Minimum amount to receive in local decimals.
    uint256 minAmountLD;
    /// @dev Additional options supplied by the caller to be used in the LayerZero message.
    bytes extraOptions;
    /// @dev The composed message for the send() operation.
    bytes composeMsg;
    /// @dev The OFT command to be executed, unused in default OFT implementations.
    bytes oftCmd;
}

/// @notice Struct representing OFT limit information.
/// @dev    These amounts can change dynamically and are up to the specific implementation.
struct OFTLimit {
    /// @dev The minimum amount in local decimals that can be sent to the recipient.
    uint256 minAmountLD;
    /// @dev The maximum amount in local decimals that can be sent to the recipient.
    uint256 maxAmountLD;
}

/// @notice Struct representing OFT receipt information.
struct OFTReceipt {
    /// @dev The amount of tokens actually debited from the sender in local decimals.
    uint256 amountSentLD;
    /// @dev The amount of tokens to be received on the destination chain in local decimals.
    uint256 amountReceivedLD;
}

/// @notice Struct representing OFT fee details.
/// @dev    Future proof mechanism to provide a standardized way to communicate fees to things like a UI.
struct OFTFeeDetail {
    /// @dev Amount of the fee in local decimals.
    int256 feeAmountLD;
    /// @dev Description of the fee.
    string description;
}

/// @title  IOFT
/// @author LayerZero Labs
/// @notice Minimal interface for the OFT (Omnichain Fungible Token) standard used by `PortalOFTWrapper`.
/// @dev    See full version at:
///         https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/oapp/contracts/oft/interfaces/IOFT.sol
interface IOFT {
    /* ============ Events ============ */

    /// @notice Emitted when tokens are sent to a destination chain.
    /// @param  guid             The unique identifier for the sent message.
    /// @param  dstEid           The destination LayerZero Endpoint ID.
    /// @param  fromAddress      The address of the sender on the source chain.
    /// @param  amountSentLD     The amount of tokens sent in local decimals.
    /// @param  amountReceivedLD The amount of tokens to be received on the destination chain in local decimals.
    event OFTSent(
        bytes32 indexed guid,
        uint32 dstEid,
        address indexed fromAddress,
        uint256 amountSentLD,
        uint256 amountReceivedLD
    );

    /// @notice Emitted when tokens are received from a source chain.
    /// @param  guid             The unique identifier for the received message.
    /// @param  srcEid           The source LayerZero Endpoint ID.
    /// @param  toAddress        The address of the recipient on the destination chain.
    /// @param  amountReceivedLD The amount of tokens received in local decimals.
    event OFTReceived(bytes32 indexed guid, uint32 srcEid, address indexed toAddress, uint256 amountReceivedLD);

    /* ============ Custom Errors ============ */

    /// @notice Thrown when the local decimals are invalid for OFT shared decimals conversion.
    error InvalidLocalDecimals();

    /// @notice Thrown when the amount to be received is below the minimum acceptable amount.
    error SlippageExceeded(uint256 amountLD, uint256 minAmountLD);

    /* ============ View/Pure Functions ============ */

    /// @notice Retrieves interfaceID and the version of the OFT.
    /// @return interfaceId The interface ID.
    /// @return version     The version, indicating cross-chain compatibility of the message encoding.
    function oftVersion() external view returns (bytes4 interfaceId, uint64 version);

    /// @notice Retrieves the address of the token associated with the OFT.
    function token() external view returns (address);

    /// @notice Indicates whether the OFT contract requires ERC-20 approval to send tokens.
    /// @dev    Allows things like wallet implementers to determine integration requirements,
    ///         without understanding the underlying token implementation.
    function approvalRequired() external view returns (bool);

    /// @notice Retrieves the shared decimals of the OFT.
    function sharedDecimals() external view returns (uint8);

    /// @notice Provides the token-side quote for a send() operation.
    /// @param  sendParam     The parameters for the send operation.
    /// @return oftLimit      The OFT limit information.
    /// @return oftFeeDetails The details of OFT fees.
    /// @return oftReceipt    The OFT receipt information.
    function quoteOFT(
        SendParam calldata sendParam
    )
        external
        view
        returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt);

    /// @notice Provides a quote for the send() operation.
    /// @param  sendParam     The parameters for the send operation.
    /// @param  payInLzToken  Flag indicating whether the caller is paying in the LayerZero token.
    /// @return fee           The calculated LayerZero messaging fee from the send operation.
    function quoteSend(SendParam calldata sendParam, bool payInLzToken) external view returns (MessagingFee memory fee);

    /// @notice Executes the send() operation.
    /// @param  sendParam     The parameters for the send operation.
    /// @param  fee           The fee information supplied by the caller.
    /// @param  refundAddress The address to receive any excess funds from fees etc. on the source chain.
    /// @return receipt       The LayerZero messaging receipt from the send() operation.
    /// @return oftReceipt    The OFT receipt information.
    function send(
        SendParam calldata sendParam,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable returns (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt);
}
