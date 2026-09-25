// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {
    MessagingFee,
    MessagingReceipt
} from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { SendParam, OFTReceipt } from "../../../../../src/portal/oft/interfaces/IOFT.sol";
import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

/// @notice Executable direct-call example for README.md#portal-oft-wrapper-decision-and-runbook; uses the local mock adapter.
contract QuoteThenSendUnitTest is PortalOFTWrapperUnitTestBase {
    function test_quoteThenApproveAndSend() external {
        uint256 amount = 10e6;
        vm.prank(address(portal));
        pyusdx.mint(user, amount);

        SendParam memory params = _sendParam(amount, amount);
        MessagingFee memory fee = wrapper.quoteSend(params, false);
        uint256 supplyBefore = pyusdx.totalSupply();

        vm.startPrank(user);
        pyusdx.approve(address(wrapper), amount);
        (MessagingReceipt memory message, OFTReceipt memory transfer) = wrapper.send{ value: fee.nativeFee }(
            params,
            fee,
            user
        );
        vm.stopPrank();

        assertEq(message.fee.nativeFee, FEE);
        assertEq(message.fee.lzTokenFee, 0);
        assertEq(message.nonce, 0);
        assertEq(transfer.amountSentLD, amount);
        assertEq(transfer.amountReceivedLD, amount);
        assertEq(pyusdx.balanceOf(user), 0);
        assertEq(pyusdx.balanceOf(address(wrapper)), 0);
        assertEq(pyusdx.totalSupply(), supplyBefore - amount);
        assertEq(address(bridgeAdapter).balance, fee.nativeFee);
    }
}
