// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";
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
        new ExtensionFactory(address(0), address(swapFacility), address(extensionBeacon));
    }

    function test_constructor_zeroSwapFacility() public {
        vm.expectRevert(IExtensionFactory.ZeroSwapFacility.selector);
        new ExtensionFactory(address(pyusdx), address(0), address(extensionBeacon));
    }

    function test_constructor_zeroBeacon() public {
        vm.expectRevert(IExtensionFactory.ZeroExtensionBeacon.selector);
        new ExtensionFactory(address(pyusdx), address(swapFacility), address(0));
    }

    function test_initialize_zeroAdmin() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(extensionBeacon)));

        vm.expectRevert(IExtensionFactory.ZeroAdmin.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(ExtensionFactory.initialize.selector, address(0), factoryManager)
        );
    }

    function test_initialize_zeroFactoryManager() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(extensionBeacon)));

        vm.expectRevert(IExtensionFactory.ZeroFactoryManager.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(ExtensionFactory.initialize.selector, admin, address(0))
        );
    }

    function test_initialState() public view {
        assertEq(factory.pyusdx(), address(pyusdx));
        assertEq(factory.swapFacility(), address(swapFacility));
        assertEq(factory.extensionBeacon(), address(extensionBeacon));

        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(factory.hasRole(factory.FACTORY_MANAGER_ROLE(), factoryManager));

        assertTrue(factory.getImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE) != address(0));
        assertTrue(factory.getImplementation(IExtensionBeacon.ExtensionType.MULTI_MINT) != address(0));

        assertEq(uint8(IExtensionBeacon.ExtensionType.NONE), uint8(0));
        assertEq(uint8(IExtensionBeacon.ExtensionType.YIELD_TO_ONE), uint8(1));
        assertEq(uint8(IExtensionBeacon.ExtensionType.MULTI_MINT), uint8(2));
    }

    function test_initialize_alreadyInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        factory.initialize(admin, factoryManager);
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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        (address proxy, address implementation) = factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        assertTrue(proxy != address(0));
        assertTrue(implementation != address(0));

        // Verify extension is registered
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionBeacon.ExtensionType.YIELD_TO_ONE));
        assertTrue(factory.isApprovedExtension(proxy));
        assertTrue(swapFacility.isApprovedExtension(proxy));

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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        // Same deployer + same extensionName reverts
        vm.expectRevert();
        factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        // Different deployer + same extensionName succeeds
        vm.prank(alice);
        (address proxy, ) = factory.deployYieldToOne(EXTENSION_NAME_YTO, params);
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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        // Different extensionName produces different address
        (address proxy2, ) = factory.deployYieldToOne(string("YTO-002"), params);

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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        IExtensionFactory.YieldToOneParams memory params2 = IExtensionFactory.YieldToOneParams({
            name: "Ext2",
            symbol: "E2",
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        (, address impl1) = factory.deployYieldToOne(string("YTO-A"), params1);
        (, address impl2) = factory.deployYieldToOne(string("YTO-B"), params2);

        // Both should return the same implementation from the beacon
        assertEq(impl1, impl2);
        assertEq(factory.getImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE), impl1);
    }

    function test_deployYieldToOne_predictedAddress() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        // Deploy from test contract (address(this))
        (address proxy1, ) = factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

        // Same extension name from different deployer should produce different address
        vm.prank(alice);
        (address proxy2, ) = factory.deployYieldToOne(EXTENSION_NAME_YTO, params);

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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        (address proxy, address implementation) = factory.deployMultiMint(EXTENSION_NAME_MM, params);

        assertTrue(proxy != address(0));
        assertTrue(implementation != address(0));

        // Verify extension is registered
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionBeacon.ExtensionType.MULTI_MINT));
        assertTrue(factory.isApprovedExtension(proxy));
        assertTrue(swapFacility.isApprovedExtension(proxy));

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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        factory.deployMultiMint(EXTENSION_NAME_MM, params);

        // Same deployer + same extensionName reverts
        vm.expectRevert();
        factory.deployMultiMint(EXTENSION_NAME_MM, params);

        // Different deployer + same extensionName succeeds
        vm.prank(alice);
        (address proxy, ) = factory.deployMultiMint(EXTENSION_NAME_MM, params);
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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        IExtensionFactory.MultiMintParams memory params2 = IExtensionFactory.MultiMintParams({
            name: "MM2",
            symbol: "M2",
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        (, address impl1) = factory.deployMultiMint(string("MM-A"), params1);
        (, address impl2) = factory.deployMultiMint(string("MM-B"), params2);

        assertEq(impl1, impl2);
        assertEq(factory.getImplementation(IExtensionBeacon.ExtensionType.MULTI_MINT), impl1);
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
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        // Deploy from test contract (address(this))
        (address proxy1, ) = factory.deployMultiMint(EXTENSION_NAME_YTO, params);

        // Same extension name from different deployer should produce different address
        vm.prank(alice);
        (address proxy2, ) = factory.deployMultiMint(EXTENSION_NAME_YTO, params);

        assertTrue(proxy1 != proxy2);
        assertTrue(factory.isApprovedExtension(proxy1));
        assertTrue(factory.isApprovedExtension(proxy2));

        // Predict addresses correctly for each deployer
        assertEq(proxy1, factory.getExtensionAddress(address(this), EXTENSION_NAME_YTO));
        assertEq(proxy2, factory.getExtensionAddress(alice, EXTENSION_NAME_YTO));
    }

    /* ============ extensionType Tests ============ */

    function test_extensionType_noneForNonExtension() public view {
        assertEq(uint8(factory.getExtensionType(alice)), uint8(IExtensionBeacon.ExtensionType.NONE));
        assertEq(uint8(factory.getExtensionType(address(0))), uint8(IExtensionBeacon.ExtensionType.NONE));
    }

    function test_extensionType_correctPerDeployment() public {
        IExtensionFactory.YieldToOneParams memory yieldToOneParams = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        IExtensionFactory.MultiMintParams memory mmParams = IExtensionFactory.MultiMintParams({
            name: MM_NAME,
            symbol: MM_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        (address yieldToOneProxy, ) = factory.deployYieldToOne(string("yto-type-test"), yieldToOneParams);
        (address multiMintProxy, ) = factory.deployMultiMint(string("mm-type-test"), mmParams);

        assertEq(uint8(factory.getExtensionType(yieldToOneProxy)), uint8(IExtensionBeacon.ExtensionType.YIELD_TO_ONE));
        assertEq(uint8(factory.getExtensionType(multiMintProxy)), uint8(IExtensionBeacon.ExtensionType.MULTI_MINT));
    }

    /* ============ setExtensionType Tests ============ */

    function test_setExtensionType() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        (address proxy, ) = factory.deployYieldToOne(string("yto-status-test"), params);

        assertTrue(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionBeacon.ExtensionType.YIELD_TO_ONE));

        vm.expectEmit();
        emit IExtensionFactory.ExtensionTypeSet(proxy, IExtensionBeacon.ExtensionType.NONE);

        vm.prank(factoryManager);
        factory.setExtensionType(proxy, IExtensionBeacon.ExtensionType.NONE);

        assertFalse(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionBeacon.ExtensionType.NONE));
    }

    function test_setExtensionType_reactivate() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        (address proxy, ) = factory.deployYieldToOne(string("yto-reactivate-test"), params);

        vm.prank(factoryManager);
        factory.setExtensionType(proxy, IExtensionBeacon.ExtensionType.NONE);

        assertFalse(factory.isApprovedExtension(proxy));

        vm.expectEmit();
        emit IExtensionFactory.ExtensionTypeSet(proxy, IExtensionBeacon.ExtensionType.YIELD_TO_ONE);

        vm.prank(factoryManager);
        factory.setExtensionType(proxy, IExtensionBeacon.ExtensionType.YIELD_TO_ONE);

        assertTrue(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionBeacon.ExtensionType.YIELD_TO_ONE));
    }

    function test_setExtensionType_idempotent() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        (address proxy, ) = factory.deployYieldToOne(string("yto-idempotent-test"), params);

        // Already YIELD_TO_ONE, should not emit event
        vm.prank(factoryManager);
        factory.setExtensionType(proxy, IExtensionBeacon.ExtensionType.YIELD_TO_ONE);

        assertTrue(factory.isApprovedExtension(proxy));
    }

    function test_setExtensionType_zeroExtension() public {
        vm.expectRevert(IExtensionFactory.ZeroExtension.selector);

        vm.prank(factoryManager);
        factory.setExtensionType(address(0), IExtensionBeacon.ExtensionType.YIELD_TO_ONE);
    }

    function test_setExtensionType_invalidExtension() public {
        // Setting NONE on unregistered address is idempotent (no-op)
        vm.prank(factoryManager);
        factory.setExtensionType(alice, IExtensionBeacon.ExtensionType.NONE);

        // Setting non-NONE on an invalid address reverts (EOA has no code)
        vm.expectRevert();

        vm.prank(factoryManager);
        factory.setExtensionType(alice, IExtensionBeacon.ExtensionType.YIELD_TO_ONE);
    }

    function test_setExtensionType_notManager() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        (address proxy, ) = factory.deployYieldToOne(string("yto-not-manager-test"), params);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                factory.FACTORY_MANAGER_ROLE()
            )
        );

        vm.prank(alice);
        factory.setExtensionType(proxy, IExtensionBeacon.ExtensionType.NONE);
    }

    /* ============ Beacon Integration Tests ============ */

    function test_extensionBeacon_getter() public view {
        assertEq(factory.extensionBeacon(), address(extensionBeacon));
    }

    function test_getImplementation_delegatesToBeacon() public view {
        assertEq(
            factory.getImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE),
            extensionBeacon.implementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE)
        );
        assertEq(
            factory.getImplementation(IExtensionBeacon.ExtensionType.MULTI_MINT),
            extensionBeacon.implementation(IExtensionBeacon.ExtensionType.MULTI_MINT)
        );
    }

    function test_deployYieldToOne_beaconProxy() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        (address proxy, ) = factory.deployYieldToOne(string("yto-beacon-test"), params);

        // Verify beacon slot is set
        bytes32 beaconSlot = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
        bytes32 beaconValue = vm.load(proxy, beaconSlot);
        assertEq(address(uint160(uint256(beaconValue))), address(extensionBeacon));

        // Verify no admin slot (not a TUP)
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 adminValue = vm.load(proxy, adminSlot);
        assertEq(adminValue, bytes32(0));
    }

    function test_deployYieldToOne_event() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        address expectedImpl = extensionBeacon.implementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE);

        vm.expectEmit();
        emit IExtensionFactory.ExtensionDeployed(
            IExtensionBeacon.ExtensionType.YIELD_TO_ONE,
            factory.getExtensionAddress(address(this), string("yto-event-test")),
            expectedImpl,
            address(this)
        );

        factory.deployYieldToOne(string("yto-event-test"), params);
    }

    function test_deployYieldToOne_wiring() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        (address proxy, ) = factory.deployYieldToOne(string("yto-wiring-test"), params);

        assertEq(IExtension(proxy).pyusdx(), address(pyusdx));
        assertEq(IExtension(proxy).swapFacility(), address(swapFacility));
    }

    function test_deployYieldToOne_approvalInSwapFacility() public {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        (address proxy, ) = factory.deployYieldToOne(string("yto-approval-test"), params);

        assertTrue(swapFacility.isApprovedExtension(proxy));
    }

    /* ============ Atomic Upgrade Tests ============ */

    function test_registerImplementation_atomicUpgrade() public {
        // Deploy 2 YieldToOne proxies
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: YTO_NAME,
            symbol: YTO_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        (address proxy1, address v1Impl) = factory.deployYieldToOne(string("yto-atomic-1"), params);
        vm.prank(alice);
        (address proxy2, ) = factory.deployYieldToOne(string("yto-atomic-2"), params);

        // Record the V1 implementation
        address originalImpl = factory.getImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE);
        assertEq(originalImpl, v1Impl);

        // Deploy a new V2 YieldToOne implementation
        address v2Impl = address(new YieldToOne(address(pyusdx), address(swapFacility)));

        // Register the V2 implementation in the beacon (factoryManager has BEACON_MANAGER_ROLE)
        vm.prank(factoryManager);
        extensionBeacon.registerImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, v2Impl);

        // Verify the beacon now returns V2 as the latest implementation
        assertEq(extensionBeacon.implementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE), v2Impl);
        assertEq(extensionBeacon.latestVersion(IExtensionBeacon.ExtensionType.YIELD_TO_ONE), 2);

        // Verify factory's getImplementation also reflects the new V2
        assertEq(factory.getImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE), v2Impl);

        // Verify both proxies now resolve to V2 through the beacon
        // Read implementation via ERC-1967 beacon slot → beacon → implementation(type)
        bytes32 beaconSlot = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

        // Both proxies should have the beacon in their beacon slot
        bytes32 beaconValue1 = vm.load(proxy1, beaconSlot);
        bytes32 beaconValue2 = vm.load(proxy2, beaconSlot);
        assertEq(address(uint160(uint256(beaconValue1))), address(extensionBeacon));
        assertEq(address(uint160(uint256(beaconValue2))), address(extensionBeacon));

        // Both proxies now use V2 through beacon delegation
        // Verify by calling a view function that executes through the proxy
        assertEq(IExtension(proxy1).pyusdx(), address(pyusdx));
        assertEq(IExtension(proxy2).pyusdx(), address(pyusdx));
    }

    /* ============ Removed Function Tests ============ */

    function test_noSetImplementation() public {
        // setImplementation(uint8,address) — the function was removed from the modified factory.
        // A low-level staticcall with its selector must fail (no match).
        bytes4 selector = bytes4(keccak256("setImplementation(uint8,address)"));

        (bool success, ) = address(factory).staticcall(
            abi.encodeWithSelector(selector, uint8(IExtensionBeacon.ExtensionType.YIELD_TO_ONE), makeAddr("impl"))
        );

        assertFalse(success, "setImplementation should not exist on modified factory");
    }

    /* ============ Storage Layout Tests ============ */

    function test_storageLayout_noImplFields() public view {
        // Verify that ExtensionFactoryStorage struct only contains extensionTypes mapping
        // and does not have yieldToOneImplementation or multiMintImplementation fields.
        // If those fields existed, they would occupy slots at base+1 and base+2.
        // Since they've been removed, those slots must be zero.
        bytes32 base = 0xa4153a6682de332cda5838d23ee5e88a3b57ff66d9351fa396c29717c1349400;

        // Slot at base+1 would be yieldToOneImplementation — must be zero
        bytes32 slot1 = bytes32(uint256(base) + 1);
        assertEq(vm.load(address(factory), slot1), bytes32(0), "slot base+1 should be zero (no yieldToOneImpl)");

        // Slot at base+2 would be multiMintImplementation — must be zero
        bytes32 slot2 = bytes32(uint256(base) + 2);
        assertEq(vm.load(address(factory), slot2), bytes32(0), "slot base+2 should be zero (no multiMintImpl)");
    }

    /* ============ Beacon TUP Deployment Tests ============ */

    function test_beacon_deployedAsTUP() public view {
        // Verify ExtensionBeacon is deployed behind a TransparentUpgradeableProxy.
        // ERC-1967 implementation slot: 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implValue = vm.load(address(extensionBeacon), implSlot);
        assertTrue(uint256(implValue) != 0, "ERC-1967 implementation slot must be non-zero (TUP)");

        // ERC-1967 admin slot: 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 adminValue = vm.load(address(extensionBeacon), adminSlot);
        assertTrue(uint256(adminValue) != 0, "ERC-1967 admin slot must be non-zero (TUP)");
    }

    /* ============ MultiMint Beacon Proxy Tests ============ */

    function test_deployMultiMint_beaconProxy() public {
        IExtensionFactory.MultiMintParams memory params = IExtensionFactory.MultiMintParams({
            name: MM_NAME,
            symbol: MM_SYMBOL,
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        (address proxy, ) = factory.deployMultiMint(string("mm-beacon-test"), params);

        // Verify beacon slot is set
        bytes32 beaconSlot = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
        bytes32 beaconValue = vm.load(proxy, beaconSlot);
        assertEq(address(uint160(uint256(beaconValue))), address(extensionBeacon));

        // Verify no admin slot (not a TUP)
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 adminValue = vm.load(proxy, adminSlot);
        assertEq(adminValue, bytes32(0));
    }
}
