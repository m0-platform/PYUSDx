// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.34;

import { TypeConverter } from "../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";

import { IBridgeAdapter } from "./interfaces/IBridgeAdapter.sol";
import { IPortal } from "./interfaces/IPortal.sol";
import { ISwapFacility } from "../swap/interfaces/ISwapFacility.sol";
import { IPYUSDX } from "../IPYUSDX.sol";
import { ReentrancyLock } from "./ReentrancyLock.sol";
import { PayloadType, PayloadEncoder } from "./libraries/PayloadEncoder.sol";

struct ChainConfig {
    /// @notice Default bridge adapter for each remote chain used if no bridge adapter is specified.
    address defaultBridgeAdapter;
    /// @notice Supported bridge adapters for each remote chain.
    mapping(address bridgeAdapter => bool supported) supportedBridgeAdapter;
    /// @notice Gas limit required to process different types of payload on destination chains.
    /// @dev    Initially only the `TokenTransfer` payload type is supported.
    ///         Using a mapping to allow extensibility for additional payload types in the future.
    mapping(PayloadType payloadType => uint256 gasLimit) payloadGasLimit;
}

abstract contract PortalStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.Portal
    struct PortalStorageStruct {
        /// @notice Ensures the uniqueness of each cross-chain message.
        uint256 nonce;
        /// @notice Configuration required to send cross-chain messages to the remote chain.
        mapping(uint32 chainId => ChainConfig) remoteChainConfig;
        /// @notice Indicates whether a message with a given hash has been processed.
        mapping(bytes32 messageId => bool) processedMessages;
        /// @notice The address that receives PYUSDX or PYUSDX Extension on the destination chain when the intended recipient is frozen.
        address fallbackRecipient;
        /// @notice Indicates whether sending cross-chain messages is paused.
        bool sendPaused;
        /// @notice Indicates whether receiving cross-chain messages is paused.
        bool receivePaused;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.Portal")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant PORTAL_STORAGE_LOCATION = 0xc28186249f0e66be857064e66a873ce85cfd996b5352867e3f7c1d7931e67d00;

    function _getPortalStorageLocation() internal pure returns (PortalStorageStruct storage $) {
        assembly {
            $.slot := PORTAL_STORAGE_LOCATION
        }
    }
}

