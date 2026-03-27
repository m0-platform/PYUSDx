// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    UnsafeUpgrades,
    Upgrades
} from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";

import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

contract ExtensionFactoryIntegrationTest is IntegrationForkTest {
    string public constant EXTENSION_NAME_YTO = "YTO-001";
    string public constant EXTENSION_NAME_MM = "MM-001";

    string public constant YTO_NAME = "YieldToOne Token";
    string public constant YTO_SYMBOL = "YTO";
    string public constant MM_NAME = "MultiMint Token";
    string public constant MM_SYMBOL = "MM";

    /* ============ Constructor Tests ============ */

    function test_constructor_zeroPyusdx() public {
        vm.expectRevert(IExtensionFactory.ZeroPYUSDX.selector);
        new ExtensionFactory(address(0), address(swapFacility), address(0));
    }

    function test_constructor_zeroSwapFacility() public {
        vm.expectRevert(IExtensionFactory.ZeroSwapFacility.selector);
        new ExtensionFactory(address(pyusdx), address(0), address(0));
    }

    function test_initialize_zeroAdmin() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(0)));
        address yieldToOneImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        address multiMintImpl = address(new MultiMint(address(pyusdx), address(swapFacility)));

        vm.expectRevert(IExtensionFactory.ZeroAdmin.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                ExtensionFactory.initialize.selector,
                address(0),
                factoryManager,
                yieldToOneImpl,
                multiMintImpl
            )
        );
    }

    function test_initialize_zeroFactoryManager() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(0)));
        address yieldToOneImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        address multiMintImpl = address(new MultiMint(address(pyusdx), address(swapFacility)));

        vm.expectRevert(IExtensionFactory.ZeroFactoryManager.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                ExtensionFactory.initialize.selector,
                admin,
                address(0),
                yieldToOneImpl,
                multiMintImpl
            )
        );
    }

    function test_initialize_zeroYieldToOneImplementation() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(0)));
        address multiMintImpl = address(new MultiMint(address(pyusdx), address(swapFacility)));

        vm.expectRevert(IExtensionFactory.ZeroExtension.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                ExtensionFactory.initialize.selector,
                admin,
                factoryManager,
                address(0),
                multiMintImpl
            )
        );
    }

    function test_initialize_zeroMultiMintImplementation() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(0)));
        address yieldToOneImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));

        vm.expectRevert(IExtensionFactory.ZeroExtension.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                ExtensionFactory.initialize.selector,
                admin,
                factoryManager,
                yieldToOneImpl,
                address(0)
            )
        );
    }

    function test_initialize_invalidYieldToOneImplementation() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(0)));
        address wrongPyusdx = makeAddr("wrongPyusdx");
        address yieldToOneImpl = address(new YieldToOne(wrongPyusdx, address(swapFacility)));
        address multiMintImpl = address(new MultiMint(address(pyusdx), address(swapFacility)));

        vm.expectRevert(IExtensionFactory.InvalidExtension.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                ExtensionFactory.initialize.selector,
                admin,
                factoryManager,
                yieldToOneImpl,
                multiMintImpl
            )
        );
    }

    function test_initialize_invalidMultiMintImplementation() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(0)));
        address yieldToOneImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        address wrongSwap = makeAddr("wrongSwap");
        address multiMintImpl = address(new MultiMint(address(pyusdx), wrongSwap));

        vm.expectRevert(IExtensionFactory.InvalidExtension.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                ExtensionFactory.initialize.selector,
                admin,
                factoryManager,
                yieldToOneImpl,
                multiMintImpl
            )
        );
    }

    function test_initialState() public view {
        assertEq(factory.pyusdx(), address(pyusdx));
        assertEq(factory.swapFacility(), address(swapFacility));

        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(factory.hasRole(factory.FACTORY_MANAGER_ROLE(), factoryManager));

        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.NONE), address(0));
        assertTrue(factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE) != address(0));
        assertTrue(factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT) != address(0));

        assertEq(uint8(IExtensionFactory.ExtensionType.NONE), uint8(0));
        assertEq(uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE), uint8(1));
        assertEq(uint8(IExtensionFactory.ExtensionType.MULTI_MINT), uint8(2));
    }

    function test_initialize_alreadyInitialized() public {
        address yieldToOneImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        address multiMintImpl = address(new MultiMint(address(pyusdx), address(swapFacility)));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        factory.initialize(admin, factoryManager, yieldToOneImpl, multiMintImpl);
    }

    /* ============ deployYieldToOne Tests ============ */

    function test_deployYieldToOne() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        (address proxy, address proxyAdmin, address implementation) = factory.deployYieldToOne(
            EXTENSION_NAME_YTO,
            params
        );

        assertTrue(proxy != address(0));
        assertTrue(proxyAdmin != address(0));
        assertTrue(implementation != address(0));

        // Verify extension is registered
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
        assertTrue(factory.isApprovedExtension(proxy));
        assertTrue(swapFacility.isApprovedExtension(proxy));

        // Verify storage
        assertEq(Upgrades.getImplementationAddress(proxy), implementation);

        // Verify ProxyAdmin matches ERC-1967 admin slot
        assertEq(proxyAdmin, Upgrades.getAdminAddress(proxy));

        // Verify token metadata
        assertEq(YieldToOne(proxy).name(), YTO_NAME);
        assertEq(YieldToOne(proxy).symbol(), YTO_SYMBOL);
        assertEq(YieldToOne(proxy).yieldRecipient(), yieldRecipient);

        // Verify wiring
        assertEq(IExtension(proxy).pyusdx(), address(pyusdx));
        assertEq(IExtension(proxy).swapFacility(), address(swapFacility));
    }

    function test_deployYieldToOne_zeroAdmin() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: address(0),
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        vm.expectRevert(IExtensionFactory.ZeroAdmin.selector);
        factory.deployYieldToOne(EXTENSION_NAME_YTO, params);
    }

    function test_deployYieldToOne_duplicateReverts() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        // Same deployer + same extensionName reverts
        vm.expectRevert();
        factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        // Different deployer + same extensionName succeeds
        vm.prank(alice);
        (address proxy, , ) = factory.deployYieldToOne(EXTENSION_NAME_YTO, params);
        assertTrue(factory.isApprovedExtension(proxy));
    }

    function test_deployYieldToOne_differentExtensionNamesNoCollision() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        // Different extensionName produces different address
        (address proxy2, , ) = factory.deployYieldToOne(string("YTO-002"), params);

        assertTrue(factory.isApprovedExtension(proxy2));
    }

    function test_deployYieldToOne_sharedImplementation() public {
        IExtensionFactory.YieldToOneParams memory params1 = IExtensionFactory.YieldToOneParams({
            name: "Ext1",
            symbol: "E1",
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        IExtensionFactory.YieldToOneParams memory params2 = IExtensionFactory.YieldToOneParams({
            name: "Ext2",
            symbol: "E2",
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        (, , address impl1) = factory.deployYieldToOne(string("YTO-A"), params1);
        (, , address impl2) = factory.deployYieldToOne(string("YTO-B"), params2);

        assertEq(impl1, impl2);
        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE), impl1);
    }

    function test_deployYieldToOne_predictedAddress() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        // Deploy from test contract (address(this))
        (address proxy1, , ) = factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        // Same extension name from different deployer should produce different address
        vm.prank(alice);
        (address proxy2, , ) = factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        assertTrue(proxy1 != proxy2);
        assertTrue(factory.isApprovedExtension(proxy1));
        assertTrue(factory.isApprovedExtension(proxy2));

        // Predict addresses correctly for each deployer
        assertEq(proxy1, factory.getExtensionAddress(address(this), EXTENSION_NAME_YTO));
        assertEq(proxy2, factory.getExtensionAddress(alice, EXTENSION_NAME_YTO));
    }

    /* ============ deployMultiMint Tests ============ */

    function test_deployMultiMint() public {
        IExtensionFactory.MultiMintParams memory params = IExtensionFactory.MultiMintParams({
            name: MM_NAME,
            symbol: MM_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        (address proxy, address proxyAdmin, address implementation) = factory.deployMultiMint(
            EXTENSION_NAME_MM,
            params
        );

        assertTrue(proxy != address(0));
        assertTrue(proxyAdmin != address(0));
        assertTrue(implementation != address(0));

        // Verify extension is registered
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.MULTI_MINT));
        assertTrue(factory.isApprovedExtension(proxy));
        assertTrue(swapFacility.isApprovedExtension(proxy));

        // Verify storage
        assertEq(Upgrades.getImplementationAddress(proxy), implementation);

        // Verify ProxyAdmin matches ERC-1967 admin slot
        assertEq(proxyAdmin, Upgrades.getAdminAddress(proxy));

        // Verify token metadata
        assertEq(MultiMint(proxy).name(), MM_NAME);
        assertEq(MultiMint(proxy).symbol(), MM_SYMBOL);
        assertEq(MultiMint(proxy).yieldRecipient(), yieldRecipient);

        // Verify wiring
        assertEq(IExtension(proxy).pyusdx(), address(pyusdx));
        assertEq(IExtension(proxy).swapFacility(), address(swapFacility));
    }

    function test_deployMultiMint_zeroAdmin() public {
        IExtensionFactory.MultiMintParams memory params = IExtensionFactory.MultiMintParams({
            name: MM_NAME,
            symbol: MM_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: address(0),
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        vm.expectRevert(IExtensionFactory.ZeroAdmin.selector);
        factory.deployMultiMint(EXTENSION_NAME_MM, params);
    }

    function test_deployMultiMint_duplicateReverts() public {
        IExtensionFactory.MultiMintParams memory params = IExtensionFactory.MultiMintParams({
            name: MM_NAME,
            symbol: MM_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: admin
        });

        factory.deployMultiMint(EXTENSION_NAME_MM, params);

        // Same deployer + same extensionName reverts
        vm.expectRevert();
        factory.deployMultiMint(EXTENSION_NAME_MM, params);

        // Different deployer + same extensionName succeeds
        vm.prank(alice);
        (address proxy, , ) = factory.deployMultiMint(EXTENSION_NAME_MM, params);
        assertTrue(factory.isApprovedExtension(proxy));
    }

    function test_deployMultiMint_sharedImplementation() public {
        IExtensionFactory.MultiMintParams memory params1 = IExtensionFactory.MultiMintParams({
            name: "MM1",
            symbol: "M1",
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: admin
        });

        IExtensionFactory.MultiMintParams memory params2 = IExtensionFactory.MultiMintParams({
            name: "MM2",
            symbol: "M2",
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: admin
        });

        (, , address impl1) = factory.deployMultiMint(string("MM-A"), params1);
        (, , address impl2) = factory.deployMultiMint(string("MM-B"), params2);

        assertEq(impl1, impl2);
        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT), impl1);
    }

    function test_deployMultiMint_predictedAddress() public {
        IExtensionFactory.MultiMintParams memory params = IExtensionFactory.MultiMintParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager
        });

        // Deploy from test contract (address(this))
        (address proxy1, , ) = factory.deployMultiMint(EXTENSION_NAME_YTO, params);

        // Same extension name from different deployer should produce different address
        vm.prank(alice);
        (address proxy2, , ) = factory.deployMultiMint(EXTENSION_NAME_YTO, params);

        assertTrue(proxy1 != proxy2);
        assertTrue(factory.isApprovedExtension(proxy1));
        assertTrue(factory.isApprovedExtension(proxy2));

        // Predict addresses correctly for each deployer
        assertEq(proxy1, factory.getExtensionAddress(address(this), EXTENSION_NAME_YTO));
        assertEq(proxy2, factory.getExtensionAddress(alice, EXTENSION_NAME_YTO));
    }

    /* ============ extensionType Tests ============ */

    function test_extensionType_noneForNonExtension() public view {
        assertEq(uint8(factory.getExtensionType(alice)), uint8(IExtensionFactory.ExtensionType.NONE));
        assertEq(uint8(factory.getExtensionType(address(0))), uint8(IExtensionFactory.ExtensionType.NONE));
    }

    function test_extensionType_correctPerDeployment() public {
        IExtensionFactory.YieldToOneParams memory yieldToOneParams = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        IExtensionFactory.MultiMintParams memory mmParams = IExtensionFactory.MultiMintParams({
            name: MM_NAME,
            symbol: MM_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: admin
        });

        (address yieldToOneProxy, , ) = factory.deployYieldToOne(string("yto-type-test"), yieldToOneParams);
        (address multiMintProxy, , ) = factory.deployMultiMint(string("mm-type-test"), mmParams);

        assertEq(uint8(factory.getExtensionType(yieldToOneProxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
        assertEq(uint8(factory.getExtensionType(multiMintProxy)), uint8(IExtensionFactory.ExtensionType.MULTI_MINT));
    }

    /* ============ setExtensionType Tests ============ */

    function test_setExtensionType() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        (address proxy, , ) = factory.deployYieldToOne(string("yto-status-test"), params);

        assertTrue(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));

        vm.expectEmit();
        emit IExtensionFactory.ExtensionTypeSet(proxy, IExtensionFactory.ExtensionType.NONE);

        vm.prank(factoryManager);
        factory.setExtensionType(proxy, IExtensionFactory.ExtensionType.NONE);

        assertFalse(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.NONE));
    }

    function test_setExtensionType_reactivate() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        (address proxy, , ) = factory.deployYieldToOne(string("yto-reactivate-test"), params);

        vm.prank(factoryManager);
        factory.setExtensionType(proxy, IExtensionFactory.ExtensionType.NONE);

        assertFalse(factory.isApprovedExtension(proxy));

        vm.expectEmit();
        emit IExtensionFactory.ExtensionTypeSet(proxy, IExtensionFactory.ExtensionType.YIELD_TO_ONE);

        vm.prank(factoryManager);
        factory.setExtensionType(proxy, IExtensionFactory.ExtensionType.YIELD_TO_ONE);

        assertTrue(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
    }

    function test_setExtensionType_idempotent() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        (address proxy, , ) = factory.deployYieldToOne(string("yto-idempotent-test"), params);

        // Already YIELD_TO_ONE, should not emit event
        vm.prank(factoryManager);
        factory.setExtensionType(proxy, IExtensionFactory.ExtensionType.YIELD_TO_ONE);

        assertTrue(factory.isApprovedExtension(proxy));
    }

    function test_setExtensionType_zeroExtension() public {
        vm.expectRevert(IExtensionFactory.ZeroExtension.selector);

        vm.prank(factoryManager);
        factory.setExtensionType(address(0), IExtensionFactory.ExtensionType.YIELD_TO_ONE);
    }

    function test_setExtensionType_invalidExtension() public {
        // Setting NONE on unregistered address is idempotent (no-op)
        vm.prank(factoryManager);
        factory.setExtensionType(alice, IExtensionFactory.ExtensionType.NONE);

        // Setting non-NONE on an invalid address reverts (EOA has no code)
        vm.expectRevert();

        vm.prank(factoryManager);
        factory.setExtensionType(alice, IExtensionFactory.ExtensionType.YIELD_TO_ONE);
    }

    function test_setExtensionType_notManager() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        (address proxy, , ) = factory.deployYieldToOne(string("yto-not-manager-test"), params);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                factory.FACTORY_MANAGER_ROLE()
            )
        );

        vm.prank(alice);
        factory.setExtensionType(proxy, IExtensionFactory.ExtensionType.NONE);
    }

    /* ============ setImplementation Tests ============ */

    function test_setImplementation_yieldToOne() public {
        address newImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));

        vm.expectEmit();
        emit IExtensionFactory.ImplementationSet(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);

        vm.prank(factoryManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);

        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE), newImpl);
    }

    function test_setImplementation_multiMint() public {
        address newImpl = address(new MultiMint(address(pyusdx), address(swapFacility)));

        vm.expectEmit();
        emit IExtensionFactory.ImplementationSet(IExtensionFactory.ExtensionType.MULTI_MINT, newImpl);

        vm.prank(factoryManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.MULTI_MINT, newImpl);

        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT), newImpl);
    }

    function test_setImplementation_proxyUsesNewImpl() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        // Deploy first proxy with original implementation
        (address proxy1, , ) = factory.deployYieldToOne(string("yto-impl-test-1"), params);

        // Set a new implementation
        address newImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));

        vm.prank(factoryManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);

        // Deploy second proxy - should use new implementation
        IExtensionFactory.YieldToOneParams memory params2 = IExtensionFactory.YieldToOneParams({
            name: "Second Token",
            symbol: "ST2",
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: admin,
            pauser: pauser
        });

        (address proxy2, , ) = factory.deployYieldToOne(string("yto-impl-test-2"), params2);

        assertEq(Upgrades.getImplementationAddress(proxy2), newImpl);

        // First proxy still uses original implementation
        assertTrue(Upgrades.getImplementationAddress(proxy1) != newImpl);
    }

    function test_setImplementation_notManager() public {
        address newImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                factory.FACTORY_MANAGER_ROLE()
            )
        );

        vm.prank(alice);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);
    }

    function test_setImplementation_invalidType() public {
        address newImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));

        vm.expectRevert(IExtensionFactory.InvalidExtensionType.selector);

        vm.prank(factoryManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.NONE, newImpl);
    }

    function test_setImplementation_invalidPyusdx() public {
        address wrongPyusdx = makeAddr("wrongPyusdx");
        address newImpl = address(new YieldToOne(wrongPyusdx, address(swapFacility)));

        vm.expectRevert(IExtensionFactory.InvalidExtension.selector);

        vm.prank(factoryManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);
    }

    function test_setImplementation_invalidSwapFacility() public {
        address wrongSwap = makeAddr("wrongSwap");
        address newImpl = address(new YieldToOne(address(pyusdx), wrongSwap));

        vm.expectRevert(IExtensionFactory.InvalidExtension.selector);

        vm.prank(factoryManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);
    }

    function test_setImplementation_zeroAddress() public {
        vm.expectRevert(IExtensionFactory.ZeroExtension.selector);

        vm.prank(factoryManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, address(0));
    }

    function test_setImplementation_eoa() public {
        vm.expectRevert();

        vm.prank(factoryManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, alice);
    }
}
