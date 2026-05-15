// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IERC1967 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import { ExtensionBeacon } from "../../src/platform/ExtensionBeacon.sol";
import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";

import { MockERC20 } from "../mock/MockERC20.sol";
import { MockPYUSDXExtension } from "../mock/MockPYUSDXExtension.sol";
import { MockSwapFacility } from "../mock/MockSwapFacility.sol";

import { BaseTest } from "../utils/BaseTest.sol";

contract ExtensionBeaconTest is BaseTest {
    MockERC20 public pyusdx;
    MockSwapFacility public swapFacility;
    ExtensionBeacon public beacon;

    MockPYUSDXExtension public impl;

    // ERC-1967 implementation slot
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function setUp() public override {
        super.setUp();

        pyusdx = new MockERC20("PYUSDX", "PYUSDX", 6);
        swapFacility = new MockSwapFacility(address(pyusdx));

        // Deploy mock implementation
        impl = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        // Deploy ExtensionBeacon behind TransparentProxy
        beacon = ExtensionBeacon(
            UnsafeUpgrades.deployTransparentProxy(
                address(new ExtensionBeacon(address(pyusdx), address(swapFacility))),
                admin,
                abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin, beaconManager, address(impl))
            )
        );
    }

    /* ============ Helper Functions ============ */

    function _deployBeaconImpl(address pyusdx_, address swapFacility_) internal returns (address) {
        return address(new ExtensionBeacon(pyusdx_, swapFacility_));
    }

    function _deployBeaconWithProxy(
        address pyusdx_,
        address swapFacility_,
        address admin_,
        address beaconManager_,
        address initialImpl_
    ) internal returns (ExtensionBeacon) {
        return
            ExtensionBeacon(
                UnsafeUpgrades.deployTransparentProxy(
                    _deployBeaconImpl(pyusdx_, swapFacility_),
                    admin_,
                    abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin_, beaconManager_, initialImpl_)
                )
            );
    }

    /* ============ constructor ============ */

    function test_constructor_zeroPyusdx() public {
        vm.expectRevert(IExtensionBeacon.ZeroPYUSDX.selector);
        new ExtensionBeacon(address(0), address(swapFacility));
    }

    function test_constructor_zeroSwapFacility() public {
        vm.expectRevert(IExtensionBeacon.ZeroSwapFacility.selector);
        new ExtensionBeacon(address(pyusdx), address(0));
    }

    function test_constructor_pyusdxMismatch() public {
        MockERC20 wrongPyusdx = new MockERC20("Wrong", "WRONG", 6);
        MockSwapFacility wrongSwap = new MockSwapFacility(address(wrongPyusdx));

        vm.expectRevert(IExtensionBeacon.PYUSDXMismatch.selector);
        new ExtensionBeacon(address(pyusdx), address(wrongSwap));
    }

    function test_constructor_immutables() public view {
        assertEq(beacon.pyusdx(), address(pyusdx));
        assertEq(beacon.swapFacility(), address(swapFacility));
    }

    /* ============ initialize ============ */

    function test_initialize_zeroAdmin() public {
        address impl_ = _deployBeaconImpl(address(pyusdx), address(swapFacility));

        vm.expectRevert(IExtensionBeacon.ZeroAdmin.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl_,
            admin,
            abi.encodeWithSelector(ExtensionBeacon.initialize.selector, address(0), beaconManager, address(impl))
        );
    }

    function test_initialize_zeroBeaconManager() public {
        address impl_ = _deployBeaconImpl(address(pyusdx), address(swapFacility));

        vm.expectRevert(IExtensionBeacon.ZeroBeaconManager.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl_,
            admin,
            abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin, address(0), address(impl))
        );
    }

    function test_initialize_zeroImplementation() public {
        address impl_ = _deployBeaconImpl(address(pyusdx), address(swapFacility));

        vm.expectRevert(IExtensionBeacon.ZeroImplementation.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl_,
            admin,
            abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin, beaconManager, address(0))
        );
    }

    function test_initialize_invalidImplementation() public {
        MockERC20 wrongPyusdx = new MockERC20("Wrong", "WRONG", 6);
        MockSwapFacility wrongSwap = new MockSwapFacility(address(wrongPyusdx));
        MockPYUSDXExtension badImpl = new MockPYUSDXExtension(address(wrongPyusdx), address(wrongSwap));

        address impl_ = _deployBeaconImpl(address(pyusdx), address(swapFacility));

        vm.expectRevert(IExtensionBeacon.InvalidExtension.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl_,
            admin,
            abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin, beaconManager, address(badImpl))
        );
    }

    function test_initialize_grantsRoles() public view {
        assertTrue(beacon.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(beacon.hasRole(BEACON_MANAGER_ROLE, beaconManager));
        assertFalse(beacon.hasRole(DEFAULT_ADMIN_ROLE, other));
        assertFalse(beacon.hasRole(BEACON_MANAGER_ROLE, other));
    }

    function test_initialize_registersImplementation() public view {
        assertEq(beacon.implementation(), address(impl));
        assertEq(beacon.latestVersion(), 1);
    }

    function test_initialize_alreadyInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        beacon.initialize(admin, beaconManager, address(impl));
    }

    /* ============ registerImplementation ============ */

    function test_registerImplementation_success() public {
        MockPYUSDXExtension newImpl = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.prank(beaconManager);
        uint256 version = beacon.registerImplementation(address(newImpl));

        assertEq(version, 2);
        assertEq(beacon.latestVersion(), 2);
        assertEq(beacon.implementation(), address(newImpl));
    }

    function test_registerImplementation_autoIncrement() public {
        MockPYUSDXExtension impl2 = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        MockPYUSDXExtension impl3 = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.startPrank(beaconManager);
        uint256 v2 = beacon.registerImplementation(address(impl2));
        uint256 v3 = beacon.registerImplementation(address(impl3));
        vm.stopPrank();

        assertEq(v2, 2);
        assertEq(v3, 3);
        assertEq(beacon.latestVersion(), 3);
        assertEq(beacon.implementation(1), address(impl));
        assertEq(beacon.implementation(2), address(impl2));
        assertEq(beacon.implementation(3), address(impl3));
    }

    function test_registerImplementation_accessControl() public {
        MockPYUSDXExtension newImpl = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, BEACON_MANAGER_ROLE)
        );
        beacon.registerImplementation(address(newImpl));
    }

    function test_registerImplementation_zeroAddress() public {
        vm.prank(beaconManager);
        vm.expectRevert(IExtensionBeacon.ZeroImplementation.selector);
        beacon.registerImplementation(address(0));
    }

    function test_registerImplementation_wrongWiring() public {
        MockERC20 wrongPyusdx = new MockERC20("Wrong", "WRONG", 6);
        MockSwapFacility wrongSwap = new MockSwapFacility(address(wrongPyusdx));
        MockPYUSDXExtension badImpl = new MockPYUSDXExtension(address(wrongPyusdx), address(wrongSwap));

        vm.prank(beaconManager);
        vm.expectRevert(IExtensionBeacon.InvalidExtension.selector);
        beacon.registerImplementation(address(badImpl));
    }

    function test_registerImplementation_nonContract() public {
        address eoa = makeAddr("eoa");

        vm.prank(beaconManager);
        vm.expectRevert();
        beacon.registerImplementation(eoa);
    }

    /* ============ implementation ============ */

    function test_implementation_zeroArg_returnsLatest() public {
        MockPYUSDXExtension impl2 = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        MockPYUSDXExtension impl3 = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.startPrank(beaconManager);
        beacon.registerImplementation(address(impl2));
        beacon.registerImplementation(address(impl3));
        vm.stopPrank();

        assertEq(beacon.implementation(), address(impl3));
    }

    function test_implementation_specificVersion() public {
        MockPYUSDXExtension impl2 = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.prank(beaconManager);
        beacon.registerImplementation(address(impl2));

        assertEq(beacon.implementation(1), address(impl));
        assertEq(beacon.implementation(2), address(impl2));
    }

    function test_implementation_noImplRegistered() public {
        // Deploy a fresh beacon with no implementations
        ExtensionBeacon freshBeacon = ExtensionBeacon(
            UnsafeUpgrades.deployTransparentProxy(
                _deployBeaconImpl(address(pyusdx), address(swapFacility)),
                admin,
                abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin, beaconManager, address(impl))
            )
        );

        // Version 99 doesn't exist
        vm.expectRevert(IExtensionBeacon.NoImplementationRegistered.selector);
        freshBeacon.implementation(99);
    }

    /* ============ latestVersion ============ */

    function test_latestVersion() public {
        MockPYUSDXExtension newImpl = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.prank(beaconManager);
        beacon.registerImplementation(address(newImpl));

        assertEq(beacon.latestVersion(), 2);
    }

    /* ============ events ============ */

    function test_registerImplementation_event() public {
        MockPYUSDXExtension newImpl = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(address(newImpl));

        vm.expectEmit(true, true, true, true);
        emit IExtensionBeacon.ImplementationRegistered(2, address(newImpl));

        vm.prank(beaconManager);
        beacon.registerImplementation(address(newImpl));
    }

    /* ============ storage ============ */

    function test_storageLocation() public pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXExtensionBeacon")) - 1)) &
            ~bytes32(uint256(0xff));
        bytes32 actual = 0xea0c2eec9f3cb72c51d142ff5c076f11b507be969141547f15f83f9b92f55900;
        assertEq(expected, actual);
    }
}
