// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { UnsafeUpgrades, Upgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";
import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract PYUSDXExtensionFactoryUnitTests is PYUSDXBaseUnitTest {
    ExtensionFactory public factory;
    SwapFacility public swapFacility;

    // Role addresses
    address public extensionManager = makeAddr("extensionManager");

    // Test constants
    string public constant YTO_NAME = "Test YieldToOne";
    string public constant YTO_SYMBOL = "TYTO";
    string public constant MULTIMINT_NAME = "Test MultiMint";
    string public constant MULTIMINT_SYMBOL = "TMM";

    function setUp() public override {
        super.setUp();

        // Predict factory proxy address
        // After super.setUp(), nonce is 4
        // new SwapFacility impl: 4 -> 5
        // deployTransparentProxy: 5 -> 6 (only 1 nonce)
        // new Factory impl: 6 -> 7
        // deployTransparentProxy: 7 -> 8
        // Factory proxy is at nonce 7 = 4 + 3

        uint64 nonceBeforeDeployments = vm.getNonce(address(this));
        address predictedFactory = vm.computeCreateAddress(address(this), nonceBeforeDeployments + 3);

        // Deploy SwapFacility with predicted factory address
        swapFacility = SwapFacility(
            UnsafeUpgrades.deployTransparentProxy(
                address(new SwapFacility(address(pyusdx), predictedFactory)),
                admin,
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin, pauser)
            )
        );

        // Deploy factory with actual SwapFacility address
        factory = ExtensionFactory(
            UnsafeUpgrades.deployTransparentProxy(
                address(new ExtensionFactory(address(pyusdx), address(swapFacility))),
                admin,
                abi.encodeWithSelector(ExtensionFactory.initialize.selector, admin, extensionManager)
            )
        );

        // Verify prediction was correct
        assertEq(address(factory), predictedFactory, "Factory address prediction failed");
    }

    /* ============ Constructor Tests ============ */

    function test_constructor_zeroPyusdx() public {
        vm.expectRevert(IExtensionFactory.ZeroPYUSDX.selector);
        new ExtensionFactory(address(0), address(swapFacility));
    }

    function test_constructor_zeroSwapFacility() public {
        vm.expectRevert(IExtensionFactory.ZeroSwapFacility.selector);
        new ExtensionFactory(address(pyusdx), address(0));
    }

    function test_initialize_zeroAdmin() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility)));
        vm.expectRevert(IExtensionFactory.ZeroAdmin.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(ExtensionFactory.initialize.selector, address(0), extensionManager)
        );
    }

    function test_initialize_zeroFactoryManager() public {
        address impl = address(new ExtensionFactory(address(pyusdx), address(swapFacility)));
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

        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(factory.hasRole(factory.FACTORY_MANAGER_ROLE(), extensionManager));

        assertTrue(factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE) != address(0));
        assertTrue(factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT) != address(0));
    }

    function test_initialize_alreadyInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        factory.initialize(admin, extensionManager);
    }

    /* ============ deployYieldToOne Tests ============ */

    function test_deployYieldToOne() public {
        (address proxy, address proxyAdmin, address implementation) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser
        );

        assertTrue(proxy != address(0));
        assertTrue(proxyAdmin != address(0));
        assertTrue(implementation != address(0));

        // Verify extension is registered
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
        assertTrue(factory.isApprovedExtension(proxy));

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

    function test_deployYieldToOne_permissionless() public {
        vm.prank(alice);
        (address proxy, , ) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        assertTrue(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
    }

    function test_deployYieldToOne_duplicateReverts() public {
        factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser
        );

        // CREATE2 reverts when deploying with identical params from the same msg.sender
        vm.expectRevert();
        factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser
        );
    }

    function test_deployYieldToOne_differentSenderDoesNotCollide() public {
        factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser
        );

        // Different msg.sender produces a different salt, so no collision
        vm.prank(alice);
        (address proxy2, , ) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        assertTrue(factory.isApprovedExtension(proxy2));
    }

    function test_deployYieldToOne_sharedImplementation() public {
        (, , address impl1) = factory.deployYieldToOne(
            "Ext1",
            "E1",
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser
        );

        (, , address impl2) = factory.deployYieldToOne(
            "Ext2",
            "E2",
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser
        );

        assertEq(impl1, impl2);
        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE), impl1);
    }

    /* ============ deployMultiMint Tests ============ */

    function test_deployMultiMint() public {
        (address proxy, address proxyAdmin, address implementation) = factory.deployMultiMint(
            MULTIMINT_NAME,
            MULTIMINT_SYMBOL,
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            yieldRecipientManager
        );

        assertTrue(proxy != address(0));
        assertTrue(proxyAdmin != address(0));
        assertTrue(implementation != address(0));

        // Verify extension is registered
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.MULTI_MINT));
        assertTrue(factory.isApprovedExtension(proxy));

        // Verify storage
        assertEq(Upgrades.getImplementationAddress(proxy), implementation);

        // Verify ProxyAdmin matches ERC-1967 admin slot
        assertEq(proxyAdmin, Upgrades.getAdminAddress(proxy));

        // Verify token metadata
        assertEq(MultiMint(proxy).name(), MULTIMINT_NAME);
        assertEq(MultiMint(proxy).symbol(), MULTIMINT_SYMBOL);
        assertEq(MultiMint(proxy).yieldRecipient(), yieldRecipient);

        // Verify wiring
        assertEq(IExtension(proxy).pyusdx(), address(pyusdx));
        assertEq(IExtension(proxy).swapFacility(), address(swapFacility));
    }

    function test_deployMultiMint_permissionless() public {
        vm.prank(alice);
        (address proxy, , ) = factory.deployMultiMint(
            MULTIMINT_NAME,
            MULTIMINT_SYMBOL,
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );

        assertTrue(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.MULTI_MINT));
    }

    function test_deployMultiMint_duplicateReverts() public {
        factory.deployMultiMint(
            MULTIMINT_NAME,
            MULTIMINT_SYMBOL,
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );

        // CREATE2 reverts when deploying with identical params from the same msg.sender
        vm.expectRevert();
        factory.deployMultiMint(
            MULTIMINT_NAME,
            MULTIMINT_SYMBOL,
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );
    }

    function test_deployMultiMint_sharedImplementation() public {
        (, , address impl1) = factory.deployMultiMint(
            "MM1",
            "M1",
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );

        (, , address impl2) = factory.deployMultiMint(
            "MM2",
            "M2",
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );

        assertEq(impl1, impl2);
        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT), impl1);
    }

    /* ============ extensionType Tests ============ */

    function test_extensionType_noneForNonExtension() public view {
        assertEq(uint8(factory.getExtensionType(alice)), uint8(IExtensionFactory.ExtensionType.NONE));
        assertEq(uint8(factory.getExtensionType(address(0))), uint8(IExtensionFactory.ExtensionType.NONE));
    }

    function test_extensionType_correctPerDeployment() public {
        (address ytoProxy, , ) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        (address mmProxy, , ) = factory.deployMultiMint(
            MULTIMINT_NAME,
            MULTIMINT_SYMBOL,
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );

        assertEq(uint8(factory.getExtensionType(ytoProxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
        assertEq(uint8(factory.getExtensionType(mmProxy)), uint8(IExtensionFactory.ExtensionType.MULTI_MINT));
    }

    /* ============ setExtensionStatus Tests ============ */

    function test_setExtensionStatus() public {
        (address proxy, , ) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        assertTrue(factory.isApprovedExtension(proxy));

        vm.expectEmit();
        emit IExtensionFactory.ExtensionStatusSet(proxy, false);

        vm.prank(extensionManager);
        factory.setExtensionStatus(proxy, false);

        assertFalse(factory.isApprovedExtension(proxy));

        // Type is preserved even when inactive
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
    }

    function test_setExtensionStatus_reactivate() public {
        (address proxy, , ) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        vm.prank(extensionManager);
        factory.setExtensionStatus(proxy, false);

        assertFalse(factory.isApprovedExtension(proxy));

        vm.expectEmit();
        emit IExtensionFactory.ExtensionStatusSet(proxy, true);

        vm.prank(extensionManager);
        factory.setExtensionStatus(proxy, true);

        assertTrue(factory.isApprovedExtension(proxy));
        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
    }

    function test_setExtensionStatus_idempotent() public {
        (address proxy, , ) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        // Already active, should not emit event
        vm.prank(extensionManager);
        factory.setExtensionStatus(proxy, true);

        assertTrue(factory.isApprovedExtension(proxy));
    }

    function test_setExtensionStatus_notRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(IExtensionFactory.ExtensionNotRegistered.selector, alice));

        vm.prank(extensionManager);
        factory.setExtensionStatus(alice, true);
    }

    function test_setExtensionStatus_notManager() public {
        (address proxy, , ) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                factory.FACTORY_MANAGER_ROLE()
            )
        );

        vm.prank(alice);
        factory.setExtensionStatus(proxy, false);
    }

    /* ============ setImplementation Tests ============ */

    function test_setImplementation_yto() public {
        // Deploy a new YieldToOne implementation
        address newImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));

        vm.expectEmit();
        emit IExtensionFactory.ImplementationSet(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);

        vm.prank(extensionManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);

        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE), newImpl);
    }

    function test_setImplementation_multiMint() public {
        // Deploy a new MultiMint implementation
        address newImpl = address(new MultiMint(address(pyusdx), address(swapFacility)));

        vm.expectEmit();
        emit IExtensionFactory.ImplementationSet(IExtensionFactory.ExtensionType.MULTI_MINT, newImpl);

        vm.prank(extensionManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.MULTI_MINT, newImpl);

        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT), newImpl);
    }

    function test_setImplementation_proxyUsesNewImpl() public {
        // Deploy first proxy with original implementation
        (address proxy1, , ) = factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        // Set a new implementation
        address newImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        vm.prank(extensionManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);

        // Deploy second proxy - should use new implementation
        (address proxy2, , ) = factory.deployYieldToOne(
            "Second Token",
            "ST2",
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

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

        vm.prank(extensionManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.NONE, newImpl);
    }

    function test_setImplementation_invalidPyusdx() public {
        // Deploy with wrong pyusdx
        address wrongPyusdx = makeAddr("wrongPyusdx");
        address newImpl = address(new YieldToOne(wrongPyusdx, address(swapFacility)));

        vm.expectRevert(IExtensionFactory.InvalidImplementation.selector);

        vm.prank(extensionManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);
    }

    function test_setImplementation_invalidSwapFacility() public {
        // Deploy with wrong swapFacility
        address wrongSwap = makeAddr("wrongSwap");
        address newImpl = address(new YieldToOne(address(pyusdx), wrongSwap));

        vm.expectRevert(IExtensionFactory.InvalidImplementation.selector);

        vm.prank(extensionManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, newImpl);
    }

    function test_setImplementation_zeroAddress() public {
        // Calling pyusdx() on address(0) returns empty data, which causes a low-level failure
        vm.expectRevert();

        vm.prank(extensionManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, address(0));
    }

    function test_setImplementation_eoa() public {
        // Calling pyusdx() on an EOA returns empty data, which causes a low-level failure
        vm.expectRevert();

        vm.prank(extensionManager);
        factory.setImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE, alice);
    }

    /* ============ View Function Tests ============ */

    function test_getImplementation() public view {
        // Implementations are set at initialization
        assertTrue(factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE) != address(0));
        assertTrue(factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT) != address(0));
        // NONE always returns address(0)
        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.NONE), address(0));
    }

    function test_getImplementation_returnsSameAfterDeploys() public {
        address ytoImplBefore = factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE);
        address mmImplBefore = factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT);

        factory.deployYieldToOne(
            YTO_NAME,
            YTO_SYMBOL,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser
        );

        factory.deployMultiMint(
            MULTIMINT_NAME,
            MULTIMINT_SYMBOL,
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );

        // Implementations remain the same after deployments
        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.YIELD_TO_ONE), ytoImplBefore);
        assertEq(factory.getImplementation(IExtensionFactory.ExtensionType.MULTI_MINT), mmImplBefore);
    }

    /* ============ Integration-like Tests ============ */

    function test_multipleExtensions() public {
        (address proxy1, , ) = factory.deployYieldToOne(
            "Extension 1",
            "EXT1",
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        (address proxy2, , ) = factory.deployYieldToOne(
            "Extension 2",
            "EXT2",
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );

        (address proxy3, , ) = factory.deployMultiMint(
            "Extension 3",
            "EXT3",
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );

        assertEq(uint8(factory.getExtensionType(proxy1)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
        assertEq(uint8(factory.getExtensionType(proxy2)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
        assertEq(uint8(factory.getExtensionType(proxy3)), uint8(IExtensionFactory.ExtensionType.MULTI_MINT));

        assertTrue(factory.isApprovedExtension(proxy1));
        assertTrue(factory.isApprovedExtension(proxy2));
        assertTrue(factory.isApprovedExtension(proxy3));

        // Deactivate proxy2
        vm.prank(extensionManager);
        factory.setExtensionStatus(proxy2, false);

        assertTrue(factory.isApprovedExtension(proxy1));
        assertFalse(factory.isApprovedExtension(proxy2)); // inactive
        assertTrue(factory.isApprovedExtension(proxy3));

        // Type preserved after deactivation
        assertEq(uint8(factory.getExtensionType(proxy2)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));
    }
}