contract Portal is PortalStorageLayout, AccessControlUpgradeable, ReentrancyLock, IPortal {
    using TypeConverter for *;
    using PayloadEncoder for bytes;
    using SafeERC20 for IERC20;

    /// @inheritdoc IPortal
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @inheritdoc IPortal
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @inheritdoc IPortal
    address public immutable pyusdx;

    /// @inheritdoc IPortal
    address public immutable swapFacility;

    /// @dev Modifier to make a function callable only when sending messages is not paused.
    modifier whenSendNotPaused() {
        if (sendPaused()) revert SendingPaused();
        _;
    }

    /// @dev Modifier to make a function callable only when receiving messages is not paused.
    modifier whenReceiveNotPaused() {
        if (receivePaused()) revert ReceivingPaused();
        _;
    }

    /// @notice Constructs the Implementation contract
    /// @dev    Sets immutable storage.
    /// @param  pyusdx_       The address of PYUSDX token.
    /// @param  swapFacility_ The address of Swap Facility.
    constructor(address pyusdx_, address swapFacility_) {
        _disableInitializers();

        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDXToken();
        if ((swapFacility = swapFacility_) == address(0)) revert ZeroSwapFacility();
    }

    /// @notice Initializes the Proxy's storage
    /// @param  admin              The address of the admin.
    /// @param  pauser             The address of the pauser.
    /// @param  operator           The address of the operator.
    /// @param  fallbackRecipient_ The address that receives PYUSDX or PYUSDX Extension on the destination chain when the intended recipient is frozen.
    function initialize(
        address admin,
        address pauser,
        address operator,
        address fallbackRecipient_
    ) external initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (pauser == address(0)) revert ZeroPauser();
        if (operator == address(0)) revert ZeroOperator();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(OPERATOR_ROLE, operator);
        _setFallbackRecipient(fallbackRecipient_);
    }

    /* ============ External Interactive Functions ============ */

    /// @inheritdoc IPortal
    function sendToken(
        uint256 amount,
        address sourceToken,
        uint32 destinationChainId,
        bytes32 destinationToken,
        bytes32 recipient,
        bytes32 refundAddress
    ) external payable whenSendNotPaused whenNotLocked returns (bytes32 messageId) {
        return
            _sendToken(
                amount,
                sourceToken,
                destinationChainId,
                destinationToken,
                recipient,
                refundAddress,
                defaultBridgeAdapter(destinationChainId)
            );
    }

    /// @inheritdoc IPortal
    function sendToken(
        uint256 amount,
        address sourceToken,
        uint32 destinationChainId,
        bytes32 destinationToken,
        bytes32 recipient,
        bytes32 refundAddress,
        address bridgeAdapter
    ) external payable whenSendNotPaused whenNotLocked returns (bytes32 messageId) {
        return
            _sendToken(
                amount,
                sourceToken,
                destinationChainId,
                destinationToken,
                recipient,
                refundAddress,
                bridgeAdapter
            );
    }

    /// @inheritdoc IPortal
    function receiveMessage(uint32 sourceChainId, bytes calldata payload) external whenReceiveNotPaused whenNotLocked {
        _revertIfUnsupportedBridgeAdapter(sourceChainId, msg.sender);

        (
            uint32 targetChainId,
            address targetBridgeAdapter,
            bytes32 messageId,
            uint256 amount,
            address destinationToken,
            bytes32 sender,
            address recipient
        ) = payload.decodeTokenTransfer();
        PortalStorageStruct storage $ = _getPortalStorageLocation();

        // NOTE: Defense-in-depth checks.
        //       These checks are enforced at the application layer regardless of what the
        //       underlying messaging protocol guarantees, so behavior is consistent across
        //       adapters and resilient to changes of the messaging provider.
        if (targetChainId != currentChainId()) revert InvalidTargetChain(targetChainId);
        if (targetBridgeAdapter != msg.sender) revert InvalidTargetBridgeAdapter(targetBridgeAdapter);
        if ($.processedMessages[messageId]) revert MessageAlreadyProcessed(messageId);
        $.processedMessages[messageId] = true;

        // NOTE: Only the PYUSDX freeze list is checked here. If the recipient is frozen on PYUSDX,
        //       tokens are redirected to the fallback recipient to prevent a revert on mint.
        //       If the recipient is frozen on a PYUSDX Extension but not on PYUSDX, the wrap via
        //       SwapFacility will fail and the recipient will receive PYUSDX directly (see WrapFailed).
        //       In reality, we expect recipients to be frozen both on PYUSDX and all PYUSDX Extensions.
        if (IFreezable(pyusdx).isFrozen(recipient)) {
            address fallbackRecipient_ = fallbackRecipient();
            emit RedirectedToFallbackRecipient(
                sourceChainId,
                destinationToken,
                sender,
                recipient,
                amount,
                messageId,
                fallbackRecipient_
            );
            recipient = fallbackRecipient_;
        }

        emit TokenReceived(sourceChainId, destinationToken, sender, recipient, amount, messageId);

        if (destinationToken == pyusdx) {
            // mints PYUSDX Token to the recipient
            IPYUSDX(pyusdx).mint(recipient, amount);
        } else {
            // mints PYUSDX Token to the Portal
            IPYUSDX(pyusdx).mint(address(this), amount);

            // wraps PYUSDX token to the destination token and transfers it to the recipient
            _wrap(destinationToken, recipient, amount);
        }
    }

    /* ============ Privileged Functions ============ */

    /// @inheritdoc IPortal
    function setDefaultBridgeAdapter(
        uint32 destinationChainId,
        address bridgeAdapter
    ) external onlyRole(OPERATOR_ROLE) {
        _revertIfInvalidDestinationChain(destinationChainId);
        _revertIfZeroBridgeAdapter(bridgeAdapter);

        ChainConfig storage remoteChainConfig = _getPortalStorageLocation().remoteChainConfig[destinationChainId];

        if (remoteChainConfig.defaultBridgeAdapter == bridgeAdapter) return;

        // If the bridge adapter isn't already supported, add it to the supported adapters list
        if (!remoteChainConfig.supportedBridgeAdapter[bridgeAdapter]) {
            remoteChainConfig.supportedBridgeAdapter[bridgeAdapter] = true;
            emit SupportedBridgeAdapterSet(destinationChainId, bridgeAdapter, true);
        }
        remoteChainConfig.defaultBridgeAdapter = bridgeAdapter;
        emit DefaultBridgeAdapterSet(destinationChainId, bridgeAdapter);
    }

    /// @inheritdoc IPortal
    function setSupportedBridgeAdapter(
        uint32 destinationChainId,
        address bridgeAdapter,
        bool supported
    ) external onlyRole(OPERATOR_ROLE) {
        _revertIfInvalidDestinationChain(destinationChainId);
        _revertIfZeroBridgeAdapter(bridgeAdapter);

        ChainConfig storage remoteChainConfig = _getPortalStorageLocation().remoteChainConfig[destinationChainId];

        if (remoteChainConfig.supportedBridgeAdapter[bridgeAdapter] == supported) return;

        // If the bridge adapter being removed is currently set as the default, clear the default adapter
        if (!supported && remoteChainConfig.defaultBridgeAdapter == bridgeAdapter) {
            remoteChainConfig.defaultBridgeAdapter = address(0);
            emit DefaultBridgeAdapterSet(destinationChainId, address(0));
        }

        remoteChainConfig.supportedBridgeAdapter[bridgeAdapter] = supported;
        emit SupportedBridgeAdapterSet(destinationChainId, bridgeAdapter, supported);
    }

    /// @inheritdoc IPortal
    function setPayloadGasLimit(uint32 destinationChainId, uint256 gasLimit) external onlyRole(OPERATOR_ROLE) {
        _revertIfInvalidDestinationChain(destinationChainId);
        ChainConfig storage remoteChainConfig = _getPortalStorageLocation().remoteChainConfig[destinationChainId];

        // NOTE: Currently, only one payload type is supported.
        // If more payload types are added in the future,
        // this function can be extended to set gas limit for each payload type.
        PayloadType payloadType = PayloadType.TokenTransfer;

        if (remoteChainConfig.payloadGasLimit[payloadType] == gasLimit) return;

        remoteChainConfig.payloadGasLimit[payloadType] = gasLimit;
        emit PayloadGasLimitSet(destinationChainId, gasLimit);
    }

    /// @inheritdoc IPortal
    /// @dev Gated by `DEFAULT_ADMIN_ROLE` rather than `OPERATOR_ROLE` because the fallback recipient
    ///      custodies inbound PYUSDX redirected from frozen accounts and must be controlled by the highest-trust role.
    function setFallbackRecipient(address fallbackRecipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFallbackRecipient(fallbackRecipient_);
    }

    /// @inheritdoc IPortal
    function pauseSend() public onlyRole(PAUSER_ROLE) {
        _pauseSend();
    }

    /// @inheritdoc IPortal
    function unpauseSend() public onlyRole(PAUSER_ROLE) {
        _unpauseSend();
    }

    /// @inheritdoc IPortal
    function pauseReceive() public onlyRole(PAUSER_ROLE) {
        _pauseReceive();
    }

    /// @inheritdoc IPortal
    function unpauseReceive() public onlyRole(PAUSER_ROLE) {
        _unpauseReceive();
    }

    /// @inheritdoc IPortal
    function pauseAll() public onlyRole(PAUSER_ROLE) {
        _pauseSend();
        _pauseReceive();
    }

    /// @inheritdoc IPortal
    function unpauseAll() public onlyRole(PAUSER_ROLE) {
        _unpauseSend();
        _unpauseReceive();
    }

    /* ============ External View/Pure Functions ============ */

    /// @inheritdoc IPortal
    function fallbackRecipient() public view returns (address) {
        return _getPortalStorageLocation().fallbackRecipient;
    }

    /// @inheritdoc IPortal
    /// @dev Using block.chainid directly to prevent a replay attack if a chain undergoes a contentious hard fork.
    function currentChainId() public view returns (uint32) {
        // NOTE: For most EVM chains, ID fits into uint32
        return block.chainid.toUint32();
    }

    /// @inheritdoc IPortal
    function getNonce() external view returns (uint256) {
        PortalStorageStruct storage $ = _getPortalStorageLocation();
        return $.nonce;
    }

    /// @inheritdoc IPortal
    function defaultBridgeAdapter(uint32 destinationChainId) public view returns (address) {
        PortalStorageStruct storage $ = _getPortalStorageLocation();
        return $.remoteChainConfig[destinationChainId].defaultBridgeAdapter;
    }

    /// @inheritdoc IPortal
    function supportedBridgeAdapter(uint32 destinationChainId, address bridgeAdapter) public view returns (bool) {
        PortalStorageStruct storage $ = _getPortalStorageLocation();
        return $.remoteChainConfig[destinationChainId].supportedBridgeAdapter[bridgeAdapter];
    }

    /// @inheritdoc IPortal
    function payloadGasLimit(uint32 destinationChainId) public view returns (uint256) {
        PortalStorageStruct storage $ = _getPortalStorageLocation();
        // NOTE: Currently, only one payload type is supported.
        // If more payload types are added in the future,
        // this function can be extended to query gas limit for each payload type.
        PayloadType payloadType = PayloadType.TokenTransfer;
        return $.remoteChainConfig[destinationChainId].payloadGasLimit[payloadType];
    }

    /// @inheritdoc IPortal
    function msgSender() public view returns (address) {
        return _locker;
    }

    /// @inheritdoc IPortal
    function quote(uint32 destinationChainId) external view returns (uint256) {
        return _quote(destinationChainId, defaultBridgeAdapter(destinationChainId));
    }

    /// @inheritdoc IPortal
    function quote(uint32 destinationChainId, address bridgeAdapter) external view returns (uint256) {
        return _quote(destinationChainId, bridgeAdapter);
    }

    /// @inheritdoc IPortal
    function sendPaused() public view returns (bool) {
        return _getPortalStorageLocation().sendPaused;
    }

    /// @inheritdoc IPortal
    function receivePaused() public view returns (bool) {
        return _getPortalStorageLocation().receivePaused;
    }

    /* ============ Internal Interactive Functions ============ */

    /// @dev Sends the specified payload to the destination chain.
    function _sendMessage(
        uint32 destinationChainId,
        bytes32 refundAddress,
        bytes memory payload,
        address bridgeAdapter
    ) internal {
        IBridgeAdapter(bridgeAdapter).sendMessage{ value: msg.value }(
            destinationChainId,
            _getPayloadGasLimitOrRevert(destinationChainId),
            refundAddress,
            payload
        );
    }

    /// @dev Transfers PYUSDX Token or PYUSDX Extension to the destination chain.
    function _sendToken(
        uint256 amount,
        address sourceToken,
        uint32 destinationChainId,
        bytes32 destinationToken,
        bytes32 recipient,
        bytes32 refundAddress,
        address bridgeAdapter
    ) internal returns (bytes32 messageId) {
        _revertIfZeroAmount(amount);
        _revertIfZeroRefundAddress(refundAddress);
        _revertIfZeroSourceToken(sourceToken);
        _revertIfZeroDestinationToken(destinationToken);
        _revertIfZeroRecipient(recipient);
        _revertIfUnsupportedBridgeAdapter(destinationChainId, bridgeAdapter);

        // Transfer and if the source token isn't PYUSDX token, unwrap it to PYUSDX token.
        _transferAndUnwrap(sourceToken, amount);

        // Burn PYUSDX tokens
        IPYUSDX(pyusdx).burn(address(this), amount);

        bytes memory payload;
        (payload, messageId) = _createTokenTransferPayload(
            amount,
            destinationChainId,
            destinationToken,
            msg.sender,
            recipient,
            bridgeAdapter
        );

        _sendMessage(destinationChainId, refundAddress, payload, bridgeAdapter);

        emit TokenSent(
            sourceToken,
            destinationChainId,
            destinationToken,
            msg.sender,
            recipient,
            amount,
            bridgeAdapter,
            messageId
        );
    }

    /// @dev Transfers the specified amount of `sourceToken` from the sender to the Portal
    ///      If the source token is not PYUSDX token, it unwraps it to PYUSDX token.
    ///      Reverts if the actual amount received is less than the specified amount.
    /// @param sourceToken     The address of the source token.
    /// @param specifiedAmount The amount specified by the sender to transfer.
    function _transferAndUnwrap(address sourceToken, uint256 specifiedAmount) internal {
        uint256 balanceBefore = _pyusdxBalanceOf(address(this));
        uint256 sourceTokenBalanceBefore = _tokenBalanceOf(sourceToken, address(this));

        // Transfer source token from the sender
        IERC20(sourceToken).safeTransferFrom(msg.sender, address(this), specifiedAmount);
        uint256 actualAmount;

        // If the source token isn't PYUSDX token, unwrap it
        if (sourceToken != pyusdx) {
            // The actual amount of the source tokens that Portal received from the sender.
            actualAmount = _tokenBalanceOf(sourceToken, address(this)) - sourceTokenBalanceBefore;

            // SwapFacility doesn't support fee-on-transfer tokens.
            // Revert if the actual amount received is less than the specified amount.
            if (actualAmount < specifiedAmount) revert InsufficientAmountReceived(specifiedAmount, actualAmount);

            IERC20(sourceToken).forceApprove(swapFacility, actualAmount);
            ISwapFacility(swapFacility).swapOut(sourceToken, actualAmount, address(this));
        }

        // The actual amount of PYUSDX tokens that Portal received from the SwapFacility.
        actualAmount = _pyusdxBalanceOf(address(this)) - balanceBefore;

        // Portal doesn't support fee-on-transfer tokens.
        // Revert if the actual amount received is less than the specified amount.
        if (actualAmount < specifiedAmount) revert InsufficientAmountReceived(specifiedAmount, actualAmount);
    }

    /// @dev Creates token transfer payload.
    /// @return payload   The encoded payload.
    /// @return messageId The message ID for the cross-chain transfer.
    function _createTokenTransferPayload(
        uint256 transferAmount,
        uint32 destinationChainId,
        bytes32 destinationToken,
        address sender,
        bytes32 recipient,
        address bridgeAdapter
    ) internal returns (bytes memory payload, bytes32 messageId) {
        messageId = _getMessageId(destinationChainId);
        bytes32 destinationPeer = IBridgeAdapter(bridgeAdapter).getPeer(destinationChainId);
        payload = PayloadEncoder.encodeTokenTransfer(
            destinationChainId,
            destinationPeer,
            messageId,
            transferAmount,
            destinationToken,
            sender,
            recipient
        );
    }

    /// @dev   Wraps PYUSDX token to the token specified by `destinationToken`.
    ///        If wrapping fails transfers PYUSDX token to `recipient`.
    /// @param destinationToken The address of the Extension token.
    /// @param recipient        The account to receive wrapped token.
    /// @param amount           The amount to wrap.
    function _wrap(address destinationToken, address recipient, uint256 amount) internal {
        IERC20(pyusdx).approve(swapFacility, amount);

        // Attempt to wrap PYUSDX token
        // NOTE: the call might fail with out-of-gas exception
        //       even if the destination token is the valid wrapped PYUSDX token.
        //       Recipients must support both PYUSDX and wrapped PYUSDX transfers.
        (bool success, ) = swapFacility.call(
            abi.encodeCall(ISwapFacility.swapIn, (destinationToken, amount, recipient))
        );

        if (!success) {
            emit WrapFailed(destinationToken, recipient, amount);
            // Reset approval to prevent a potential double-spend attack
            IERC20(pyusdx).approve(swapFacility, 0);
            // Transfer PYUSDX token to the recipient
            IERC20(pyusdx).transfer(recipient, amount);
        }
    }

    /// @dev Pauses sending cross-chain messages.
    function _pauseSend() internal {
        PortalStorageStruct storage $ = _getPortalStorageLocation();
        if ($.sendPaused) return;
        $.sendPaused = true;
        emit SendPaused();
    }

    /// @dev Unpauses sending cross-chain messages.
    function _unpauseSend() internal {
        PortalStorageStruct storage $ = _getPortalStorageLocation();
        if (!$.sendPaused) return;
        $.sendPaused = false;
        emit SendUnpaused();
    }

    /// @dev Pauses receiving cross-chain messages.
    function _pauseReceive() internal {
        PortalStorageStruct storage $ = _getPortalStorageLocation();
        if ($.receivePaused) return;
        $.receivePaused = true;
        emit ReceivePaused();
    }

    /// @dev Unpauses receiving cross-chain messages.
    function _unpauseReceive() internal {
        PortalStorageStruct storage $ = _getPortalStorageLocation();
        if (!$.receivePaused) return;
        $.receivePaused = false;
        emit ReceiveUnpaused();
    }

    /// @dev Sets the address that receives PYUSDX or PYUSDX Extension on the destination chain when the intended recipient is frozen.
    function _setFallbackRecipient(address fallbackRecipient_) internal {
        if (fallbackRecipient_ == address(0)) revert ZeroFallbackRecipient();

        PortalStorageStruct storage $ = _getPortalStorageLocation();
        if ($.fallbackRecipient == fallbackRecipient_) return;

        $.fallbackRecipient = fallbackRecipient_;
        emit FallbackRecipientSet(fallbackRecipient_);
    }

    /// @dev Generates a unique across all chains message ID.
    /// @param destinationChainId The ID of the destination chain.
    function _getMessageId(uint32 destinationChainId) internal returns (bytes32) {
        return keccak256(abi.encode(currentChainId(), destinationChainId, _getPortalStorageLocation().nonce++));
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev Returns the fee for delivering a cross-chain message.
    /// @param  destinationChainId The ID of the destination chain.
    /// @param  bridgeAdapter      The address of the bridge adapter.
    function _quote(uint32 destinationChainId, address bridgeAdapter) internal view returns (uint256) {
        _revertIfUnsupportedBridgeAdapter(destinationChainId, bridgeAdapter);

        uint256 gasLimit = _getPayloadGasLimitOrRevert(destinationChainId);

        // NOTE: For quoting delivery fee, the content of the message doesn’t matter,
        //       only the destination chain, gas limit required to process the message on the destination
        //       and, for some protocols, payload size is relevant.
        bytes memory payload = PayloadEncoder.generateEmptyPayload();

        return IBridgeAdapter(bridgeAdapter).quote(destinationChainId, gasLimit, payload);
    }

    /// @dev Returns the gas limit for the specified payload type on the destination chain.
    ///      Reverts if the gas limit is not set.
    function _getPayloadGasLimitOrRevert(uint32 destinationChainId) internal view returns (uint256) {
        uint256 gasLimit = payloadGasLimit(destinationChainId);
        if (gasLimit == 0) revert PayloadGasLimitNotSet(destinationChainId);
        return gasLimit;
    }

    /// @dev Reverts if `amount` is zero.
    function _revertIfZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /// @dev Reverts if `refundAddress` is zero address.
    function _revertIfZeroRefundAddress(bytes32 refundAddress) internal pure {
        if (refundAddress == bytes32(0)) revert ZeroRefundAddress();
    }

    /// @dev Reverts if `bridgeAdapter` is zero address.
    function _revertIfZeroBridgeAdapter(address bridgeAdapter) internal pure {
        if (bridgeAdapter == address(0)) revert ZeroBridgeAdapter();
    }

    /// @dev Reverts if `destinationChainId` is the current chain.
    function _revertIfInvalidDestinationChain(uint32 destinationChainId) internal view {
        if (destinationChainId == currentChainId()) revert InvalidDestinationChain(destinationChainId);
    }

    /// @dev Reverts if `sourceToken` is zero address.
    function _revertIfZeroSourceToken(address sourceToken) internal pure {
        if (sourceToken == address(0)) revert ZeroSourceToken();
    }

    /// @dev Reverts if `destinationToken` is zero.
    function _revertIfZeroDestinationToken(bytes32 destinationToken) internal pure {
        if (destinationToken == bytes32(0)) revert ZeroDestinationToken();
    }

    /// @dev Reverts if `recipient` is zero.
    function _revertIfZeroRecipient(bytes32 recipient) internal pure {
        if (recipient == bytes32(0)) revert ZeroRecipient();
    }

    /// @dev Reverts if `bridgeAdapter` is not supported for `chainId`.
    function _revertIfUnsupportedBridgeAdapter(uint32 chainId, address bridgeAdapter) internal view {
        if (!supportedBridgeAdapter(chainId, bridgeAdapter)) revert UnsupportedBridgeAdapter(chainId, bridgeAdapter);
    }

    /// @dev Returns PYUSDX balance of `account`.
    function _pyusdxBalanceOf(address account) internal view returns (uint256) {
        return IERC20(pyusdx).balanceOf(account);
    }

    /// @dev Returns the `token` balance of `account`.
    function _tokenBalanceOf(address token, address account) internal view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }
}
