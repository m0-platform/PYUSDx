// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.34;

import { TypeConverter } from "../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";
import { IERC20 } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlUpgradeable } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { MessagingFee, MessagingReceipt } from "../bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { IBridgeAdapter } from "../interfaces/IBridgeAdapter.sol";
import { IPortal } from "../interfaces/IPortal.sol";
import { IOFT, SendParam, OFTLimit, OFTReceipt, OFTFeeDetail } from "./interfaces/IOFT.sol";
import { IPortalOFTWrapper } from "./interfaces/IPortalOFTWrapper.sol";

abstract contract PortalOFTWrapperStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PortalOFTWrapper
    struct PortalOFTWrapperStorageStruct {
        /// @notice Maps a LayerZero Endpoint ID to the address of the token on that chain.
        mapping(uint32 destinationEid => bytes32 destinationToken) destinationToken;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.PortalOFTWrapper")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant PORTAL_OFT_WRAPPER_STORAGE_LOCATION =
        0x2ef942f2de2c4f4849a04a7b805b0f5a6916137facb4b88a2b036eb465681600;

    function _getPortalOFTWrapperStorageLocation() internal pure returns (PortalOFTWrapperStorageStruct storage $) {
        assembly {
            $.slot := PORTAL_OFT_WRAPPER_STORAGE_LOCATION
        }
    }
}

