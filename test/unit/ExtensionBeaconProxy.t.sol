// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { ERC1967Utils } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IERC1967 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { ExtensionBeacon } from "../../src/platform/ExtensionBeacon.sol";
import { ExtensionBeaconProxy } from "../../src/platform/ExtensionBeaconProxy.sol";
import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";

import { ExtensionHarness } from "../harness/ExtensionHarness.sol";

import { MockERC20 } from "../mock/MockERC20.sol";
import { MockExtensionBeacon } from "../mock/MockExtensionBeacon.sol";
import { MockSwapFacility } from "../mock/MockSwapFacility.sol";

import { BaseTest } from "../utils/BaseTest.sol";

contract ExtensionBeaconProxyTest is BaseTest {
    MockERC20 public pyusdx;
    MockSwapFacility public swapFacility;
    ExtensionBeacon public beacon;

    ExtensionHarness public ytoImpl;
    ExtensionHarness public mmImpl;

    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
    bytes32 internal constant _EXTENSION_TYPE_STORAGE_LOCATION =
        0x50809f8892663c0bc92e8283fda4cb9143fb961da9c4bc5652b13b5c450bbc00;
    bytes32 internal constant _PINNED_VERSION_STORAGE_LOCATION =
        0xfec66d3fc30888a287564007fecbbfaf6a964b972d5e0e57e4d8faceddbe2b00;

    function setUp() public override {
        super.setUp();

        pyusdx = new MockERC20("PYUSDX", "PYUSDX", 6);
        swapFacility = new MockSwapFacility(address(pyusdx));

        // Deploy actual extension implementations (with initialize functions)
        ytoImpl = new ExtensionHarness(address(pyusdx), address(swapFacility), 1);
        mmImpl = new ExtensionHarness(address(pyusdx), address(swapFacility), 1);

        // Deploy ExtensionBeacon behind TransparentProxy
        beacon = ExtensionBeacon(
            UnsafeUpgrades.deployTransparentProxy(
                address(new ExtensionBeacon(address(pyusdx), address(swapFacility))),
                admin,
                abi.encodeWithSelector(
                    ExtensionBeacon.initialize.selector,
                    admin,
                    beaconManager,
                    address(ytoImpl),
                    address(mmImpl)
                )
            )
        );
    }

    /* ============ Helper Functions ============ */

    function _deployYTOProxy(string memory name_, string memory symbol_) internal returns (ExtensionBeaconProxy) {
        bytes memory initData = abi.encodeWithSelector(
            ExtensionHarness.initialize.selector,
            name_,
            symbol_,
            admin,
            freezeManager,
            pauser,
            versionManager
        );

        return new ExtensionBeaconProxy(address(beacon), IExtensionBeacon.ExtensionType.YIELD_TO_ONE, initData);
    }

    function _deployMMProxy(string memory name_, string memory symbol_) internal returns (ExtensionBeaconProxy) {
        bytes memory initData = abi.encodeWithSelector(
            ExtensionHarness.initialize.selector,
            name_,
            symbol_,
            admin,
            freezeManager,
            pauser,
            versionManager
        );

        return new ExtensionBeaconProxy(address(beacon), IExtensionBeacon.ExtensionType.MULTI_MINT, initData);
    }

    /* ============ constructor ============ */

    function test_constructor_revertOnFailedInitializer() public {
        bytes memory malformedData = hex"deadbeef";

        vm.expectRevert();
        new ExtensionBeaconProxy(address(beacon), IExtensionBeacon.ExtensionType.YIELD_TO_ONE, malformedData);
    }

    function test_constructor_revertOnNonContractBeacon() public {
        address eoa = makeAddr("eoa");

        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidBeacon.selector, eoa));
        new ExtensionBeaconProxy(eoa, IExtensionBeacon.ExtensionType.YIELD_TO_ONE, "");
    }

    function test_constructor_revertOnNonContractImplementation() public {
        MockExtensionBeacon mockBeacon = new MockExtensionBeacon();
        address eoa = makeAddr("eoa");
        mockBeacon.setImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, eoa);

        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, eoa));
        new ExtensionBeaconProxy(address(mockBeacon), IExtensionBeacon.ExtensionType.YIELD_TO_ONE, "");
    }

    function test_constructor() public {
        vm.expectEmit();
        emit IERC1967.BeaconUpgraded(address(beacon));

        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        bytes32 slotValue = vm.load(address(proxy), _BEACON_SLOT);
        assertEq(address(uint160(uint256(slotValue))), address(beacon));

        slotValue = vm.load(address(proxy), _EXTENSION_TYPE_STORAGE_LOCATION);
        assertEq(uint256(slotValue), uint256(IExtensionBeacon.ExtensionType.YIELD_TO_ONE));

        slotValue = vm.load(address(proxy), _PINNED_VERSION_STORAGE_LOCATION);
        assertEq(uint256(slotValue), 0);

        assertEq(proxy.beacon(), address(beacon));
        assertEq(uint8(proxy.extensionType()), uint8(IExtensionBeacon.ExtensionType.YIELD_TO_ONE));

        assertEq(ExtensionHarness(address(proxy)).name(), "Test YTO");
        assertEq(ExtensionHarness(address(proxy)).symbol(), "tYTO");

        ExtensionHarness proxyAsHarness = ExtensionHarness(address(proxy));
        assertTrue(proxyAsHarness.hasRole(proxyAsHarness.DEFAULT_ADMIN_ROLE(), admin));
    }

    /* ============ implementation resolution ============ */

    function test_implementation_resolvesViaBeacon() public {
        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        // The proxy's _implementation() returns beacon.implementation(extensionType)
        // We verify by reading storage at the ERC-1967 implementation slot is NOT used
        // (beacon proxy doesn't use ERC-1967 impl slot, it resolves dynamically)
        // Instead, we can verify the proxy's code path works correctly

        // Call a function that requires the correct implementation to be resolved
        // If the proxy resolved to the wrong implementation, pyusdx() would return wrong value
        assertEq(IExtensionBeacon(address(proxy)).pyusdx(), address(pyusdx));
        assertEq(IExtensionBeacon(address(proxy)).swapFacility(), address(swapFacility));

        // The beacon's registered implementation matches what the proxy uses
        address beaconImpl = beacon.implementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE);
        assertEq(beaconImpl, address(ytoImpl));
    }

    /* ============ upgrade propagation ============ */

    function test_upgrade_propagates() public {
        ExtensionBeaconProxy proxy1 = _deployYTOProxy("Test YTO 1", "tYTO1");
        ExtensionBeaconProxy proxy2 = _deployYTOProxy("Test YTO 2", "tYTO2");

        // Proxies initially resolve to the v1 implementation
        assertEq(ExtensionHarness(address(proxy1)).harnessVersion(), 1);
        assertEq(ExtensionHarness(address(proxy2)).harnessVersion(), 1);

        // Deploy a v2 implementation and register it
        ExtensionHarness newImpl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, address(newImpl));

        // Beacon now points to v2
        assertEq(beacon.implementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE), address(newImpl));

        // Both proxies now resolve to v2, proving upgrade propagation
        assertEq(ExtensionHarness(address(proxy1)).harnessVersion(), 2);
        assertEq(ExtensionHarness(address(proxy2)).harnessVersion(), 2);
    }

    /* ============ multi-proxy ============ */

    function test_multipleProxies_sameType() public {
        ExtensionBeaconProxy proxy1 = _deployYTOProxy("Test YTO 1", "tYTO1");
        ExtensionBeaconProxy proxy2 = _deployYTOProxy("Test YTO 2", "tYTO2");

        // Both proxies resolve to the same implementation
        address impl1 = beacon.implementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE);
        address impl2 = beacon.implementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE);

        assertEq(impl1, impl2);
        assertEq(impl1, address(ytoImpl));

        // Both have the same beacon
        assertEq(proxy1.beacon(), proxy2.beacon());
        assertEq(uint8(proxy1.extensionType()), uint8(proxy2.extensionType()));
    }

    function test_differentTypes_differentImpls() public {
        ExtensionBeaconProxy ytoProxy = _deployYTOProxy("Test YTO", "tYTO");
        ExtensionBeaconProxy mmProxy = _deployMMProxy("Test MM", "tMM");

        address ytoImplAddr = beacon.implementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE);
        address mmImplAddr = beacon.implementation(IExtensionBeacon.ExtensionType.MULTI_MINT);

        assertTrue(ytoImplAddr != mmImplAddr);
        assertEq(ytoImplAddr, address(ytoImpl));
        assertEq(mmImplAddr, address(mmImpl));

        // Verify extension types differ
        assertTrue(ytoProxy.extensionType() != mmProxy.extensionType());
    }

    /* ============ pinnedVersion ============ */

    function test_pinnedVersion_defaultZero() public {
        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        assertEq(ExtensionHarness(address(proxy)).pinnedVersion(), 0);
    }

    /* ============ pinVersion ============ */

    function test_pinVersion_notAdmin() public {
        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                ExtensionHarness(address(proxy)).VERSION_MANAGER_ROLE()
            )
        );

        vm.prank(alice);
        ExtensionHarness(address(proxy)).pinVersion(1);
    }

    function test_pinVersion_nonExistentVersion() public {
        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        vm.expectRevert(abi.encodeWithSelector(IExtensionBeacon.NoImplementationRegistered.selector));

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(99);
    }

    function test_pinVersion() public {
        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        // Register v2 implementation
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, address(v2Impl));

        // Proxy follows latest (v2)
        assertEq(ExtensionHarness(address(proxy)).pinnedVersion(), 0);
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 2);

        // Pin to v1
        vm.expectEmit();
        emit IExtension.VersionPinned(1);

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        bytes32 slotValue = vm.load(address(proxy), _PINNED_VERSION_STORAGE_LOCATION);
        assertEq(uint256(slotValue), 1);

        assertEq(ExtensionHarness(address(proxy)).pinnedVersion(), 1);
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 1);
    }

    function test_pinVersion_pinnedIgnoresUpgrade() public {
        ExtensionBeaconProxy proxy1 = _deployYTOProxy("Pinned", "PIN");
        ExtensionBeaconProxy proxy2 = _deployYTOProxy("Unpinned", "UNP");

        // Pin proxy1 to v1
        vm.prank(versionManager);
        ExtensionHarness(address(proxy1)).pinVersion(1);

        // Register v2
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, address(v2Impl));

        // Pinned stays on v1, unpinned moves to v2
        assertEq(ExtensionHarness(address(proxy1)).harnessVersion(), 1);
        assertEq(ExtensionHarness(address(proxy2)).harnessVersion(), 2);
    }

    function test_pinVersion_repin() public {
        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        // Register v2
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, address(v2Impl));

        // Pin to v1
        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 1);

        // Re-pin directly to v2
        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(2);

        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 2);
        assertEq(ExtensionHarness(address(proxy)).pinnedVersion(), 2);
    }

    function test_pinVersion_unpin() public {
        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        // Register v2
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, address(v2Impl));

        // Pin to v1
        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 1);

        // Unpin (version 0)
        vm.expectEmit();
        emit IExtension.VersionPinned(0);

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(0);

        assertEq(ExtensionHarness(address(proxy)).pinnedVersion(), 0);

        // Now follows latest (v2)
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 2);
    }

    function test_pinVersion_pinToLatestThenUpgrade() public {
        ExtensionBeaconProxy proxy = _deployYTOProxy("Test YTO", "tYTO");

        // Pin to v1 (currently the latest)
        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        // Register v2
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, address(v2Impl));

        // Still on v1 despite v2 being registered
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 1);
    }
}
