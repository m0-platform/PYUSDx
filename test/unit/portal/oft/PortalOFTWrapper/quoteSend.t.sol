// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { MessagingFee } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";
import { IOFT, SendParam } from "../../../../../src/portal/oft/interfaces/IOFT.sol";

import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

contract QuoteSendUnitTest is PortalOFTWrapperUnitTestBase {
    uint256 internal constant AMOUNT = 10e6;

    function test_quoteSend() external view {
        MessagingFee memory fee = wrapper.quoteSend(_sendParam(AMOUNT, AMOUNT), false);

        assertEq(fee.nativeFee, FEE);
        assertEq(fee.lzTokenFee, 0);
    }

    function testFuzz_quoteSend(uint256 expectedFee) external {
        vm.assume(expectedFee < 1 ether);
        bridgeAdapter.setQuote(expectedFee);

        assertEq(wrapper.quoteSend(_sendParam(AMOUNT, AMOUNT), false).nativeFee, expectedFee);
    }

    function test_quoteSend_extensionWrapper() external view {
        MessagingFee memory fee = extensionWrapper.quoteSend(_sendParam(AMOUNT, AMOUNT), false);

        assertEq(fee.nativeFee, FEE);
        assertEq(fee.lzTokenFee, 0);
    }

    function test_quoteSend_revertsIfSlippageExceeded() external {
        vm.expectRevert(abi.encodeWithSelector(IOFT.SlippageExceeded.selector, AMOUNT, AMOUNT + 1));
        wrapper.quoteSend(_sendParam(AMOUNT, AMOUNT + 1), false);
    }

    function test_quoteSend_revertsIfAmountExceedsUint128() external {
        vm.expectRevert(TypeConverter.Uint128Overflow.selector);
        wrapper.quoteSend(_sendParam(uint256(type(uint128).max) + 1, 0), false);
    }

    function test_quoteSend_revertsIfEidUnknownToBridgeAdapter() external {
        // A destination token is configured, but the bridge adapter has no chain ID mapping
        // for the Endpoint ID, so the chain ID derivation fails.
        uint32 unknownEid = 30101;

        vm.prank(operator);
        wrapper.setDestinationToken(unknownEid, peerPYUSDX);

        SendParam memory sendParam = _sendParam(AMOUNT, AMOUNT);
        sendParam.dstEid = unknownEid;

        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, unknownEid));
        wrapper.quoteSend(sendParam, false);
    }

    function test_quoteSend_revertsAfterRemoveDestinationToken() external {
        vm.prank(operator);
        wrapper.removeDestinationToken(DESTINATION_EID);

        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, DESTINATION_EID));
        wrapper.quoteSend(_sendParam(AMOUNT, AMOUNT), false);
    }

    function test_quoteSend_revertsIfPayInLzToken() external {
        vm.expectRevert(IPortalOFTWrapper.LayerZeroTokenUnsupported.selector);
        wrapper.quoteSend(_sendParam(AMOUNT, AMOUNT), true);
    }

    function test_quoteSend_revertsIfComposeMsg() external {
        SendParam memory sendParam = _sendParam(AMOUNT, AMOUNT);
        sendParam.composeMsg = hex"01";

        vm.expectRevert(IPortalOFTWrapper.ComposeMsgUnsupported.selector);
        wrapper.quoteSend(sendParam, false);
    }

    function test_quoteSend_revertsIfOftCmd() external {
        SendParam memory sendParam = _sendParam(AMOUNT, AMOUNT);
        sendParam.oftCmd = hex"01";

        vm.expectRevert(IPortalOFTWrapper.OFTCmdUnsupported.selector);
        wrapper.quoteSend(sendParam, false);
    }

    function test_quoteSend_revertsIfUnsupportedEid() external {
        SendParam memory sendParam = _sendParam(AMOUNT, AMOUNT);
        sendParam.dstEid = 1;

        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, 1));
        wrapper.quoteSend(sendParam, false);
    }
}
