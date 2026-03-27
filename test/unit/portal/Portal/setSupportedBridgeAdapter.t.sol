// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IAccessControl } from "../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";

import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract SetSupportedBridgeAdapterUnitTest is PortalUnitTestBase {
    address internal newBridgeAdapter = makeAddr("newBridgeAdapter");

    function test_setSupportedBridgeAdapter_setsAsSupported() external {
        vm.prank(operator);
        vm.expectEmit();
        emit IPortal.SupportedBridgeAdapterSet(CHAIN_ID_2, newBridgeAdapter, true);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter, true);

        assertTrue(portal.supportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter));
    }

    function test_setSupportedBridgeAdapter_setsAsUnsupported() external {
        // First add as supported
        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter, true);

        // Then remove support
        vm.prank(operator);
        vm.expectEmit();
        emit IPortal.SupportedBridgeAdapterSet(CHAIN_ID_2, newBridgeAdapter, false);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter, false);

        assertFalse(portal.supportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter));
    }

    function test_setSupportedBridgeAdapter_revertsIfCalledByNonOperator() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                portal.OPERATOR_ROLE()
            )
        );
        vm.prank(admin);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                portal.OPERATOR_ROLE()
            )
        );
        vm.prank(user);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter, true);
    }

    function test_setSupportedBridgeAdapter_revertsIfInvalidDestinationChain() external {
        vm.expectRevert(abi.encodeWithSelector(IPortal.InvalidDestinationChain.selector, CHAIN_ID_1));
        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_1, newBridgeAdapter, true);
    }

    function test_setSupportedBridgeAdapter_revertsIfZeroBridgeAdapter() external {
        vm.expectRevert(IPortal.ZeroBridgeAdapter.selector);
        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, address(0), true);
    }

    function test_setSupportedBridgeAdapter_multipleAdaptersPerChain() external {
        address adapter1 = makeAddr("adapter1");
        address adapter2 = makeAddr("adapter2");
        address adapter3 = makeAddr("adapter3");

        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, adapter1, true);

        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, adapter2, true);

        vm.prank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, adapter3, true);

        assertTrue(portal.supportedBridgeAdapter(CHAIN_ID_2, adapter1));
        assertTrue(portal.supportedBridgeAdapter(CHAIN_ID_2, adapter2));
        assertTrue(portal.supportedBridgeAdapter(CHAIN_ID_2, adapter3));
    }

    function test_setSupportedBridgeAdapter_clearsDefaultAdapterWhenUnsupported() external {
        // Add the adapter as supported
        vm.startPrank(operator);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter, true);

        // Set it as the default adapter
        portal.setDefaultBridgeAdapter(CHAIN_ID_2, newBridgeAdapter);

        // Verify it's set as default
        assertEq(portal.defaultBridgeAdapter(CHAIN_ID_2), newBridgeAdapter);

        // Set the adapter as unsupported, which clears the default
        vm.expectEmit();
        emit IPortal.DefaultBridgeAdapterSet(CHAIN_ID_2, address(0));
        vm.expectEmit();
        emit IPortal.SupportedBridgeAdapterSet(CHAIN_ID_2, newBridgeAdapter, false);
        portal.setSupportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter, false);

        // Verify the adapter is no longer supported
        assertFalse(portal.supportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter));

        // Verify the default adapter was cleared
        assertEq(portal.defaultBridgeAdapter(CHAIN_ID_2), address(0));
    }
}