/// @title  PortalOFTWrapper
/// @author M0 Labs
/// @notice Send-only OFT facade exposing a single token (PYUSDX or a PYUSDX Extension) to
///         LayerZero Stargate. Sends are forwarded to the Portal, which burns on the source
///         chain and delivers through the pinned LayerZero bridge adapter. The wrapper takes no
///         part in the receive path: inbound transfers arrive through
///         `LayerZeroBridgeAdapter -> Portal.receiveMessage`, which mints PYUSDX or wraps into
///         the destination extension.
/// @dev    One wrapper instance represents exactly one token (`IOFT.token()`), so each token
///         exposed to Stargate needs its own wrapper instance; all instances share the same Portal.
///         The bridge adapter is pinned to the LayerZero adapter.
///
///         Identity semantics: the end user is not observable on this path. In the Stargate flow
///         the wrapper's caller is LayerZero's `LZMultiCall`, and downstream `Portal.msgSender()`
///         resolves to this wrapper, so extension hooks keyed on the original caller (e.g. the
///         freeze check in `_beforeUnwrap`) evaluate the wrapper address, not the user. This is
///         safe because user-bound compliance is enforced at the token-transfer layer, which
///         always sees the true holder: a frozen user's tokens cannot reach the wrapper at all.
///         Two invariants follow: the wrapper address must never be frozen on the token or any
///         extension (it would brick all sends and protects nothing, as the wrapper holds no
///         resting funds), and any future caller-keyed policy hook must classify this wrapper
///         as a router, like Portal and SwapFacility in the trusted-router registry.
contract PortalOFTWrapper is PortalOFTWrapperStorageLayout, AccessControlUpgradeable, IPortalOFTWrapper {
    using TypeConverter for address;
    using SafeERC20 for IERC20;

    /// @inheritdoc IPortalOFTWrapper
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @inheritdoc IPortalOFTWrapper
    address public immutable portal;

    /// @inheritdoc IPortalOFTWrapper
    address public immutable layerZeroBridgeAdapter;

    /// @inheritdoc IOFT
    address public immutable token;

    /// @inheritdoc IOFT
    /// @dev The Portal path is 1:1 with no dust conversion, so shared decimals equal local decimals.
    uint8 public immutable sharedDecimals;

    /// @notice Constructs the Implementation contract
    /// @dev    Sets immutable storage.
    /// @param  portal_                 The address of the Portal contract.
    /// @param  token_                  The address of the token (PYUSDX or PYUSDX Extension) this wrapper represents.
    /// @param  layerZeroBridgeAdapter_ The address of the LayerZero bridge adapter used for every send.
    constructor(address portal_, address token_, address layerZeroBridgeAdapter_) {
        _disableInitializers();

        if ((portal = portal_) == address(0)) revert ZeroPortal();
        if ((token = token_) == address(0)) revert ZeroToken();
        if ((layerZeroBridgeAdapter = layerZeroBridgeAdapter_) == address(0)) revert ZeroBridgeAdapter();

        sharedDecimals = IERC20Metadata(token_).decimals();
    }

    /// @inheritdoc IPortalOFTWrapper
    function initialize(address admin, address operator) external initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (operator == address(0)) revert ZeroOperator();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
    }

    /* ============ External Interactive Functions ============ */

    /// @inheritdoc IOFT
    /// @dev Forwards the send to `Portal.sendToken`, which burns the token on the source chain
    ///      and dispatches the message through the pinned LayerZero bridge adapter.
    ///      Supports both LayerZero Value Transfer API call sequences:
    ///      1. Fee path: the user approves the token to the LayerZero `TransferDelegate`, which moves
    ///         the send amount into this wrapper before `LZMultiCall` invokes `send`. The wrapper
    ///         already holds the tokens and nothing is pulled from the caller.
    ///      2. Direct path: the caller approves this wrapper and calls `send` directly; the
    ///         full send amount is pulled from the caller.
    ///      Tokens held by the wrapper are spendable by the next `send` caller, so they must only
    ///      be pushed here within the sending transaction — never transferred in advance.
    ///      `sendParam.extraOptions` is ignored: destination execution is configured by the
    ///      Portal's payload gas limits, and delivery can be retried with more gas if needed.
    ///      `sendParam.composeMsg` and `sendParam.oftCmd` are rejected rather than ignored:
    ///      the Portal path cannot execute them on the destination, and silently dropping a
    ///      compose message could strand funds on a composer recipient. Stargate always sends
    ///      all three empty.
    ///      `fee.nativeFee` is ignored in favor of `msg.value`; the excess over the actual bridge
    ///      fee is returned to `refundAddress` by the LayerZero Endpoint.
    function send(
        SendParam calldata sendParam,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable returns (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) {
        if (fee.lzTokenFee != 0) revert LayerZeroTokenUnsupported();

        _revertIfUnsupportedSendParam(sendParam);
        _revertIfInvalidAmount(sendParam);

        uint256 amount = sendParam.amountLD;
        bytes32 destinationToken = _getDestinationTokenOrRevert(sendParam.dstEid);
        uint32 destinationChainId = _getChainIdOrRevert(sendParam.dstEid);

        // Ensure the send amount is available in the wrapper: on the Stargate fee path it was
        // pre-pushed by TransferDelegate; otherwise pull the full amount from the caller.
        if (IERC20(token).balanceOf(address(this)) < amount) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        IERC20(token).forceApprove(portal, amount);

        bytes32 messageId = IPortal(portal).sendToken{ value: msg.value }(
            amount,
            token,
            destinationChainId,
            destinationToken,
            sendParam.to,
            refundAddress.toBytes32(),
            layerZeroBridgeAdapter
        );

        // NOTE: The Portal is bridge-agnostic and returns its own message ID rather than
        //       LayerZero-specific identifiers, so `guid` carries the Portal message ID
        //       and `nonce` is not populated.
        receipt = MessagingReceipt({
            guid: messageId,
            nonce: 0,
            fee: MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 })
        });
        oftReceipt = OFTReceipt({ amountSentLD: amount, amountReceivedLD: amount });

        emit OFTSent(messageId, sendParam.dstEid, msg.sender, amount, amount);
    }

    /* ============ Privileged Functions ============ */

    /// @inheritdoc IPortalOFTWrapper
    function setDestinationToken(uint32 destinationEid, bytes32 destinationToken) external onlyRole(OPERATOR_ROLE) {
        if (destinationEid == 0) revert ZeroDestinationEid();
        if (destinationToken == bytes32(0)) revert ZeroDestinationToken();

        PortalOFTWrapperStorageStruct storage $ = _getPortalOFTWrapperStorageLocation();

        if ($.destinationToken[destinationEid] == destinationToken) return;

        $.destinationToken[destinationEid] = destinationToken;
        emit DestinationTokenSet(destinationEid, destinationToken);
    }

    /// @inheritdoc IPortalOFTWrapper
    function removeDestinationToken(uint32 destinationEid) external onlyRole(OPERATOR_ROLE) {
        PortalOFTWrapperStorageStruct storage $ = _getPortalOFTWrapperStorageLocation();

        if ($.destinationToken[destinationEid] == bytes32(0)) return;

        delete $.destinationToken[destinationEid];
        emit DestinationTokenRemoved(destinationEid);
    }

    /* ============ External View/Pure Functions ============ */

    /// @inheritdoc IOFT
    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /// @inheritdoc IOFT
    /// @dev Returns `false` as required by Stargate flow: the send amount is
    ///      moved into the wrapper by the LayerZero `TransferDelegate` before `send` is invoked, so
    ///      no ERC-20 allowance on this wrapper is needed. Direct callers not using Stargate must
    ///      still approve this wrapper, since `send` pulls the send amount from the caller.
    function approvalRequired() external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IOFT
    /// @dev The Portal path applies no token-side fees and delivers amounts 1:1.
    ///      Amounts are encoded as uint128 in the Portal's cross-chain payload.
    function quoteOFT(
        SendParam calldata sendParam
    )
        external
        view
        returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt)
    {
        _revertIfUnsupportedSendParam(sendParam);
        _revertIfInvalidAmount(sendParam);
        _getDestinationTokenOrRevert(sendParam.dstEid);
        _getChainIdOrRevert(sendParam.dstEid);

        // The Portal rejects zero-amount sends (`ZeroAmount`), so the true minimum is 1;
        // the maximum is bound by the uint128 amount encoding of the Portal's payload.
        oftLimit = OFTLimit({ minAmountLD: 1, maxAmountLD: type(uint128).max });
        oftFeeDetails = new OFTFeeDetail[](0);
        oftReceipt = OFTReceipt({ amountSentLD: sendParam.amountLD, amountReceivedLD: sendParam.amountLD });
    }

    /// @inheritdoc IOFT
    /// @dev Paying in LayerZero token is unsupported since the Portal quotes and pays native fees only.
    function quoteSend(SendParam calldata sendParam, bool payInLzToken) external view returns (MessagingFee memory) {
        if (payInLzToken) revert LayerZeroTokenUnsupported();

        _revertIfUnsupportedSendParam(sendParam);
        _revertIfInvalidAmount(sendParam);
        _getDestinationTokenOrRevert(sendParam.dstEid);
        uint32 destinationChainId = _getChainIdOrRevert(sendParam.dstEid);

        return
            MessagingFee({
                nativeFee: IPortal(portal).quote(destinationChainId, layerZeroBridgeAdapter),
                lzTokenFee: 0
            });
    }

    /// @inheritdoc IPortalOFTWrapper
    function getDestinationToken(uint32 destinationEid) external view returns (bytes32 destinationToken) {
        return _getPortalOFTWrapperStorageLocation().destinationToken[destinationEid];
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev Returns the destination token for the given LayerZero Endpoint ID or reverts if not configured.
    function _getDestinationTokenOrRevert(uint32 destinationEid) internal view returns (bytes32 destinationToken) {
        destinationToken = _getPortalOFTWrapperStorageLocation().destinationToken[destinationEid];
        if (destinationToken == bytes32(0)) revert UnsupportedDestinationEid(destinationEid);
    }

    /// @dev Returns the M0 internal chain ID for the given LayerZero Endpoint ID, derived from the
    ///      pinned bridge adapter's mapping so the wrapper's routing cannot diverge from the adapter's.
    function _getChainIdOrRevert(uint32 destinationEid) internal view returns (uint32 destinationChainId) {
        destinationChainId = IBridgeAdapter(layerZeroBridgeAdapter).getChainId(destinationEid);
        if (destinationChainId == 0) revert UnsupportedDestinationEid(destinationEid);
    }

    /// @dev The Portal path is 1:1, so the amount received equals the amount sent, and the
    ///      amount must fit the uint128 encoding of the Portal's cross-chain payload.
    ///      Applied to quotes and sends alike, mirroring the canonical OFT's `_debitView`,
    ///      so quotes never accept an amount that `send` would reject.
    function _revertIfInvalidAmount(SendParam calldata sendParam) internal pure {
        if (sendParam.amountLD > type(uint128).max) revert TypeConverter.Uint128Overflow();
        if (sendParam.amountLD < sendParam.minAmountLD) {
            revert SlippageExceeded(sendParam.amountLD, sendParam.minAmountLD);
        }
    }

    /// @dev Rejects send parameters whose semantics the Portal path cannot honor. A compose
    ///      message or OFT command accepted here would be silently dropped on the destination,
    ///      so fail loudly instead. Applied to quotes and sends alike, so quotes never accept
    ///      parameters that `send` would reject.
    function _revertIfUnsupportedSendParam(SendParam calldata sendParam) internal pure {
        if (sendParam.composeMsg.length != 0) revert ComposeMsgUnsupported();
        if (sendParam.oftCmd.length != 0) revert OFTCmdUnsupported();
    }
}
