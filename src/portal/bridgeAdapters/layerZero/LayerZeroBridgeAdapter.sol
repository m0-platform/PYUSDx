// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.34;

import { TypeConverter } from "../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { BridgeAdapter } from "../BridgeAdapter.sol";
import { IBridgeAdapter } from "../../interfaces/IBridgeAdapter.sol";
import { ILayerZeroBridgeAdapter } from "./interfaces/ILayerZeroBridgeAdapter.sol";
import { ILayerZeroReceiver } from "./interfaces/ILayerZeroReceiver.sol";
import { Origin, MessagingParams, MessagingFee, ILayerZeroEndpointV2 } from "./interfaces/ILayerZeroEndpointV2.sol";
import { OptionsBuilder } from "./libraries/OptionsBuilder.sol";
import { IPortal } from "../../interfaces/IPortal.sol";

/// @title  LayerZeroBridgeAdapter
/// @author M0 Labs
/// @notice Bridge adapter implementation for LayerZero V2.
contract LayerZeroBridgeAdapter is BridgeAdapter, ILayerZeroBridgeAdapter {
    using TypeConverter for *;
    using OptionsBuilder for bytes;

    /// @inheritdoc ILayerZeroBridgeAdapter
    address public immutable endpoint;

    /// @notice Constructs the LayerZeroBridgeAdapter.
    /// @dev    Sets immutable storage and disables initializers for the implementation contract.
    /// @param  endpoint_ The LayerZero Endpoint V2 address.
    /// @param  portal_   The Portal contract address.
    constructor(address endpoint_, address portal_) BridgeAdapter(portal_) {
        if (endpoint_ == address(0)) revert ZeroEndpoint();
        endpoint = endpoint_;
    }

    /// @inheritdoc IBridgeAdapter
    function initialize(address admin, address operator) external initializer {
        _initialize(admin, operator);

        // Sets the operator as a default delegate.
        // The delegate is authorized to configure LayerZero settings, clear, skip messages, etc.
        // by interacting directly with LayerZero Endpoint on behalf of this contract.
        ILayerZeroEndpointV2(endpoint).setDelegate(operator);
    }

    /* ============ External Interactive Functions ============ */

    /// @inheritdoc IBridgeAdapter
    function sendMessage(
        uint32 destinationChainId,
        uint256 gasLimit,
        uint256 composedMessageGasLimit,
        bytes32 refundAddress,
        bytes memory payload
    ) external payable {
        _revertIfNotPortal();

        bytes memory options = _buildOptions(gasLimit, composedMessageGasLimit);
        bytes32 destinationPeer = _getPeerOrRevert(destinationChainId);
        uint32 destinationEid = _getLayerZeroEndpointIdOrRevert(destinationChainId);

        // NOTE: The transaction reverts if msg.value isn't enough to cover the fee.
        //       If msg.value is greater than the required fee, the excess is sent to the refund address.
        ILayerZeroEndpointV2(endpoint).send{ value: msg.value }(
            MessagingParams(destinationEid, destinationPeer, payload, options, false),
            refundAddress.toAddress()
        );
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        Origin calldata origin,
        bytes32 lzMessageGuid,
        bytes calldata payload,
        address /* executor */,
        bytes calldata /* extraData */
    ) external payable {
        if (msg.sender != endpoint) revert NotEndpoint();
        // Convert LayerZero Endpoint ID to internal chain ID
        uint32 sourceChainId = _getChainIdOrRevert(origin.srcEid);
        if (origin.sender != _getPeerOrRevert(sourceChainId)) revert UnsupportedSender(origin.sender);

        (address composer, bytes memory composedMessage) = IPortal(portal).receiveMessage(sourceChainId, payload);

        // Forward the composed message to the LayerZero Endpoint, which will deliver it
        // to the composer contract via `lzCompose`.
        if (composer != address(0) && composedMessage.length > 0) {
            ILayerZeroEndpointV2(endpoint).sendCompose(composer, lzMessageGuid, 0, composedMessage);
        }
    }

    /// @inheritdoc ILayerZeroBridgeAdapter
    function setDelegate(address delegate) external onlyRole(OPERATOR_ROLE) {
        ILayerZeroEndpointV2(endpoint).setDelegate(delegate);
    }

    /* ============ Internal Functions ============ */

    /// @dev Clears the LayerZero Endpoint delegate when the OPERATOR_ROLE is revoked from the current delegate.
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        bool revoked = super._revokeRole(role, account);

        if (revoked && role == OPERATOR_ROLE) {
            if (ILayerZeroEndpointV2(endpoint).delegates(address(this)) == account) {
                ILayerZeroEndpointV2(endpoint).setDelegate(address(0));
            }
        }

        return revoked;
    }

    /* ============ External View/Pure Functions ============ */

    /// @inheritdoc IBridgeAdapter
    function quote(
        uint32 destinationChainId,
        uint256 gasLimit,
        uint256 composedMessageGasLimit,
        bytes memory payload
    ) external view returns (uint256 fee) {
        bytes memory options = _buildOptions(gasLimit, composedMessageGasLimit);
        uint32 destinationEid = _getLayerZeroEndpointIdOrRevert(destinationChainId);
        bytes32 destinationPeer = _getPeerOrRevert(destinationChainId);

        MessagingFee memory messagingFee = ILayerZeroEndpointV2(endpoint).quote(
            MessagingParams(destinationEid, destinationPeer, payload, options, false),
            address(this)
        );
        return messagingFee.nativeFee;
    }

    /// @inheritdoc ILayerZeroReceiver
    function allowInitializePath(Origin calldata origin) external view returns (bool) {
        // The path is considered initialized if the source endpoint ID maps to a known chain
        // and the sender matches the configured peer for that chain.
        // Reference:
        // https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/oapp/contracts/oapp/OAppReceiver.sol#L63
        uint32 chainId = _getChainId(origin.srcEid);
        if (chainId == 0) return false;
        bytes32 peer = _getPeer(chainId);
        if (peer == bytes32(0)) return false;
        return peer == origin.sender;
    }

    /// @inheritdoc ILayerZeroReceiver
    function nextNonce(uint32 /* srcEid */, bytes32 /* sender */) external pure returns (uint64) {
        // Hardcode to 0 for unordered execution.
        return 0;
    }

    /* ============ Private View/Pure Functions ============ */

    /// @notice Builds LayerZero execution options with the specified gas limit.
    /// @param  gasLimit                The gas limit for destination execution.
    /// @param  composedMessageGasLimit The gas limit for the composed message execution on the destination chain.
    /// @return options                 The encoded options bytes.
    function _buildOptions(
        uint256 gasLimit,
        uint256 composedMessageGasLimit
    ) internal pure returns (bytes memory options) {
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit.toUint128(), 0);
        if (composedMessageGasLimit > 0) {
            options = options.addExecutorLzComposeOption(0, composedMessageGasLimit.toUint128(), 0);
        }
    }

    /// @notice Returns LayerZero Endpoint Id by chain Id
    /// @dev    https://docs.layerzero.network/v2/deployments/deployed-contracts?stages=mainnet
    function _getLayerZeroEndpointIdOrRevert(uint32 chainId) private view returns (uint32) {
        return _getBridgeChainIdOrRevert(chainId).toUint32();
    }
}
