// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IAccessControl } from "../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";

import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract SetDefaultBridgeAdapterUnitTest is PortalUnitTestBase {
    address internal newBridgeAdapter = makeAddr("newBridgeAdapter");

    function test_setDefaultBridgeAdapter() external {
        vm.prank(operator);

        vm.expectEmit();
        emit IPortal.DefaultBridgeAdapterSet(CHAIN_ID_2, newBridgeAdapter);

        portal.setDefaultBridgeAdapter(CHAIN_ID_2, newBridgeAdapter);

        assertEq(portal.defaultBridgeAdapter(CHAIN_ID_2), newBridgeAdapter);
    }

    function test_setDefaultBridgeAdapter_addsToSupportedAdaptersIfNotPresent() external {
        vm.prank(operator);

        vm.expectEmit();
        emit IPortal.SupportedBridgeAdapterSet(CHAIN_ID_2, newBridgeAdapter, true);

        portal.setDefaultBridgeAdapter(CHAIN_ID_2, newBridgeAdapter);

        assertTrue(portal.supportedBridgeAdapter(CHAIN_ID_2, newBridgeAdapter));
    }

    function test_setDefaultBridgeAdapter_revertsIfCalledByNonOperator() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                portal.OPERATOR_ROLE()
            )
        );
        vm.prank(admin);
        portal.setDefaultBridgeAdapter(CHAIN_ID_2, newBridgeAdapter);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                portal.OPERATOR_ROLE()
            )
        );
        vm.prank(user);
        portal.setDefaultBridgeAdapter(CHAIN_ID_2, newBridgeAdapter);
    }

    function test_setDefaultBridgeAdapter_revertsIfInvalidDestinationChain() external {
        vm.expectRevert(abi.encodeWithSelector(IPortal.InvalidDestinationChain.selector, CHAIN_ID_1));
        vm.prank(operator);
        portal.setDefaultBridgeAdapter(CHAIN_ID_1, newBridgeAdapter);
    }

    function test_setDefaultBridgeAdapter_revertsIfZeroBridgeAdapter() external {
        vm.expectRevert(IPortal.ZeroBridgeAdapter.selector);
        vm.prank(operator);
        portal.setDefaultBridgeAdapter(CHAIN_ID_2, address(0));
    }
}
