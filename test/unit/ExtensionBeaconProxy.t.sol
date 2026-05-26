// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { ERC1967Utils } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IERC1967 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { ExtensionBeacon } from "../../src/platform/ExtensionBeacon.sol";
import { ExtensionBeaconProxy } from "../../src/platform/ExtensionBeaconProxy.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";

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

    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant _ORIGIN_BEACON_SLOT = 0x0db096ce50da19b63b97b47df5b0c87e2ed1677b3d801ad424e1bbfc0bb0c300;

    function setUp() public override {
        super.setUp();

        pyusdx = new MockERC20("PYUSDX", "PYUSDX", 6);
        swapFacility = new MockSwapFacility(address(pyusdx));

        ytoImpl = new ExtensionHarness(address(pyusdx), address(swapFacility), 1);

        beacon = ExtensionBeacon(
            UnsafeUpgrades.deployTransparentProxy(
                address(new ExtensionBeacon(address(pyusdx), address(swapFacility))),
                admin,
                abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin, beaconManager, address(ytoImpl))
            )
        );
    }

    /* ============ Helper Functions ============ */

    function _deployProxy(string memory name_, string memory symbol_) internal returns (ExtensionBeaconProxy) {
        bytes memory initData = abi.encodeWithSelector(
            ExtensionHarness.initialize.selector,
            name_,
            symbol_,
            admin,
            freezeManager,
            pauser,
            versionManager
        );

        return new ExtensionBeaconProxy(address(beacon), initData);
    }

    /* ============ constructor ============ */

    function test_constructor_revertOnFailedInitializer() public {
        bytes memory malformedData = hex"deadbeef";

        vm.expectRevert();
        new ExtensionBeaconProxy(address(beacon), malformedData);
    }

    function test_constructor_revertOnNonContractBeacon() public {
        address eoa = makeAddr("eoa");

        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidBeacon.selector, eoa));
        new ExtensionBeaconProxy(eoa, "");
    }

    function test_constructor_revertOnNonContractImplementation() public {
        MockExtensionBeacon mockBeacon = new MockExtensionBeacon(address(0), address(0));
        address eoa = makeAddr("eoa");
        mockBeacon.setImplementation(eoa);

        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, eoa));
        new ExtensionBeaconProxy(address(mockBeacon), "");
    }

    function test_constructor() public {
        vm.expectEmit();
        emit IERC1967.BeaconUpgraded(address(beacon));

        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        // Verify beacon slot
        bytes32 slotValue = vm.load(address(proxy), _BEACON_SLOT);
        assertEq(address(uint160(uint256(slotValue))), address(beacon));

        // Verify origin beacon slot
        slotValue = vm.load(address(proxy), _ORIGIN_BEACON_SLOT);
        assertEq(address(uint160(uint256(slotValue))), address(beacon));

        // Verify implementation slot is empty (not pinned)
        slotValue = vm.load(address(proxy), _IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(slotValue))), address(0));

        // Verify initializer ran
        assertEq(ExtensionHarness(address(proxy)).name(), "Test YTO");
        assertEq(ExtensionHarness(address(proxy)).symbol(), "tYTO");

        ExtensionHarness proxyAsHarness = ExtensionHarness(address(proxy));
        assertTrue(proxyAsHarness.hasRole(proxyAsHarness.DEFAULT_ADMIN_ROLE(), admin));
    }

    /* ============ implementation resolution ============ */

    function test_implementation_resolvesViaBeacon() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        assertEq(IExtension(address(proxy)).pyusdx(), address(pyusdx));
        assertEq(IExtension(address(proxy)).swapFacility(), address(swapFacility));

        address beaconImpl = beacon.implementation();
        assertEq(beaconImpl, address(ytoImpl));
    }

    /* ============ upgrade propagation ============ */

    function test_upgrade_propagates() public {
        ExtensionBeaconProxy proxy1 = _deployProxy("Test YTO 1", "tYTO1");
        ExtensionBeaconProxy proxy2 = _deployProxy("Test YTO 2", "tYTO2");

        assertEq(ExtensionHarness(address(proxy1)).harnessVersion(), 1);
        assertEq(ExtensionHarness(address(proxy2)).harnessVersion(), 1);

        ExtensionHarness newImpl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(address(newImpl));

        assertEq(beacon.implementation(), address(newImpl));

        assertEq(ExtensionHarness(address(proxy1)).harnessVersion(), 2);
        assertEq(ExtensionHarness(address(proxy2)).harnessVersion(), 2);
    }

    /* ============ multi-proxy ============ */

    function test_multipleProxies_sameBeacon() public {
        ExtensionBeaconProxy proxy1 = _deployProxy("Test 1", "t1");
        ExtensionBeaconProxy proxy2 = _deployProxy("Test 2", "t2");

        // Both resolve to the same implementation
        address impl1 = beacon.implementation();
        address impl2 = beacon.implementation();

        assertEq(impl1, impl2);
        assertEq(impl1, address(ytoImpl));
    }

    /* ============ originBeacon ============ */

    function test_originBeacon_matchesBeaconInitially() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        assertEq(ExtensionHarness(address(proxy)).originBeacon(), address(beacon));
    }

    /* ============ pinVersion ============ */

    function test_pinVersion_notAdmin() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

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
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        vm.expectRevert(abi.encodeWithSelector(IExtensionBeacon.NoImplementationRegistered.selector));

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(99);
    }

    function test_pinVersion_zeroVersion() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        vm.expectRevert(IExtension.ZeroVersion.selector);

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(0);
    }

    function test_pinVersion() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        // Register v2 implementation
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(address(v2Impl));

        // Proxy follows latest (v2)
        assertFalse(ExtensionHarness(address(proxy)).isPinned());
        assertEq(ExtensionHarness(address(proxy)).pinnedImplementation(), address(0));
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 2);

        // Pin to v1
        vm.expectEmit();
        emit IERC1967.BeaconUpgraded(address(0));

        vm.expectEmit();
        emit IERC1967.Upgraded(address(ytoImpl));

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        // Verify storage: beacon slot cleared, implementation slot set
        bytes32 beaconSlot = vm.load(address(proxy), _BEACON_SLOT);
        assertEq(address(uint160(uint256(beaconSlot))), address(0));

        bytes32 implSlot = vm.load(address(proxy), _IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(implSlot))), address(ytoImpl));

        // Origin beacon unchanged
        bytes32 originSlot = vm.load(address(proxy), _ORIGIN_BEACON_SLOT);
        assertEq(address(uint160(uint256(originSlot))), address(beacon));

        assertTrue(ExtensionHarness(address(proxy)).isPinned());
        assertEq(ExtensionHarness(address(proxy)).pinnedImplementation(), address(ytoImpl));
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 1);
    }

    function test_pinVersion_pinnedIgnoresUpgrade() public {
        ExtensionBeaconProxy proxy1 = _deployProxy("Pinned", "PIN");
        ExtensionBeaconProxy proxy2 = _deployProxy("Unpinned", "UNP");

        // Pin proxy1 to v1
        vm.prank(versionManager);
        ExtensionHarness(address(proxy1)).pinVersion(1);

        // Register v2
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(address(v2Impl));

        // Pinned stays on v1, unpinned moves to v2
        assertEq(ExtensionHarness(address(proxy1)).harnessVersion(), 1);
        assertEq(ExtensionHarness(address(proxy2)).harnessVersion(), 2);
    }

    function test_pinVersion_repin() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        // Register v2
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(address(v2Impl));

        // Pin to v1
        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 1);

        // Re-pin directly to v2
        vm.expectEmit();
        emit IERC1967.BeaconUpgraded(address(0));

        vm.expectEmit();
        emit IERC1967.Upgraded(address(v2Impl));

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(2);

        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 2);
        assertEq(ExtensionHarness(address(proxy)).pinnedImplementation(), address(v2Impl));
        assertTrue(ExtensionHarness(address(proxy)).isPinned());
    }

    /* ============ unpinVersion ============ */

    function test_unpinVersion() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        // Register v2
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(address(v2Impl));

        // Pin to v1
        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 1);

        // Unpin
        vm.expectEmit();
        emit IERC1967.Upgraded(address(0));

        vm.expectEmit();
        emit IERC1967.BeaconUpgraded(address(beacon));

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).unpinVersion();

        // Verify storage: implementation slot cleared, beacon slot restored
        bytes32 implSlot = vm.load(address(proxy), _IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(implSlot))), address(0));

        bytes32 beaconSlot = vm.load(address(proxy), _BEACON_SLOT);
        assertEq(address(uint160(uint256(beaconSlot))), address(beacon));

        // Origin beacon unchanged
        assertEq(ExtensionHarness(address(proxy)).originBeacon(), address(beacon));

        assertFalse(ExtensionHarness(address(proxy)).isPinned());
        assertEq(ExtensionHarness(address(proxy)).pinnedImplementation(), address(0));

        // Now follows latest (v2)
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 2);
    }

    function test_unpinVersion_notPinned() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        vm.expectRevert(IExtension.NotPinned.selector);

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).unpinVersion();
    }

    function test_unpinVersion_notAdmin() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                ExtensionHarness(address(proxy)).VERSION_MANAGER_ROLE()
            )
        );

        vm.prank(alice);
        ExtensionHarness(address(proxy)).unpinVersion();
    }

    function test_unpinVersion_afterRepin() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(address(v2Impl));

        // Pin to v1, then re-pin to v2
        vm.startPrank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);
        ExtensionHarness(address(proxy)).pinVersion(2);
        vm.stopPrank();

        // Unpin
        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).unpinVersion();

        assertFalse(ExtensionHarness(address(proxy)).isPinned());
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 2);
        assertEq(ExtensionHarness(address(proxy)).originBeacon(), address(beacon));
    }

    /* ============ storage ============ */

    function test_originBeaconSlot_derivation() public pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXOriginBeacon")) - 1)) &
            ~bytes32(uint256(0xff));

        assertEq(expected, _ORIGIN_BEACON_SLOT);
    }

    /* ============ pinToLatest ============ */

    function test_pinVersion_pinToLatestThenUpgrade() public {
        ExtensionBeaconProxy proxy = _deployProxy("Test YTO", "tYTO");

        // Pin to v1 (currently the latest)
        vm.prank(versionManager);
        ExtensionHarness(address(proxy)).pinVersion(1);

        // Register v2
        ExtensionHarness v2Impl = new ExtensionHarness(address(pyusdx), address(swapFacility), 2);

        vm.prank(beaconManager);
        beacon.registerImplementation(address(v2Impl));

        // Still on v1 despite v2 being registered
        assertEq(ExtensionHarness(address(proxy)).harnessVersion(), 1);
    }
}
