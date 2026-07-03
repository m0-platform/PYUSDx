// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IAccessControl } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";

import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

contract SetDestinationTokenUnitTest is PortalOFTWrapperUnitTestBase {
    uint32 internal constant NEW_EID = 30101;
    bytes32 internal newDestinationToken = bytes32(uint256(uint160(0xCAFE)));

    function test_setDestinationToken() external {
        vm.expectEmit();
        emit IPortalOFTWrapper.DestinationTokenSet(NEW_EID, newDestinationToken);

        vm.prank(operator);
        wrapper.setDestinationToken(NEW_EID, newDestinationToken);

        assertEq(wrapper.getDestinationToken(NEW_EID), newDestinationToken);
    }

    function test_setDestinationToken_overwrite() external {
        vm.prank(operator);
        wrapper.setDestinationToken(DESTINATION_EID, newDestinationToken);

        assertEq(wrapper.getDestinationToken(DESTINATION_EID), newDestinationToken);
    }

    function test_setDestinationToken_noOpIfUnchanged() external {
        vm.recordLogs();

        vm.prank(operator);
        wrapper.setDestinationToken(DESTINATION_EID, peerPYUSDX);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(wrapper.getDestinationToken(DESTINATION_EID), peerPYUSDX);
    }

    function test_setDestinationToken_revertsIfNotOperator() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                wrapper.OPERATOR_ROLE()
            )
        );
        vm.prank(user);
        wrapper.setDestinationToken(NEW_EID, newDestinationToken);
    }

    function test_setDestinationToken_revertsIfZeroEid() external {
        vm.expectRevert(IPortalOFTWrapper.ZeroDestinationEid.selector);
        vm.prank(operator);
        wrapper.setDestinationToken(0, newDestinationToken);
    }

    function test_setDestinationToken_revertsIfZeroToken() external {
        vm.expectRevert(IPortalOFTWrapper.ZeroDestinationToken.selector);
        vm.prank(operator);
        wrapper.setDestinationToken(NEW_EID, bytes32(0));
    }
}
