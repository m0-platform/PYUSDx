// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TypeConverter } from "../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { ComposeMessageParams, IPortal } from "../../../../src/portal/interfaces/IPortal.sol";

import { MockBridgeAdapter } from "../../../mock/MockBridgeAdapter.sol";
import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract QuoteUnitTest is PortalUnitTestBase {
    using TypeConverter for address;

    function test_quote_withDefaultAdapter() external {
        uint256 expectedFee = 0.001 ether;
        bridgeAdapter.setQuote(expectedFee);

        uint256 fee = portal.quote(CHAIN_ID_2, address(0));

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

        assertEq(portal.quote(CHAIN_ID_2, address(0)), expectedFee);
    }

    function test_quote_revertsIfNoBridgeAdapterSet() external {
        uint32 unconfiguredChain = 999;

        vm.expectRevert(
            abi.encodeWithSelector(IPortal.UnsupportedBridgeAdapter.selector, unconfiguredChain, address(0))
        );
        portal.quote(unconfiguredChain, address(0));
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

        vm.expectRevert(abi.encodeWithSelector(IPortal.PayloadGasLimitNotSet.selector, newChainId));
        portal.quote(newChainId, address(0));
    }

    function test_quote_withSpecificAdapter_revertsIfPayloadGasLimitNotSet() external {
        uint32 newChainId = 999;

        // Set up bridge adapter but NOT the gas limit
        vm.prank(operator);
        portal.setSupportedBridgeAdapter(newChainId, address(bridgeAdapter), true);

        vm.expectRevert(abi.encodeWithSelector(IPortal.PayloadGasLimitNotSet.selector, newChainId));
        portal.quote(newChainId, address(bridgeAdapter));
    }

    /* ============ Composed Quote ============ */

    function test_quoteComposed_withDefaultAdapter() external {
        uint256 expectedFee = 0.003 ether;
        bridgeAdapter.setQuote(expectedFee);

        ComposeMessageParams memory composeParams = ComposeMessageParams({
            composer: makeAddr("composer").toBytes32(),
            message: "msg",
            gasLimit: 100_000
        });

        uint256 fee = portal.quote(CHAIN_ID_2, address(0), composeParams);

        assertEq(fee, expectedFee);
    }

    function test_quoteComposed_withSpecificAdapter() external {
        MockBridgeAdapter customAdapter = new MockBridgeAdapter();
        customAdapter.setPortal(address(portal));

        uint256 expectedFee = 0.004 ether;
        customAdapter.setQuote(expectedFee);

        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, address(customAdapter), true);

        ComposeMessageParams memory composeParams = ComposeMessageParams({
            composer: makeAddr("composer").toBytes32(),
            message: "msg",
            gasLimit: 100_000
        });

        uint256 fee = portal.quote(CHAIN_ID_2, address(customAdapter), composeParams);

        assertEq(fee, expectedFee);
    }

    function test_quoteComposed_revertsIfPayloadGasLimitNotSet() external {
        uint32 newChainId = 999;

        vm.prank(operator);
        portal.setDefaultBridgeAdapter(newChainId, address(bridgeAdapter));

        ComposeMessageParams memory composeParams = ComposeMessageParams({
            composer: makeAddr("composer").toBytes32(),
            message: "msg",
            gasLimit: 100_000
        });

        vm.expectRevert(abi.encodeWithSelector(IPortal.PayloadGasLimitNotSet.selector, newChainId));
        portal.quote(newChainId, address(0), composeParams);
    }
}
