// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";

contract ForceTransferTest is Test {
    PYUSDX public pyusdx;

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public earnerManager = makeAddr("earnerManager");
    address public freezeManager = makeAddr("freezeManager");
    address public forcedTransferManager = makeAddr("forcedTransferManager");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    function setUp() public {
        PYUSDX impl = new PYUSDX(makeAddr("minterGateway"), makeAddr("pyusd"));
        bytes memory initData = abi.encodeWithSelector(
            PYUSDX.initialize.selector,
            "PayPal USDX",
            "PYUSDX",
            admin,
            pauser,
            freezeManager,
            forcedTransferManager,
            earnerManager,
            address(1)  // rateManager
        );
        pyusdx = PYUSDX(address(new ERC1967Proxy(address(impl), initData)));
    }

    /* ============ freeze() behavior tests ============ */

    function test_freeze_doesNotStopEarning() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        assertTrue(pyusdx.isEarning(alice));

        // Freeze - should NOT stop earning (cleanup happens in forceTransfer)
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Account is frozen but still has earning status
        assertTrue(pyusdx.isFrozen(alice));
        assertTrue(pyusdx.isEarning(alice));
    }

    function test_freeze_nonEarner_works() public {
        // Alice is not earning
        assertFalse(pyusdx.isEarning(alice));

        // Freeze should work
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));
    }

    /* ============ _forceTransfer tests ============ */

    function test_forceTransfer_stopsEarningAndClearsDetails() public {
        // Setup earner with all details
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        (bool isEarning, address manager, uint16 feeRate, address recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(manager, earnerManager);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);

        // Force transfer
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, charlie, 0);

        // Account should be frozen and all earning details cleared
        assertTrue(pyusdx.isFrozen(alice));
        (isEarning, manager, feeRate, recipient) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
        assertEq(manager, address(0));
        assertEq(feeRate, 0);
        assertEq(recipient, address(0));
    }

    function test_forceTransfer_nonEarningAccount() public {
        // Alice is not earning
        assertFalse(pyusdx.isEarning(alice));
        assertFalse(pyusdx.isFrozen(alice));

        // Force transfer on non-earning account
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, 0);

        // Should be frozen, still not earning
        assertTrue(pyusdx.isFrozen(alice));
        assertFalse(pyusdx.isEarning(alice));
    }

    function test_forceTransfer_succeedsWhenPaused() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        // Pause the contract
        vm.prank(pauser);
        pyusdx.pause();
        assertTrue(pyusdx.paused());

        // Force transfer should still work when paused
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, 0);

        // Should be frozen and not earning
        assertTrue(pyusdx.isFrozen(alice));
        assertFalse(pyusdx.isEarning(alice));
    }

    function test_forceTransfer_onlyForcedTransferManager() public {
        // Random caller should revert
        vm.expectRevert();
        vm.prank(alice);
        pyusdx.forceTransfer(alice, bob, 0);
    }

    function test_forceTransfer_freezesAccountFirst() public {
        // Alice is not frozen
        assertFalse(pyusdx.isFrozen(alice));

        // Force transfer (with 0 amount since alice has no balance)
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, 0);

        // Assert account is now frozen
        assertTrue(pyusdx.isFrozen(alice));
    }

    function test_forceTransfer_alreadyFrozenAccountStaysFrozen() public {
        // First freeze alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);
        assertTrue(pyusdx.isFrozen(alice));

        // Force transfer should still work
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, 0);

        // Still frozen
        assertTrue(pyusdx.isFrozen(alice));
    }

    function test_forceTransfer_stopsEarningEvenIfAlreadyFrozen() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        assertTrue(pyusdx.isEarning(alice));

        // Freeze first (doesn't stop earning)
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));
        assertTrue(pyusdx.isEarning(alice)); // Still earning

        // Force transfer stops earning
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, 0);

        assertFalse(pyusdx.isEarning(alice)); // Now stopped
    }

    function test_forceTransfer_revertsOnInsufficientBalance() public {
        // Alice has no balance
        assertEq(pyusdx.balanceOf(alice), 0);

        // Try to force transfer more than balance
        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, 0, 100));
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, 100);
    }

    function test_forceTransfer_revertsOnZeroRecipient() public {
        vm.expectRevert(IPYUSDX.ZeroRecipient.selector);
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, address(0), 0);
    }

    function test_forceTransfer_emitsEarningDetailsSetEvent() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Force transfer and check for EarningDetailsSet event
        vm.expectEmit(true, true, true, true);
        emit IPYUSDX.EarningDetailsSet(alice, false, address(0), 0, address(0));

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, charlie, 0);
    }

    /* ============ forceTransferWithYieldRecipient tests ============ */

    function test_forceTransferWithYieldRecipient_works() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        // Force transfer with yield recipient
        vm.prank(forcedTransferManager);
        pyusdx.forceTransferWithYieldRecipient(alice, bob, 0, charlie);

        // Should be frozen and not earning
        assertTrue(pyusdx.isFrozen(alice));
        assertFalse(pyusdx.isEarning(alice));
    }

    function test_forceTransferWithYieldRecipient_zeroYieldRecipient_keepsYieldWithAccount() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        // Force transfer with zero yield recipient (yield stays with account)
        vm.prank(forcedTransferManager);
        pyusdx.forceTransferWithYieldRecipient(alice, bob, 0, address(0));

        // Should be frozen and not earning
        assertTrue(pyusdx.isFrozen(alice));
        assertFalse(pyusdx.isEarning(alice));
    }

    function test_forceTransferWithYieldRecipient_claimsYieldEvenIfFrozen() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        // Freeze first
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));
        assertTrue(pyusdx.isEarning(alice));

        // Force transfer should still work and claim yield (no yield to claim since no balance, but no revert)
        vm.prank(forcedTransferManager);
        pyusdx.forceTransferWithYieldRecipient(alice, bob, 0, charlie);

        // Should still be frozen and now not earning
        assertTrue(pyusdx.isFrozen(alice));
        assertFalse(pyusdx.isEarning(alice));
    }

    function test_forceTransferWithYieldRecipient_onlyForcedTransferManager() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        // Random caller should revert
        vm.expectRevert();
        vm.prank(alice);
        pyusdx.forceTransferWithYieldRecipient(alice, bob, 0, charlie);
    }

    function test_forceTransferWithYieldRecipient_revertsOnZeroRecipient() public {
        vm.expectRevert(IPYUSDX.ZeroRecipient.selector);
        vm.prank(forcedTransferManager);
        pyusdx.forceTransferWithYieldRecipient(alice, address(0), 0, charlie);
    }

    function test_forceTransferWithYieldRecipient_succeedsWhenPaused() public {
        // Setup earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        // Pause the contract
        vm.prank(pauser);
        pyusdx.pause();
        assertTrue(pyusdx.paused());

        // Force transfer with yield recipient should still work when paused
        vm.prank(forcedTransferManager);
        pyusdx.forceTransferWithYieldRecipient(alice, bob, 0, charlie);

        // Should be frozen and not earning
        assertTrue(pyusdx.isFrozen(alice));
        assertFalse(pyusdx.isEarning(alice));
    }
}
