// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IAccessControl } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IBridgeAdapter } from "../../../../../src/portal/interfaces/IBridgeAdapter.sol";

import { LayerZeroBridgeAdapterUnitTestBase } from "./LayerZeroBridgeAdapterUnitTestBase.sol";

contract SetBridgeChainIdUnitTest is LayerZeroBridgeAdapterUnitTestBase {
    uint32 internal constant OTHER_CHAIN_ID = 3;
    uint256 internal constant OTHER_LAYER_ZERO_EID = 30_103;

    function test_setBridgeChainId() external {
        // The base already configured (SPOKE_CHAIN_ID, SPOKE_LAYER_ZERO_EID). Add a fresh pair.
        vm.prank(operator);
        vm.expectEmit();
        emit IBridgeAdapter.BridgeChainIdSet(OTHER_CHAIN_ID, OTHER_LAYER_ZERO_EID);

        adapter.setBridgeChainId(OTHER_CHAIN_ID, OTHER_LAYER_ZERO_EID);

        assertEq(adapter.getBridgeChainId(OTHER_CHAIN_ID), OTHER_LAYER_ZERO_EID);
        assertEq(adapter.getChainId(OTHER_LAYER_ZERO_EID), OTHER_CHAIN_ID);
    }

    function test_setBridgeChainId_unchanged() external {
        // No event should be emitted when the pair is already configured.
        vm.recordLogs();
        vm.prank(operator);
        adapter.setBridgeChainId(SPOKE_CHAIN_ID, SPOKE_LAYER_ZERO_EID);

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_setBridgeChainId_reassignsBridgeChainToNewInternalChain() external {
        // Reassign SPOKE_LAYER_ZERO_EID from SPOKE_CHAIN_ID to OTHER_CHAIN_ID.
        // The old (SPOKE_CHAIN_ID -> SPOKE_LAYER_ZERO_EID) forward mapping must be removed and logged.
        vm.prank(operator);
        vm.expectEmit();
        emit IBridgeAdapter.BridgeChainIdRemoved(SPOKE_CHAIN_ID, SPOKE_LAYER_ZERO_EID);
        vm.expectEmit();
        emit IBridgeAdapter.BridgeChainIdSet(OTHER_CHAIN_ID, SPOKE_LAYER_ZERO_EID);

        adapter.setBridgeChainId(OTHER_CHAIN_ID, SPOKE_LAYER_ZERO_EID);

        assertEq(adapter.getBridgeChainId(OTHER_CHAIN_ID), SPOKE_LAYER_ZERO_EID);
        assertEq(adapter.getChainId(SPOKE_LAYER_ZERO_EID), OTHER_CHAIN_ID);
        // Old internal chain is now orphaned.
        assertEq(adapter.getBridgeChainId(SPOKE_CHAIN_ID), 0);
    }

    function test_setBridgeChainId_reassignsInternalChainToNewBridgeChain() external {
        // Repoint SPOKE_CHAIN_ID from SPOKE_LAYER_ZERO_EID to OTHER_LAYER_ZERO_EID.
        // The old (SPOKE_LAYER_ZERO_EID -> SPOKE_CHAIN_ID) reverse mapping must be removed and logged.
        vm.prank(operator);
        vm.expectEmit();
        emit IBridgeAdapter.BridgeChainIdRemoved(SPOKE_CHAIN_ID, SPOKE_LAYER_ZERO_EID);
        vm.expectEmit();
        emit IBridgeAdapter.BridgeChainIdSet(SPOKE_CHAIN_ID, OTHER_LAYER_ZERO_EID);

        adapter.setBridgeChainId(SPOKE_CHAIN_ID, OTHER_LAYER_ZERO_EID);

        assertEq(adapter.getBridgeChainId(SPOKE_CHAIN_ID), OTHER_LAYER_ZERO_EID);
        assertEq(adapter.getChainId(OTHER_LAYER_ZERO_EID), SPOKE_CHAIN_ID);
        // Old bridge chain is now orphaned.
        assertEq(adapter.getChainId(SPOKE_LAYER_ZERO_EID), 0);
    }

    function test_setBridgeChainId_reassignsBothSides() external {
        // Pre-configure a second pair so both cleanup branches fire.
        vm.prank(operator);
        adapter.setBridgeChainId(OTHER_CHAIN_ID, OTHER_LAYER_ZERO_EID);

        // Now call setBridgeChainId(SPOKE_CHAIN_ID, OTHER_LAYER_ZERO_EID):
        //  - Forward cleanup: OTHER_LAYER_ZERO_EID was mapped to OTHER_CHAIN_ID → remove (OTHER_CHAIN_ID, OTHER_LAYER_ZERO_EID).
        //  - Reverse cleanup: SPOKE_CHAIN_ID was mapped to SPOKE_LAYER_ZERO_EID → remove (SPOKE_CHAIN_ID, SPOKE_LAYER_ZERO_EID).
        vm.prank(operator);
        vm.expectEmit();
        emit IBridgeAdapter.BridgeChainIdRemoved(OTHER_CHAIN_ID, OTHER_LAYER_ZERO_EID);
        vm.expectEmit();
        emit IBridgeAdapter.BridgeChainIdRemoved(SPOKE_CHAIN_ID, SPOKE_LAYER_ZERO_EID);
        vm.expectEmit();
        emit IBridgeAdapter.BridgeChainIdSet(SPOKE_CHAIN_ID, OTHER_LAYER_ZERO_EID);

        adapter.setBridgeChainId(SPOKE_CHAIN_ID, OTHER_LAYER_ZERO_EID);

        // Final state: only (SPOKE_CHAIN_ID <-> OTHER_LAYER_ZERO_EID) is mapped.
        assertEq(adapter.getBridgeChainId(SPOKE_CHAIN_ID), OTHER_LAYER_ZERO_EID);
        assertEq(adapter.getChainId(OTHER_LAYER_ZERO_EID), SPOKE_CHAIN_ID);
        assertEq(adapter.getBridgeChainId(OTHER_CHAIN_ID), 0);
        assertEq(adapter.getChainId(SPOKE_LAYER_ZERO_EID), 0);
    }

    function test_setBridgeChainId_revertsIfZeroChain() external {
        vm.expectRevert(IBridgeAdapter.ZeroChain.selector);
        vm.prank(operator);
        adapter.setBridgeChainId(0, OTHER_LAYER_ZERO_EID);
    }

    function test_setBridgeChainId_revertsIfZeroBridgeChain() external {
        vm.expectRevert(IBridgeAdapter.ZeroBridgeChain.selector);
        vm.prank(operator);
        adapter.setBridgeChainId(OTHER_CHAIN_ID, 0);
    }

    function test_setBridgeChainId_revertsIfCalledByNonOperator() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                adapter.OPERATOR_ROLE()
            )
        );
        vm.prank(user);
        adapter.setBridgeChainId(OTHER_CHAIN_ID, OTHER_LAYER_ZERO_EID);
    }
}
