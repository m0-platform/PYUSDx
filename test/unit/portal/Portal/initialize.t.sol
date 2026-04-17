// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { TransparentUpgradeableProxy } from "../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IPortal } from "../../../../src/portal/interfaces/IPortal.sol";
import { Portal } from "../../../../src/portal/Portal.sol";

import { PortalUnitTestBase } from "./PortalUnitTestBase.sol";

contract InitializeUnitTest is PortalUnitTestBase {
    function test_initialize_initialState() external {
        assertTrue(portal.hasRole(portal.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(portal.hasRole(portal.PAUSER_ROLE(), pauser));
        assertTrue(portal.hasRole(portal.OPERATOR_ROLE(), operator));
        assertEq(portal.fallbackRecipient(), fallbackRecipient);
    }

    function test_initialize_cannotReinitialize() external {
        bytes memory initializeData = abi.encodeCall(Portal.initialize, (admin, pauser, operator, fallbackRecipient));

        (bool success, ) = address(portal).call(initializeData);
        assertFalse(success);
    }

    function test_initialize_zeroAdmin() external {
        bytes memory initializeData = abi.encodeCall(
            Portal.initialize,
            (address(0), pauser, operator, fallbackRecipient)
        );

        vm.expectRevert(IPortal.ZeroAdmin.selector);
        new TransparentUpgradeableProxy(address(implementation), admin, initializeData);
    }

    function test_initialize_zeroPauser() external {
        bytes memory initializeData = abi.encodeCall(
            Portal.initialize,
            (admin, address(0), operator, fallbackRecipient)
        );

        vm.expectRevert(IPortal.ZeroPauser.selector);
        new TransparentUpgradeableProxy(address(implementation), admin, initializeData);
    }

    function test_initialize_zeroOperator() external {
        bytes memory initializeData = abi.encodeCall(Portal.initialize, (admin, pauser, address(0), fallbackRecipient));

        vm.expectRevert(IPortal.ZeroOperator.selector);
        new TransparentUpgradeableProxy(address(implementation), admin, initializeData);
    }

    function test_initialize_zeroFallbackRecipient() external {
        bytes memory initializeData = abi.encodeCall(Portal.initialize, (admin, pauser, operator, address(0)));

        vm.expectRevert(IPortal.ZeroFallbackRecipient.selector);
        new TransparentUpgradeableProxy(address(implementation), admin, initializeData);
    }
}
