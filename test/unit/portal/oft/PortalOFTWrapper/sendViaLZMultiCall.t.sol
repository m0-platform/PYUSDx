// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { MessagingFee } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { IOFT, SendParam } from "../../../../../src/portal/oft/interfaces/IOFT.sol";
import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";
import { PortalOFTWrapper } from "../../../../../src/portal/oft/PortalOFTWrapper.sol";

import { MockLZMultiCall } from "../../../../mock/MockLZMultiCall.sol";
import { MockTransferDelegate } from "../../../../mock/MockTransferDelegate.sol";
import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

/// @notice Models the production LayerZero Value Transfer API sequence: the user approves the
///         token to the single-purpose TransferDelegate only, then a single LZMultiCall
///         transaction pre-pushes the send amount into the wrapper and invokes `send`, so at
///         `send` the caller is the multicall contract (not the user or token owner) and the
///         wrapper already holds the tokens. Both steps roll back together on failure.
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
        calls = new MockLZMultiCall.Call[](2);
        calls[0] = MockLZMultiCall.Call({
            target: address(transferDelegate),
            value: 0,
            data: abi.encodeCall(
                MockTransferDelegate.delegateTransferFrom,
                (address(pyusdx), user, address(wrapper), AMOUNT)
            )
        });
        calls[1] = MockLZMultiCall.Call({
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

        // At `send`, msg.sender is the multicall contract, which holds no tokens and has no
        // allowance: the wrapper must consume its pre-pushed balance and pull nothing.
        vm.expectEmit();
        emit IOFT.OFTSent(_getMessageId(), DESTINATION_EID, address(lzMultiCall), AMOUNT, AMOUNT);

        vm.prank(user);
        lzMultiCall.multicall{ value: FEE }(calls);

        assertEq(pyusdx.balanceOf(user), 100e6 - AMOUNT);
        assertEq(pyusdx.balanceOf(address(wrapper)), 0);
        assertEq(pyusdx.balanceOf(address(lzMultiCall)), 0);
        assertEq(pyusdx.totalSupply(), initialSupply - AMOUNT);

        // The delegate allowance was consumed; the wrapper was never approved by anyone.
        assertEq(pyusdx.allowance(user, address(transferDelegate)), 0);
        assertEq(pyusdx.allowance(user, address(wrapper)), 0);
        assertEq(pyusdx.allowance(address(lzMultiCall), address(wrapper)), 0);

        // The fee travelled multicall -> wrapper -> Portal -> bridge adapter.
        assertEq(address(bridgeAdapter).balance, FEE);
    }

    function test_send_viaLZMultiCall_rollsBackAtomically() external {
        // Make the `send` leg fail after the delegate has pre-pushed the tokens.
        vm.prank(operator);
        wrapper.removeDestinationToken(DESTINATION_EID);

        MockLZMultiCall.Call[] memory calls = _multicallCalls(_sendParam(AMOUNT, AMOUNT));

        // The multicall bubbles the wrapper's revert, unwinding the pre-push with it.
        vm.expectRevert(abi.encodeWithSelector(IPortalOFTWrapper.UnsupportedDestinationEid.selector, DESTINATION_EID));
        vm.prank(user);
        lzMultiCall.multicall{ value: FEE }(calls);

        // Nothing moved: balance and delegate allowance are fully intact.
        assertEq(pyusdx.balanceOf(user), 100e6);
        assertEq(pyusdx.balanceOf(address(wrapper)), 0);
        assertEq(pyusdx.allowance(user, address(transferDelegate)), AMOUNT);
    }
}
