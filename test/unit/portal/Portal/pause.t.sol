// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IAccessControl } from "../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";
import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract PauseUnitTest is PortalUnitTestBase {
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function test_pauseSend() external {
        assertFalse(portal.sendPaused());

        vm.expectEmit();
        emit IPortal.SendPaused();

        vm.prank(pauser);
        portal.pauseSend();

        assertTrue(portal.sendPaused());
    }

    function test_pauseSend_alreadyPaused() external {
        vm.prank(pauser);
        portal.pauseSend();

        assertTrue(portal.sendPaused());

        // Should not emit event when already paused
        vm.recordLogs();
        vm.prank(pauser);
        portal.pauseSend();

        assertEq(vm.getRecordedLogs().length, 0);
        assertTrue(portal.sendPaused());
    }

    function test_pauseSend_revertsIfNotPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, PAUSER_ROLE)
        );
        vm.prank(user);
        portal.pauseSend();
    }

    function test_unpauseSend() external {
        vm.prank(pauser);
        portal.pauseSend();

        assertTrue(portal.sendPaused());

        vm.expectEmit();
        emit IPortal.SendUnpaused();

        vm.prank(pauser);
        portal.unpauseSend();

        assertFalse(portal.sendPaused());
    }

    function test_unpauseSend_alreadyUnpaused() external {
        assertFalse(portal.sendPaused());

        // Should not emit event when already unpaused
        vm.recordLogs();
        vm.prank(pauser);
        portal.unpauseSend();

        assertEq(vm.getRecordedLogs().length, 0);
        assertFalse(portal.sendPaused());
    }

    function test_unpauseSend_revertsIfNotPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, PAUSER_ROLE)
        );
        vm.prank(user);
        portal.unpauseSend();
    }

    function test_pauseReceive() external {
        assertFalse(portal.receivePaused());

        vm.expectEmit();
        emit IPortal.ReceivePaused();

        vm.prank(pauser);
        portal.pauseReceive();

        assertTrue(portal.receivePaused());
    }

    function test_pauseReceive_alreadyPaused() external {
        vm.prank(pauser);
        portal.pauseReceive();

        assertTrue(portal.receivePaused());

        // Should not emit event when already paused
        vm.recordLogs();
        vm.prank(pauser);
        portal.pauseReceive();

        assertEq(vm.getRecordedLogs().length, 0);
        assertTrue(portal.receivePaused());
    }

    function test_pauseReceive_revertsIfNotPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, PAUSER_ROLE)
        );
        vm.prank(user);
        portal.pauseReceive();
    }

    function test_unpauseReceive() external {
        vm.prank(pauser);
        portal.pauseReceive();

        assertTrue(portal.receivePaused());

        vm.expectEmit();
        emit IPortal.ReceiveUnpaused();

        vm.prank(pauser);
        portal.unpauseReceive();

        assertFalse(portal.receivePaused());
    }

    function test_unpauseReceive_alreadyUnpaused() external {
        assertFalse(portal.receivePaused());

        // Should not emit event when already unpaused
        vm.recordLogs();
        vm.prank(pauser);
        portal.unpauseReceive();

        assertEq(vm.getRecordedLogs().length, 0);
        assertFalse(portal.receivePaused());
    }

    function test_unpauseReceive_revertsIfNotPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, PAUSER_ROLE)
        );
        vm.prank(user);
        portal.unpauseReceive();
    }

    function test_pauseAll() external {
        assertFalse(portal.sendPaused());
        assertFalse(portal.receivePaused());

        vm.expectEmit();
        emit IPortal.SendPaused();
        vm.expectEmit();
        emit IPortal.ReceivePaused();

        vm.prank(pauser);
        portal.pauseAll();

        assertTrue(portal.sendPaused());
        assertTrue(portal.receivePaused());
    }

    function test_pauseAll_partiallyPaused() external {
        vm.prank(pauser);
        portal.pauseSend();

        assertTrue(portal.sendPaused());
        assertFalse(portal.receivePaused());

        // Should only emit ReceivePaused since send is already paused
        vm.recordLogs();
        vm.prank(pauser);
        portal.pauseAll();

        // Only ReceivePaused should be emitted
        assertEq(vm.getRecordedLogs().length, 1);
        assertTrue(portal.sendPaused());
        assertTrue(portal.receivePaused());
    }

    function test_pauseAll_revertsIfNotPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, PAUSER_ROLE)
        );
        vm.prank(user);
        portal.pauseAll();
    }

    function test_unpauseAll() external {
        vm.prank(pauser);
        portal.pauseAll();

        assertTrue(portal.sendPaused());
        assertTrue(portal.receivePaused());

        vm.expectEmit();
        emit IPortal.SendUnpaused();
        vm.expectEmit();
        emit IPortal.ReceiveUnpaused();

        vm.prank(pauser);
        portal.unpauseAll();

        assertFalse(portal.sendPaused());
        assertFalse(portal.receivePaused());
    }

    function test_unpauseAll_partiallyPaused() external {
        vm.prank(pauser);
        portal.pauseReceive();

        assertFalse(portal.sendPaused());
        assertTrue(portal.receivePaused());

        // Should only emit ReceiveUnpaused since send is already unpaused
        vm.recordLogs();
        vm.prank(pauser);
        portal.unpauseAll();

        // Only ReceiveUnpaused should be emitted
        assertEq(vm.getRecordedLogs().length, 1);
        assertFalse(portal.sendPaused());
        assertFalse(portal.receivePaused());
    }

    function test_unpauseAll_revertsIfNotPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, PAUSER_ROLE)
        );
        vm.prank(user);
        portal.unpauseAll();
    }
}
