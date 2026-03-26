// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { ILayerZeroEndpointV2 } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";

import { LayerZeroBridgeAdapterUnitTestBase } from "./LayerZeroBridgeAdapterUnitTestBase.sol";

contract RevokeRoleUnitTest is LayerZeroBridgeAdapterUnitTestBase {
    function test_revokeRole_clearsDelegateWhenRevokingCurrentDelegate() external {
        // After initialize, the operator is the delegate.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);

        // Admin revokes the operator role.
        vm.startPrank(admin);
        adapter.revokeRole(adapter.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // The delegate should be cleared on the endpoint.
        assertEq(lzEndpoint.delegates(address(adapter)), address(0));
    }

    function test_revokeRole_doesNotClearDelegateWhenRevokingNonDelegate() external {
        // Grant operator role to a second address.
        address operator2 = makeAddr("operator2");

        vm.startPrank(admin);
        adapter.grantRole(adapter.OPERATOR_ROLE(), operator2);

        // The original operator is still the delegate.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);

        // Revoking operator2 (who is NOT the delegate) should not clear the delegate.
        adapter.revokeRole(adapter.OPERATOR_ROLE(), operator2);
        vm.stopPrank();

        // The delegate remains unchanged.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);
    }

    function test_revokeRole_doesNotClearDelegateWhenRevokingAdminRole() external {
        // Grant admin role to operator so we can test revoking it.
        vm.startPrank(admin);
        adapter.grantRole(adapter.DEFAULT_ADMIN_ROLE(), operator);

        // Operator is the delegate.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);

        // Revoking the admin role (not OPERATOR_ROLE) should not affect the delegate.
        adapter.revokeRole(adapter.DEFAULT_ADMIN_ROLE(), operator);
        vm.stopPrank();

        // The delegate remains unchanged.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);
    }

    function test_revokeRole_doesNotClearDelegateAfterDelegateWasChanged() external {
        // Operator sets a new delegate.
        address newDelegate = makeAddr("newDelegate");
        vm.prank(operator);
        adapter.setDelegate(newDelegate);

        assertEq(lzEndpoint.delegates(address(adapter)), newDelegate);

        // Revoking operator (no longer the delegate) should not clear the delegate.
        vm.startPrank(admin);
        adapter.revokeRole(adapter.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // The delegate remains the newDelegate.
        assertEq(lzEndpoint.delegates(address(adapter)), newDelegate);
    }
}
