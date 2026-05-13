// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IAccessControl } from "../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";

import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract SetPayloadGasLimitUnitTest is PortalUnitTestBase {
    function test_setPayloadGasLimit() external {
        uint256 newGasLimit = 350_000;
        vm.prank(operator);
        vm.expectEmit();
        emit IPortal.PayloadGasLimitSet(CHAIN_ID_2, newGasLimit);

        portal.setPayloadGasLimit(CHAIN_ID_2, newGasLimit);

        assertEq(portal.payloadGasLimit(CHAIN_ID_2), newGasLimit);
    }

    function test_setPayloadGasLimit_revertsIfCalledByNonOperator() external {
        uint256 newGasLimit = 300_000;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                portal.OPERATOR_ROLE()
            )
        );
        vm.prank(admin);
        portal.setPayloadGasLimit(CHAIN_ID_2, newGasLimit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                portal.OPERATOR_ROLE()
            )
        );
        vm.prank(user);
        portal.setPayloadGasLimit(CHAIN_ID_2, newGasLimit);
    }

    function test_setPayloadGasLimit_revertsIfInvalidDestinationChain() external {
        uint256 gasLimit = 100_000;

        vm.expectRevert(abi.encodeWithSelector(IPortal.InvalidDestinationChain.selector, CHAIN_ID_1));
        vm.prank(operator);
        portal.setPayloadGasLimit(CHAIN_ID_1, gasLimit);
    }

    function test_setPayloadGasLimit_unsetsWithZero() external {
        // Base setup already configures a non-zero gas limit for CHAIN_ID_2
        assertEq(portal.payloadGasLimit(CHAIN_ID_2), TOKEN_TRANSFER_GAS_LIMIT);

        vm.prank(operator);
        vm.expectEmit();
        emit IPortal.PayloadGasLimitSet(CHAIN_ID_2, 0);

        portal.setPayloadGasLimit(CHAIN_ID_2, 0);

        assertEq(portal.payloadGasLimit(CHAIN_ID_2), 0);
    }
}
