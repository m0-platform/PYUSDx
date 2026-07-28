// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IAccessControl } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";

import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

contract RemoveDestinationTokenUnitTest is PortalOFTWrapperUnitTestBase {
    function test_removeDestinationToken() external {
        vm.expectEmit();
        emit IPortalOFTWrapper.DestinationTokenRemoved(DESTINATION_EID);

        vm.prank(operator);
        wrapper.removeDestinationToken(DESTINATION_EID);

        assertEq(wrapper.getDestinationToken(DESTINATION_EID), bytes32(0));
    }

    function test_removeDestinationToken_noOpIfUnset() external {
        vm.recordLogs();

        vm.prank(operator);
        wrapper.removeDestinationToken(1);

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_removeDestinationToken_revertsIfZeroDestinationEid() external {
        vm.expectRevert(IPortalOFTWrapper.ZeroDestinationEid.selector);
        vm.prank(operator);
        wrapper.removeDestinationToken(0);
    }

    function test_removeDestinationToken_revertsIfNotOperator() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                wrapper.OPERATOR_ROLE()
            )
        );
        vm.prank(user);
        wrapper.removeDestinationToken(DESTINATION_EID);
    }
}
