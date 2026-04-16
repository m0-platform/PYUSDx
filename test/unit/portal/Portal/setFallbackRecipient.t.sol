// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IAccessControl } from "../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";

import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract SetFallbackRecipientUnitTest is PortalUnitTestBase {
    function test_setFallbackRecipient() external {
        address newFallbackRecipient = makeAddr("newFallbackRecipient");

        vm.expectEmit();
        emit IPortal.FallbackRecipientSet(newFallbackRecipient);

        vm.prank(admin);
        portal.setFallbackRecipient(newFallbackRecipient);

        assertEq(portal.fallbackRecipient(), newFallbackRecipient);
    }

    function test_setFallbackRecipient_noOpIfUnchanged() external {
        // Initial value is set by the test base to `fallbackRecipient`
        assertEq(portal.fallbackRecipient(), fallbackRecipient);

        // Record logs to verify no event is emitted when the value is unchanged
        vm.recordLogs();

        vm.prank(admin);
        portal.setFallbackRecipient(fallbackRecipient);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(portal.fallbackRecipient(), fallbackRecipient);
    }

    function test_setFallbackRecipient_revertsIfCalledByNonAdmin() external {
        address newFallbackRecipient = makeAddr("newFallbackRecipient");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                operator,
                portal.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(operator);
        portal.setFallbackRecipient(newFallbackRecipient);
    }

    function test_setFallbackRecipient_revertsIfZeroFallbackRecipient() external {
        vm.expectRevert(IPortal.ZeroFallbackRecipient.selector);
        vm.prank(admin);
        portal.setFallbackRecipient(address(0));
    }
}
