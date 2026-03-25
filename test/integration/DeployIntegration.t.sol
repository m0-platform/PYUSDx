// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";

import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @title DeployIntegrationTests
/// @notice Validates the deploy scripts produce a fully wired, functional PYUSDX stack
contract DeployIntegrationTests is IntegrationForkTest {
    /* ============ Cross-Reference Tests ============ */

    function test_coreDeployment_crossReferences() public view {
        // IssuerGateway → PYUSDX
        assertEq(issuerGateway.pyusdx(), address(pyusdx));

        // SwapFacility → PYUSDX, Factory
        assertEq(swapFacility.pyusdx(), address(pyusdx));
        assertEq(swapFacility.extensionFactory(), address(factory));

        // Factory → PYUSDX, SwapFacility
        assertEq(factory.pyusdx(), address(pyusdx));
        assertEq(factory.swapFacility(), address(swapFacility));
    }

    /* ============ Role Tests ============ */

    function test_coreDeployment_pyusdxRoles() public view {
        assertTrue(pyusdx.hasRole(pyusdx.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(pyusdx.hasRole(pyusdx.PAUSER_ROLE(), pauser));
        assertTrue(pyusdx.hasRole(pyusdx.FREEZE_MANAGER_ROLE(), freezeManager));
        assertTrue(pyusdx.hasRole(pyusdx.FORCED_TRANSFER_MANAGER_ROLE(), forcedTransferManager));
        assertEq(pyusdx.earnerManager(), earnerManager);
    }

    function test_coreDeployment_issuerGatewayRoles() public view {
        assertTrue(issuerGateway.hasRole(issuerGateway.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(issuerGateway.hasRole(issuerGateway.ISSUER_ROLE(), issuer));
        assertTrue(issuerGateway.hasRole(issuerGateway.MINTER_ROLE(), minter));
    }

    function test_coreDeployment_swapFacilityRoles() public view {
        assertTrue(swapFacility.hasRole(swapFacility.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(swapFacility.hasRole(swapFacility.PAUSER_ROLE(), pauser));
    }

    function test_coreDeployment_factoryRoles() public view {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(factory.hasRole(factory.FACTORY_MANAGER_ROLE(), factoryManager));
    }

    /* ============ Functional Tests ============ */

    function test_coreDeployment_mintBurn() public {
        uint256 amount = 1000e6;

        // Mint via gateway
        _mintPYUSDX(alice, amount);
        assertEq(pyusdx.balanceOf(alice), amount);

        // Transfer to issuer so issuer can burn (burn burns from msg.sender)
        vm.prank(alice);
        pyusdx.transfer(issuer, amount);

        vm.prank(issuer);
        issuerGateway.burn(amount);

        assertEq(pyusdx.balanceOf(issuer), 0);
    }

    function test_coreDeployment_factoryDeployExtension() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "TestYTO",
            symbol: "TYTO",
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        vm.prank(admin);
        (address ytoProxy, , ) = factory.deployYieldToOne(string("test-yto-deploy"), params);

        assertTrue(factory.isApprovedExtension(ytoProxy));
        assertTrue(swapFacility.isApprovedExtension(ytoProxy));
    }

    function test_coreDeployment_swapEndToEnd() public {
        uint256 amount = 1000e6;

        // Deploy extension via factory
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "TestYTO",
            symbol: "TYTO",
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        vm.prank(admin);
        (address ytoProxy, , ) = factory.deployYieldToOne(string("test-yto-swap"), params);
        YieldToOne yto = YieldToOne(ytoProxy);

        // Enable earning for the extension
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(yto), 500, 0, yieldRecipient);

        // Mint PYUSDX
        _mintPYUSDX(alice, amount);

        // Swap in
        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), amount);

        vm.prank(alice);
        swapFacility.swapIn(address(yto), amount, alice);

        assertEq(yto.balanceOf(alice), amount);
        assertEq(pyusdx.balanceOf(alice), 0);

        // Swap out
        vm.prank(alice);
        IERC20(address(yto)).approve(address(swapFacility), amount);

        vm.prank(alice);
        swapFacility.swapOut(address(yto), amount, alice);

        assertEq(pyusdx.balanceOf(alice), amount);
        assertEq(yto.balanceOf(alice), 0);
    }
}
