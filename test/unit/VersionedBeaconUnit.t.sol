// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Test } from "../../lib/evm-m-extensions/lib/forge-std/src/Test.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";

import { VersionedBeacon } from "../../src/platform/VersionedBeacon.sol";

contract VersionedBeaconUnitTests is Test {
    VersionedBeacon public beacon;

    address public admin = makeAddr("admin");
    address public factory = makeAddr("factory");
    address public pyusdx = makeAddr("pyusdx");
    address public swapFacility = makeAddr("swapFacility");
    address public versionManager = makeAddr("versionManager");
    address public pauseManager = makeAddr("pauseManager");
    address public freezeManager = makeAddr("freezeManager");

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        beacon = new VersionedBeacon(factory, pyusdx, swapFacility, admin, versionManager, pauseManager, freezeManager);
    }

    /* ============ Constructor ============ */

    function test_constructor_grantsFreezeManagerRole() public view {
        assertTrue(beacon.hasRole(beacon.FREEZE_MANAGER_ROLE(), freezeManager));
    }

    function test_constructor_revert_zeroFreezeManager() public {
        vm.expectRevert(IFreezable.ZeroFreezeManager.selector);
        new VersionedBeacon(factory, pyusdx, swapFacility, admin, versionManager, pauseManager, address(0));
    }

    /* ============ Freeze / Unfreeze ============ */

    function test_freeze() public {
        vm.expectEmit();
        emit IFreezable.Frozen(alice, block.timestamp);

        vm.prank(freezeManager);
        beacon.freeze(alice);

        assertTrue(beacon.isFrozen(alice));
        assertFalse(beacon.isFrozen(bob));
    }

    function test_freeze_idempotent() public {
        vm.prank(freezeManager);
        beacon.freeze(alice);

        vm.prank(freezeManager);
        beacon.freeze(alice);

        assertTrue(beacon.isFrozen(alice));
    }

    function test_unfreeze() public {
        vm.prank(freezeManager);
        beacon.freeze(alice);

        vm.expectEmit();
        emit IFreezable.Unfrozen(alice, block.timestamp);

        vm.prank(freezeManager);
        beacon.unfreeze(alice);

        assertFalse(beacon.isFrozen(alice));
    }

    function test_unfreeze_idempotent() public {
        vm.prank(freezeManager);
        beacon.unfreeze(alice);

        assertFalse(beacon.isFrozen(alice));
    }

    function test_freeze_revert_notFreezeManager() public {
        bytes32 role = beacon.FREEZE_MANAGER_ROLE();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));

        beacon.freeze(bob);
    }

    function test_unfreeze_revert_notFreezeManager() public {
        vm.prank(freezeManager);
        beacon.freeze(alice);

        bytes32 role = beacon.FREEZE_MANAGER_ROLE();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));

        beacon.unfreeze(alice);
    }

    /* ============ Batch Freeze / Unfreeze ============ */

    function test_freezeAccounts() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        vm.prank(freezeManager);
        beacon.freezeAccounts(accounts);

        assertTrue(beacon.isFrozen(alice));
        assertTrue(beacon.isFrozen(bob));
    }

    function test_unfreezeAccounts() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        vm.prank(freezeManager);
        beacon.freezeAccounts(accounts);

        vm.prank(freezeManager);
        beacon.unfreezeAccounts(accounts);

        assertFalse(beacon.isFrozen(alice));
        assertFalse(beacon.isFrozen(bob));
    }
}
