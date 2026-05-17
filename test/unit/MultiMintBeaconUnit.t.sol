// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { VmSafe } from "../../lib/evm-m-extensions/lib/forge-std/src/Vm.sol";

import { ExtensionBeacon } from "../../src/platform/ExtensionBeacon.sol";
import { MultiMintBeacon } from "../../src/platform/MultiMintBeacon.sol";
import { IMultiMintBeacon } from "../../src/platform/interfaces/IMultiMintBeacon.sol";

import { MockERC20 } from "../mock/MockERC20.sol";
import { MockPYUSDXExtension } from "../mock/MockPYUSDXExtension.sol";
import { MockSwapFacility } from "../mock/MockSwapFacility.sol";

import { BaseTest } from "../utils/BaseTest.sol";

contract MultiMintBeaconTest is BaseTest {
    MockERC20 public pyusdx;
    MockSwapFacility public swapFacility;
    MultiMintBeacon public beacon;

    MockPYUSDXExtension public impl;

    address public usdc = makeAddr("usdc");
    address public dai = makeAddr("dai");

    function setUp() public override {
        super.setUp();

        pyusdx = new MockERC20("PYUSDX", "PYUSDX", 6);
        swapFacility = new MockSwapFacility(address(pyusdx));

        impl = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        beacon = MultiMintBeacon(
            UnsafeUpgrades.deployTransparentProxy(
                address(new MultiMintBeacon(address(pyusdx), address(swapFacility))),
                admin,
                abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin, beaconManager, address(impl))
            )
        );
    }

    /* ============ setAssetWhitelist ============ */

    function test_setAssetWhitelist_notBeaconManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, BEACON_MANAGER_ROLE)
        );

        vm.prank(other);
        beacon.setAssetWhitelist(usdc, true);
    }

    function test_setAssetWhitelist_zeroAsset() public {
        vm.expectRevert(IMultiMintBeacon.ZeroAsset.selector);

        vm.prank(beaconManager);
        beacon.setAssetWhitelist(address(0), true);
    }

    function test_setAssetWhitelist() public {
        assertFalse(beacon.isAssetWhitelisted(usdc));

        vm.expectEmit();
        emit IMultiMintBeacon.AssetWhitelistSet(usdc, true);

        vm.prank(beaconManager);
        beacon.setAssetWhitelist(usdc, true);

        assertTrue(beacon.isAssetWhitelisted(usdc));

        vm.expectEmit();
        emit IMultiMintBeacon.AssetWhitelistSet(usdc, false);

        vm.prank(beaconManager);
        beacon.setAssetWhitelist(usdc, false);

        assertFalse(beacon.isAssetWhitelisted(usdc));
    }

    function test_setAssetWhitelist_idempotent() public {
        vm.prank(beaconManager);
        beacon.setAssetWhitelist(usdc, true);

        vm.recordLogs();

        vm.prank(beaconManager);
        beacon.setAssetWhitelist(usdc, true);

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            assertNotEq(logs[i].topics[0], IMultiMintBeacon.AssetWhitelistSet.selector);
        }

        assertTrue(beacon.isAssetWhitelisted(usdc));
    }

    /* ============ setAssetWhitelist (batch) ============ */

    function test_setAssetWhitelist_batch_notBeaconManager() public {
        address[] memory assets = new address[](1);
        bool[] memory allowed = new bool[](1);
        assets[0] = usdc;
        allowed[0] = true;

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, BEACON_MANAGER_ROLE)
        );

        vm.prank(other);
        beacon.setAssetWhitelist(assets, allowed);
    }

    function test_setAssetWhitelist_batch_arrayLengthMismatch() public {
        address[] memory assets = new address[](2);
        bool[] memory allowed = new bool[](1);
        assets[0] = usdc;
        assets[1] = dai;
        allowed[0] = true;

        vm.expectRevert(IMultiMintBeacon.ArrayLengthMismatch.selector);

        vm.prank(beaconManager);
        beacon.setAssetWhitelist(assets, allowed);
    }

    function test_setAssetWhitelist_batch_zeroAsset() public {
        address[] memory assets = new address[](2);
        bool[] memory allowed = new bool[](2);
        assets[0] = usdc;
        assets[1] = address(0);
        allowed[0] = true;
        allowed[1] = true;

        vm.expectRevert(IMultiMintBeacon.ZeroAsset.selector);

        vm.prank(beaconManager);
        beacon.setAssetWhitelist(assets, allowed);
    }

    function test_setAssetWhitelist_batch() public {
        address[] memory assets = new address[](2);
        bool[] memory allowed = new bool[](2);
        assets[0] = usdc;
        assets[1] = dai;
        allowed[0] = true;
        allowed[1] = true;

        vm.prank(beaconManager);
        beacon.setAssetWhitelist(assets, allowed);

        assertTrue(beacon.isAssetWhitelisted(usdc));
        assertTrue(beacon.isAssetWhitelisted(dai));

        allowed[1] = false;

        vm.prank(beaconManager);
        beacon.setAssetWhitelist(assets, allowed);

        assertTrue(beacon.isAssetWhitelisted(usdc));
        assertFalse(beacon.isAssetWhitelisted(dai));
    }
}
