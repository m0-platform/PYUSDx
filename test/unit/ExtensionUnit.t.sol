// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Test } from "../../lib/evm-m-extensions/lib/forge-std/src/Test.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { IPausable } from "../../lib/evm-m-extensions/src/components/pausable/IPausable.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { PausableUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { ExtensionHarness } from "../harness/ExtensionHarness.sol";
import { MockSwapFacility } from "../mock/MockSwapFacility.sol";
import { MockERC20 } from "../mock/MockERC20.sol";

contract ExtensionUnitTests is Test {
    MockERC20 public pyusdx;
    MockSwapFacility public swapFacility;
    ExtensionHarness public extension;

    address public admin = makeAddr("admin");
    address public freezeManager = makeAddr("freezeManager");
    address public pauser = makeAddr("pauser");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant MINT_AMOUNT = 1000e6;

    function setUp() public {
        pyusdx = new MockERC20("PYUSDX", "PYUSDX", 6);
        swapFacility = new MockSwapFacility(address(pyusdx));

        address impl = address(new ExtensionHarness(address(pyusdx), address(swapFacility)));
        extension = ExtensionHarness(
            UnsafeUpgrades.deployTransparentProxy(
                impl,
                admin,
                abi.encodeWithSelector(
                    ExtensionHarness.initialize.selector,
                    "Test Extension",
                    "tEXT",
                    admin,
                    freezeManager,
                    pauser
                )
            )
        );
    }

    /* ============ Helpers ============ */

    function _wrapFor(address to, address recipient, uint256 amount) internal {
        pyusdx.mint(to, amount);

        vm.startPrank(to);

        IERC20(address(pyusdx)).approve(address(swapFacility), amount);
        swapFacility.swapIn(address(extension), amount, recipient);

        vm.stopPrank();
    }

    /* ============ constructor ============ */

    function test_constructor_revert_zeroPYUSDX() public {
        vm.expectRevert(IExtension.ZeroPYUSDX.selector);
        new ExtensionHarness(address(0), address(swapFacility));
    }

    function test_constructor_revert_zeroSwapFacility() public {
        vm.expectRevert(IExtension.ZeroSwapFacility.selector);
        new ExtensionHarness(address(pyusdx), address(0));
    }

    /* ============ initialize ============ */

    function test_initialize() public view {
        assertTrue(extension.hasRole(extension.FREEZE_MANAGER_ROLE(), freezeManager));
        assertTrue(extension.hasRole(extension.PAUSER_ROLE(), pauser));
    }

    function test_initialize_revert_zeroFreezeManager() public {
        address impl = address(new ExtensionHarness(address(pyusdx), address(swapFacility)));
        vm.expectRevert(IFreezable.ZeroFreezeManager.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                ExtensionHarness.initialize.selector,
                "Test Extension",
                "tEXT",
                admin,
                address(0),
                pauser
            )
        );
    }

    function test_initialize_revert_zeroPauser() public {
        address impl = address(new ExtensionHarness(address(pyusdx), address(swapFacility)));
        vm.expectRevert(IPausable.ZeroPauser.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                ExtensionHarness.initialize.selector,
                "Test Extension",
                "tEXT",
                admin,
                freezeManager,
                address(0)
            )
        );
    }

    /* ============ freeze / pause – roles ============ */

    function test_freeze_revert_notFreezeManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                extension.FREEZE_MANAGER_ROLE()
            )
        );

        vm.prank(alice);
        extension.freeze(alice);
    }

    function test_pause_revert_notPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                extension.PAUSER_ROLE()
            )
        );

        vm.prank(alice);
        extension.pause();
    }

    /* ============ wrap ============ */

    function test_wrap_revert_frozenAccount() public {
        vm.prank(freezeManager);
        extension.freeze(alice);

        pyusdx.mint(alice, MINT_AMOUNT);

        vm.startPrank(alice);

        IERC20(address(pyusdx)).approve(address(swapFacility), MINT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swapIn(address(extension), MINT_AMOUNT, alice);

        vm.stopPrank();
    }

    function test_wrap_revert_frozenRecipient() public {
        vm.prank(freezeManager);
        extension.freeze(bob);

        pyusdx.mint(alice, MINT_AMOUNT);

        vm.startPrank(alice);

        IERC20(address(pyusdx)).approve(address(swapFacility), MINT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));
        swapFacility.swapIn(address(extension), MINT_AMOUNT, bob);

        vm.stopPrank();
    }

    function test_wrap_revert_paused() public {
        vm.prank(pauser);
        extension.pause();

        pyusdx.mint(alice, MINT_AMOUNT);

        vm.startPrank(alice);

        IERC20(address(pyusdx)).approve(address(swapFacility), MINT_AMOUNT);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        swapFacility.swapIn(address(extension), MINT_AMOUNT, alice);

        vm.stopPrank();
    }

    /* ============ unwrap ============ */

    function test_unwrap_revert_frozenAccount() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        swapFacility.swapOut(address(extension), MINT_AMOUNT, alice);
    }

    function test_unwrap_revert_paused() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);

        vm.prank(pauser);
        extension.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swapOut(address(extension), MINT_AMOUNT, alice);
    }

    /* ============ transfer ============ */

    function test_transfer_revert_frozenSender() public {
        extension.mint(alice, MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        extension.transfer(bob, 400e6);
    }

    function test_transfer_revert_frozenRecipient() public {
        extension.mint(alice, MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        extension.transfer(bob, 400e6);
    }

    function test_transfer_revert_paused() public {
        extension.mint(alice, MINT_AMOUNT);

        vm.prank(pauser);
        extension.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        extension.transfer(bob, 400e6);
    }

    /* ============ transferFrom ============ */

    function test_transferFrom_revert_frozenMsgSender() public {
        extension.mint(alice, MINT_AMOUNT);

        vm.prank(alice);
        extension.approve(bob, MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(bob);
        extension.transferFrom(alice, bob, 400e6);
    }

    /* ============ approve ============ */

    function test_approve_revert_frozenAccount() public {
        extension.mint(alice, MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        extension.approve(bob, 100e6);
    }

    function test_approve_revert_frozenSpender() public {
        extension.mint(alice, MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        extension.approve(bob, 100e6);
    }

    function test_approve_succeedsWhenPaused() public {
        extension.mint(alice, MINT_AMOUNT);

        vm.prank(pauser);
        extension.pause();

        vm.prank(alice);
        extension.approve(bob, 400e6);

        assertEq(extension.allowance(alice, bob), 400e6);
    }

    /* ============ unfreeze / unpause ============ */

    function test_unfreeze_resumesOperations() public {
        vm.prank(freezeManager);
        extension.freeze(alice);

        pyusdx.mint(alice, MINT_AMOUNT);

        vm.startPrank(alice);

        IERC20(address(pyusdx)).approve(address(swapFacility), MINT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swapIn(address(extension), MINT_AMOUNT, alice);

        vm.stopPrank();

        vm.prank(freezeManager);
        extension.unfreeze(alice);

        vm.prank(alice);
        swapFacility.swapIn(address(extension), MINT_AMOUNT, alice);

        assertEq(extension.balanceOf(alice), MINT_AMOUNT);
    }

    function test_unpause_resumesOperations() public {
        extension.mint(alice, MINT_AMOUNT);

        vm.prank(pauser);
        extension.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        extension.transfer(bob, 400e6);

        vm.prank(pauser);
        extension.unpause();

        vm.prank(alice);
        extension.transfer(bob, 400e6);

        assertEq(extension.balanceOf(alice), 600e6);
        assertEq(extension.balanceOf(bob), 400e6);
    }
}
