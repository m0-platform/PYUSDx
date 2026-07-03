// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IOFT } from "../../../../../src/portal/oft/interfaces/IOFT.sol";

import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

contract ViewsUnitTest is PortalOFTWrapperUnitTestBase {
    function test_oftVersion() external view {
        (bytes4 interfaceId, uint64 version) = wrapper.oftVersion();

        // The canonical LayerZero IOFT interface ID, asserted as a literal so any drift
        // in the vendored interface from the canonical one is caught.
        assertEq(interfaceId, bytes4(0x02e49c2c));
        assertEq(interfaceId, type(IOFT).interfaceId);
        assertEq(version, 1);
    }

    function test_approvalRequired() external view {
        // `false` as required by the LayerZero Value Transfer API flow: the send amount is
        // pre-pushed into the wrapper by the LayerZero TransferDelegate before `send`.
        assertFalse(wrapper.approvalRequired());
    }

    function test_getDestinationToken() external view {
        assertEq(wrapper.getDestinationToken(DESTINATION_EID), peerPYUSDX);
    }

    function test_getDestinationToken_unset() external view {
        assertEq(wrapper.getDestinationToken(1), bytes32(0));
    }
}
