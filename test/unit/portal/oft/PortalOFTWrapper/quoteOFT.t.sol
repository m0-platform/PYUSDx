// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";
import { IOFT, SendParam, OFTLimit, OFTReceipt, OFTFeeDetail } from "../../../../../src/portal/oft/interfaces/IOFT.sol";

import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

contract QuoteOFTUnitTest is PortalOFTWrapperUnitTestBase {
    uint256 internal constant AMOUNT = 10e6;

    function test_quoteOFT() external view {
        (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt) = wrapper
            .quoteOFT(_sendParam(AMOUNT, AMOUNT));

        // The Portal rejects zero-amount sends, so the advertised minimum is 1.
        assertEq(oftLimit.minAmountLD, 1);
        assertEq(oftLimit.maxAmountLD, type(uint128).max);
        assertEq(oftFeeDetails.length, 0);
        assertEq(oftReceipt.amountSentLD, AMOUNT);
        assertEq(oftReceipt.amountReceivedLD, AMOUNT);
    }

    function testFuzz_quoteOFT_oneToOne(uint128 amount) external view {
        (, , OFTReceipt memory oftReceipt) = wrapper.quoteOFT(_sendParam(amount, amount));

        assertEq(oftReceipt.amountSentLD, amount);
        assertEq(oftReceipt.amountReceivedLD, amount);
    }

    function test_quoteOFT_extensionWrapper() external view {
        (OFTLimit memory oftLimit, , OFTReceipt memory oftReceipt) = extensionWrapper.quoteOFT(
            _sendParam(AMOUNT, AMOUNT)
        );

        assertEq(oftLimit.maxAmountLD, type(uint128).max);
        assertEq(oftReceipt.amountSentLD, AMOUNT);
        assertEq(oftReceipt.amountReceivedLD, AMOUNT);
    }

    function test_quoteOFT_revertsIfSlippageExceeded() external {
        vm.expectRevert(abi.encodeWithSelector(IOFT.SlippageExceeded.selector, AMOUNT, AMOUNT + 1));
        wrapper.quoteOFT(_sendParam(AMOUNT, AMOUNT + 1));
    }

    function test_quoteOFT_revertsIfAmountExceedsUint128() external {
        vm.expectRevert(TypeConverter.Uint128Overflow.selector);
        wrapper.quoteOFT(_sendParam(uint256(type(uint128).max) + 1, 0));
    }

    function test_quoteOFT_revertsIfEidUnknownToBridgeAdapter() external {
        // A destination token is configured, but the bridge adapter has no chain ID mapping
        // for the Endpoint ID, so the chain ID derivation fails.
        uint32 unknownEid = 30101;

        vm.prank(operator);
        wrapper.setDestinationToken(unknownEid, peerPYUSDX);

        SendParam memory sendParam = _sendParam(AMOUNT, AMOUNT);
        sendParam.dstEid = unknownEid;

        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, unknownEid));
        wrapper.quoteOFT(sendParam);
    }

    function test_quoteOFT_revertsIfUnsupportedEid() external {
        SendParam memory sendParam = _sendParam(AMOUNT, AMOUNT);
        sendParam.dstEid = 1;

        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, 1));
        wrapper.quoteOFT(sendParam);
    }
}
