// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";
import { PortalOFTWrapper } from "../../../../../src/portal/oft/PortalOFTWrapper.sol";

import { MockERC20 } from "../../../../mock/MockERC20.sol";
import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

contract ConstructorUnitTest is PortalOFTWrapperUnitTestBase {
    function test_constructor() external view {
        assertEq(wrapper.portal(), address(portal));
        assertEq(wrapper.token(), address(pyusdx));
        assertEq(wrapper.layerZeroBridgeAdapter(), address(bridgeAdapter));
        assertEq(wrapper.sharedDecimals(), 6);

        assertEq(extensionWrapper.portal(), address(portal));
        assertEq(extensionWrapper.token(), address(extension));
        assertEq(extensionWrapper.layerZeroBridgeAdapter(), address(bridgeAdapter));
        assertEq(extensionWrapper.sharedDecimals(), 6);
    }

    function test_constructor_sharedDecimalsFollowsTokenDecimals() external {
        MockERC20 token18 = new MockERC20("Token", "TKN", 18);
        PortalOFTWrapper wrapper18 = new PortalOFTWrapper(address(portal), address(token18), address(bridgeAdapter));

        assertEq(wrapper18.sharedDecimals(), 18);
    }

    function test_constructor_revertsIfZeroPortal() external {
        vm.expectRevert(IPortalOFTWrapper.ZeroPortal.selector);
        new PortalOFTWrapper(address(0), address(pyusdx), address(bridgeAdapter));
    }

    function test_constructor_revertsIfZeroToken() external {
        vm.expectRevert(IPortalOFTWrapper.ZeroToken.selector);
        new PortalOFTWrapper(address(portal), address(0), address(bridgeAdapter));
    }

    function test_constructor_revertsIfZeroBridgeAdapter() external {
        vm.expectRevert(IPortalOFTWrapper.ZeroBridgeAdapter.selector);
        new PortalOFTWrapper(address(portal), address(pyusdx), address(0));
    }
}
