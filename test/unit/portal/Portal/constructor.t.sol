// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";
import { Portal } from "../../../../src/portal/Portal.sol";

import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract ConstructorUnitTest is PortalUnitTestBase {
    function test_constructor_initialState() external {
        assertEq(address(portal.pyusdx()), address(pyusdx));
        assertEq(address(portal.swapFacility()), address(swapFacility));
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IPortal.ZeroPYUSDXToken.selector);
        new Portal(address(0), address(swapFacility));
    }

    function test_constructor_zeroSwapFacility() external {
        vm.expectRevert(IPortal.ZeroSwapFacility.selector);
        new Portal(address(pyusdx), address(0));
    }
}
