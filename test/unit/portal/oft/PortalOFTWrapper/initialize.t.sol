// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Initializable } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { TransparentUpgradeableProxy } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IPortalOFTWrapper } from "../../../../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";
import { PortalOFTWrapper } from "../../../../../src/portal/oft/PortalOFTWrapper.sol";

import { PortalOFTWrapperUnitTestBase } from "./PortalOFTWrapperUnitTestBase.sol";

contract InitializeUnitTest is PortalOFTWrapperUnitTestBase {
    function test_initialize() external view {
        assertTrue(wrapper.hasRole(wrapper.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(wrapper.hasRole(wrapper.OPERATOR_ROLE(), operator));
    }

    function test_initialize_revertsIfZeroAdmin() external {
        vm.expectRevert(IPortalOFTWrapper.ZeroAdmin.selector);
        new TransparentUpgradeableProxy(
            address(wrapperImplementation),
            admin,
            abi.encodeCall(PortalOFTWrapper.initialize, (address(0), operator))
        );
    }

    function test_initialize_revertsIfZeroOperator() external {
        vm.expectRevert(IPortalOFTWrapper.ZeroOperator.selector);
        new TransparentUpgradeableProxy(
            address(wrapperImplementation),
            admin,
            abi.encodeCall(PortalOFTWrapper.initialize, (admin, address(0)))
        );
    }

    function test_initialize_revertsIfCalledOnImplementation() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        wrapperImplementation.initialize(admin, operator);
    }

    function test_initialize_revertsIfCalledTwice() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        wrapper.initialize(admin, operator);
    }
}
