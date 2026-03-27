// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";
import { PayloadType } from "../../../../src/portal/libraries/PayloadEncoder.sol";

import { MockBridgeAdapter } from "../../../mock/MockBridgeAdapter.sol";
import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract QuoteUnitTest is PortalUnitTestBase {
    function test_quote_withDefaultAdapter() external {
        uint256 expectedFee = 0.001 ether;
        bridgeAdapter.setQuote(expectedFee);

        uint256 fee = portal.quote(CHAIN_ID_2);

        assertEq(fee, expectedFee);
    }

    function test_quote_withSpecificAdapter() external {
        MockBridgeAdapter customAdapter = new MockBridgeAdapter();
        customAdapter.setPortal(address(portal));

        uint256 expectedFee = 0.002 ether;
        customAdapter.setQuote(expectedFee);

        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, address(customAdapter), true);

        uint256 fee = portal.quote(CHAIN_ID_2, address(customAdapter));

        assertEq(fee, expectedFee);
    }

    function testFuzz_quote(uint256 expectedFee) external {
        vm.assume(expectedFee < 1 ether);
        bridgeAdapter.setQuote(expectedFee);

        assertEq(portal.quote(CHAIN_ID_2), expectedFee);
    }

    function test_quote_revertsIfNoBridgeAdapterSet() external {
        uint32 unconfiguredChain = 999;

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, unconfiguredChain, address(0))
        );
        portal.quote(unconfiguredChain);
    }

    function test_quote_revertsIfUnsupportedBridgeAdapter() external {
        address unsupportedAdapter = makeAddr("unsupported");

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, CHAIN_ID_2, unsupportedAdapter)
        );
        portal.quote(CHAIN_ID_2, unsupportedAdapter);
    }

    function test_quote_revertsIfPayloadGasLimitNotSet() external {
        uint32 newChainId = 999;

        // Set up bridge adapter but NOT the gas limit
        vm.prank(operator);
        portal.setDefaultBridgeAdapter(newChainId, address(bridgeAdapter));

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.PayloadGasLimitNotSet.selector, newChainId, PayloadType.TokenTransfer)
        );
        portal.quote(newChainId);
    }

    function test_quote_withSpecificAdapter_revertsIfPayloadGasLimitNotSet() external {
        uint32 newChainId = 999;

        // Set up bridge adapter but NOT the gas limit
        vm.prank(operator);
        portal.setSupportedBridgeAdapter(newChainId, address(bridgeAdapter), true);

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.PayloadGasLimitNotSet.selector, newChainId, PayloadType.TokenTransfer)
        );
        portal.quote(newChainId, address(bridgeAdapter));
    }
}
