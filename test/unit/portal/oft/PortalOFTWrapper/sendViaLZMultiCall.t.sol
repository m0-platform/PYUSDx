// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";
import { IERC20 } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { MessagingFee } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { IOFT, SendParam } from "../../../../../src/portal/oft/interfaces/IOFT.sol";
import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";
import { PortalOFTWrapper } from "../../../../../src/portal/oft/PortalOFTWrapper.sol";

import { MockLZMultiCall } from "../../../../mock/MockLZMultiCall.sol";
import { MockTransferDelegate } from "../../../../mock/MockTransferDelegate.sol";
import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

/// @notice Models the production LayerZero Value Transfer API sequence: the user approves the
///         token to the single-purpose TransferDelegate only, then a single LZMultiCall
///         transaction moves the send amount from the user into the multicall contract, approves
///         the wrapper (as instructed by `approvalRequired()`), and invokes `send`, so at `send`
///         the caller is the multicall contract (not the user or token owner) and the wrapper
///         pulls the amount from it. All steps roll back together on failure.
contract SendViaLZMultiCallUnitTest is PortalOFTWrapperUnitTestBase {
    using TypeConverter for address;

    uint256 internal constant AMOUNT = 10e6;

    MockTransferDelegate internal transferDelegate;
    MockLZMultiCall internal lzMultiCall;

    function setUp() public override {
        super.setUp();

        transferDelegate = new MockTransferDelegate();
        lzMultiCall = new MockLZMultiCall();

        // Prank Portal as in MockPYUSDX it's set as an issuer
        vm.prank(address(portal));
        pyusdx.mint(user, 100e6);

        // The user approves the TransferDelegate only — never the wrapper or the multicall.
        vm.prank(user);
        pyusdx.approve(address(transferDelegate), AMOUNT);
    }

    function _multicallCalls(SendParam memory sendParam) internal view returns (MockLZMultiCall.Call[] memory calls) {
        calls = new MockLZMultiCall.Call[](3);
        calls[0] = MockLZMultiCall.Call({
            target: address(transferDelegate),
            value: 0,
            data: abi.encodeCall(
                MockTransferDelegate.delegateTransferFrom,
                (address(pyusdx), user, address(lzMultiCall), AMOUNT)
            )
        });
        calls[1] = MockLZMultiCall.Call({
            target: address(pyusdx),
            value: 0,
            data: abi.encodeCall(IERC20.approve, (address(wrapper), AMOUNT))
        });
        calls[2] = MockLZMultiCall.Call({
            target: address(wrapper),
            value: FEE,
            data: abi.encodeCall(
                PortalOFTWrapper.send,
                (sendParam, MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }), address(lzMultiCall))
            )
        });
    }

    function test_send_viaLZMultiCall() external {
        MockLZMultiCall.Call[] memory calls = _multicallCalls(_sendParam(AMOUNT, AMOUNT));

        uint256 initialSupply = pyusdx.totalSupply();

        // At `send`, msg.sender is the multicall contract, which holds the user's tokens and
        // has approved the wrapper: the full amount is pulled from the multicall contract.
        vm.expectEmit();
        emit IOFT.OFTSent(_getMessageId(), DESTINATION_EID, address(lzMultiCall), AMOUNT, AMOUNT);

        vm.prank(user);
        lzMultiCall.multicall{ value: FEE }(calls);

        assertEq(pyusdx.balanceOf(user), 100e6 - AMOUNT);
        assertEq(pyusdx.balanceOf(address(wrapper)), 0);
        assertEq(pyusdx.balanceOf(address(lzMultiCall)), 0);
        assertEq(pyusdx.totalSupply(), initialSupply - AMOUNT);

        // Both allowances were consumed in full: the user's on the delegate and the multicall
        // contract's on the wrapper. The user never approved the wrapper.
        assertEq(pyusdx.allowance(user, address(transferDelegate)), 0);
        assertEq(pyusdx.allowance(user, address(wrapper)), 0);
        assertEq(pyusdx.allowance(address(lzMultiCall), address(wrapper)), 0);

        // The fee travelled multicall -> wrapper -> Portal -> bridge adapter.
        assertEq(address(bridgeAdapter).balance, FEE);
    }

    function test_send_viaLZMultiCall_rollsBackAtomically() external {
        // Make the `send` leg fail after the delegate has moved the tokens and the wrapper
        // has been approved.
        vm.prank(operator);
        wrapper.removeDestinationToken(DESTINATION_EID);

        MockLZMultiCall.Call[] memory calls = _multicallCalls(_sendParam(AMOUNT, AMOUNT));

        // The multicall bubbles the wrapper's revert, unwinding the transfer and approval with it.
        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, DESTINATION_EID));
        vm.prank(user);
        lzMultiCall.multicall{ value: FEE }(calls);

        // Nothing moved: balances and the delegate allowance are fully intact, and the
        // multicall contract's approval on the wrapper never survives the transaction.
        assertEq(pyusdx.balanceOf(user), 100e6);
        assertEq(pyusdx.balanceOf(address(wrapper)), 0);
        assertEq(pyusdx.balanceOf(address(lzMultiCall)), 0);
        assertEq(pyusdx.allowance(user, address(transferDelegate)), AMOUNT);
        assertEq(pyusdx.allowance(address(lzMultiCall), address(wrapper)), 0);
    }
}
