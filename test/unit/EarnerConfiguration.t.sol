// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Test, Vm } from "forge-std/Test.sol";

import { ERC1967Proxy } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IForcedTransferable } from "../../lib/m-extensions/src/components/forcedTransferable/IForcedTransferable.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";

contract EarnerConfigurationTest is Test {
    PYUSDX public pyusdx;

    address public admin = makeAddr("admin");
    address public earnerManager = makeAddr("earnerManager");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        PYUSDX impl = new PYUSDX(makeAddr("minterGateway"), makeAddr("pyusd"));
        bytes memory initData = abi.encodeWithSelector(
            PYUSDX.initialize.selector,
            "PayPal USDX",
            "PYUSDX",
            admin,
            address(1), // pauser
            address(1), // freezeManager
            address(1), // forcedTransferManager
            earnerManager,
            address(1) // rateManager
        );
        pyusdx = PYUSDX(address(new ERC1967Proxy(address(impl), initData)));
    }

    function test_setEarningDetails_enableEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        (bool isEarning, address manager, uint16 feeRate, address recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(manager, earnerManager);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);
    }

    function test_setEarningDetails_disableEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 0, address(0));

        (bool isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
    }

    function test_setEarningDetails_revert_zeroAccount() public {
        vm.expectRevert(IPYUSDX.ZeroAccount.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(address(0), true, 500, bob);
    }

    function test_setEarningDetails_revert_feeRateTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.FeeRateTooHigh.selector, 10001));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 10001, bob);
    }

    function test_setEarningDetails_revert_invalidDetails() public {
        vm.expectRevert(IPYUSDX.InvalidDetails.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 500, bob);
    }

    function test_setEarningDetails_batch() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        bool[] memory isEarning = new bool[](2);
        isEarning[0] = true;
        isEarning[1] = true;

        uint16[] memory feeRates = new uint16[](2);
        feeRates[0] = 500;
        feeRates[1] = 1000;

        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = alice;

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(accounts, isEarning, feeRates, recipients);

        assertTrue(pyusdx.isEarning(alice));
        assertTrue(pyusdx.isEarning(bob));
    }

    function test_setEarningDetails_batch_revert_arrayLengthZero() public {
        vm.expectRevert(IPYUSDX.ArrayLengthZero.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(new address[](0), new bool[](0), new uint16[](0), new address[](0));
    }

    function test_setEarningDetails_batch_revert_arrayLengthMismatch() public {
        vm.expectRevert(IForcedTransferable.ArrayLengthMismatch.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(new address[](2), new bool[](1), new uint16[](2), new address[](2));
    }

    function test_setEarningDetails_noop_alreadyDisabled() public {
        // Alice is not earning (default state)
        (bool isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);

        // Calling setEarningDetails with isEarning=false should be a no-op (no event)
        vm.recordLogs();
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 0, address(0));

        // Verify no EarningDetailsSet event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], keccak256("EarningDetailsSet(address,bool,address,uint16,address)"));
        }

        // State should remain unchanged
        (isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
    }

    function test_setEarningDetails_noop_sameSettings() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        (bool isEarning, address manager, uint16 feeRate, address recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);

        // Call again with same settings - should be a no-op (no event, no claim)
        vm.recordLogs();
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Verify no EarningDetailsSet event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], keccak256("EarningDetailsSet(address,bool,address,uint16,address)"));
        }

        // State should remain unchanged
        (isEarning, manager, feeRate, recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(manager, earnerManager);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);
    }

    function test_setEarningDetails_changedFeeRate_emitsEvent() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Change fee rate - should NOT be a no-op
        vm.recordLogs();
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        // Verify EarningDetailsSet event WAS emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("EarningDetailsSet(address,bool,address,uint16,address)")) {
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "EarningDetailsSet event should be emitted when fee rate changes");

        // Verify state updated
        (, , uint16 feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(feeRate, 1000);
    }

    function test_setEarningDetails_changedClaimRecipient_emitsEvent() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        address charlie = makeAddr("charlie");

        // Change claim recipient - should NOT be a no-op
        vm.recordLogs();
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, charlie);

        // Verify EarningDetailsSet event WAS emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("EarningDetailsSet(address,bool,address,uint16,address)")) {
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "EarningDetailsSet event should be emitted when claim recipient changes");

        // Verify state updated
        (, , , address recipient) = pyusdx.getEarningDetails(alice);
        assertEq(recipient, charlie);
    }

    function test_setEarningDetails_revert_earnerDetailsAlreadySet() public {
        // First earner manager sets earning details for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // A different earner manager tries to modify alice's details
        address otherEarnerManager = makeAddr("otherEarnerManager");
        bytes32 earnerManagerRole = pyusdx.EARNER_MANAGER_ROLE();
        vm.prank(admin);
        pyusdx.grantRole(earnerManagerRole, otherEarnerManager);

        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.EarnerDetailsAlreadySet.selector, alice));
        vm.prank(otherEarnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);
    }

    function test_setEarningDetails_sameManagerCanUpdate() public {
        // First earner manager sets earning details for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Same earner manager can update alice's details
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        (, , uint16 feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(feeRate, 1000);
    }
}
