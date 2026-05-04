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

    function test_revokeRole_clearsDelegateWhenRevokingNonDelegate() external {
        // Grant operator role to a second address.
        address operator2 = makeAddr("operator2");

        vm.startPrank(admin);
        adapter.grantRole(adapter.OPERATOR_ROLE(), operator2);

        // The original operator is still the delegate.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);

        // Revoking operator2 (who is NOT the delegate) should clear the delegate.
        adapter.revokeRole(adapter.OPERATOR_ROLE(), operator2);
        vm.stopPrank();

        // The delegate should be cleared on the endpoint.
        assertEq(lzEndpoint.delegates(address(adapter)), address(0));
    }

    function test_revokeRole_doesNotClearDelegateWhenRevokingAdminRole() external {
        // Grant admin role to operator so we can test revoking it.
        vm.startPrank(admin);
        adapter.grantRole(adapter.DEFAULT_ADMIN_ROLE(), operator);

        // Operator is the delegate.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);

        // Revoking a non-OPERATOR role must not affect the delegate.
        adapter.revokeRole(adapter.DEFAULT_ADMIN_ROLE(), operator);
        vm.stopPrank();

        // The delegate remains unchanged.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);
    }

    function test_revokeRole_doesNotClearDelegateWhenNoOpRevoke() external {
        // Account does not hold OPERATOR_ROLE — revoke is a no-op.
        address notOperator = makeAddr("notOperator");
        assertFalse(adapter.hasRole(adapter.OPERATOR_ROLE(), notOperator));

        // Operator is still the delegate.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);

        // Revoking OPERATOR_ROLE from an account that doesn't have it must not clear the delegate.
        vm.startPrank(admin);
        adapter.revokeRole(adapter.OPERATOR_ROLE(), notOperator);
        vm.stopPrank();

        // The delegate remains unchanged.
        assertEq(lzEndpoint.delegates(address(adapter)), operator);
    }

    function test_revokeRole_clearsDelegateAfterDelegateWasChanged() external {
        // Operator sets a new delegate.
        address newDelegate = makeAddr("newDelegate");
        vm.prank(operator);
        adapter.setDelegate(newDelegate);

        assertEq(lzEndpoint.delegates(address(adapter)), newDelegate);

        // Revoking OPERATOR_ROLE from the operator should clear the delegate, even though the
        // current delegate is a different address.
        vm.startPrank(admin);
        adapter.revokeRole(adapter.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // The delegate should be cleared on the endpoint.
        assertEq(lzEndpoint.delegates(address(adapter)), address(0));
    }
}
