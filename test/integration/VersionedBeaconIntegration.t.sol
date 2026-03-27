// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";
import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { IVersionedBeacon } from "../../src/platform/interfaces/IVersionedBeacon.sol";
import { VersionedBeacon } from "../../src/platform/VersionedBeacon.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";
import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @dev V2 extension that adds a `ping()` function. Demonstrates new functionality after upgrade.
contract YieldToOneV2 is YieldToOne {
    constructor(address pyusdx_, address swapFacility_) YieldToOne(pyusdx_, swapFacility_) {}

    function ping() external pure returns (string memory) {
        return "pong";
    }
}

contract VersionedBeaconIntegrationTests is IntegrationForkTest {
    VersionedBeacon public beacon;

    address public versionManager;
    address public builder;

    address public yieldToOneImplV1;
    address public yieldToOneImplV2;

    function setUp() public override {
        super.setUp();

        versionManager = makeAddr("versionManager");
        builder = makeAddr("builder");

        // Deploy VersionedBeacon
        beacon = new VersionedBeacon(address(factory), address(pyusdx), address(swapFacility), admin, versionManager);

        // Upgrade factory to new implementation with beacon address
        address newFactoryImpl = address(new ExtensionFactory(address(pyusdx), address(swapFacility), address(beacon)));

        UnsafeUpgrades.upgradeProxy(address(factory), newFactoryImpl, "", admin);

        // Deploy v1 (base YieldToOne) and v2 (YieldToOneV2 with ping())
        yieldToOneImplV1 = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        yieldToOneImplV2 = address(new YieldToOneV2(address(pyusdx), address(swapFacility)));
    }

    function test_fullBeaconLifecycle() public {
        /* ============ M0 registers version 1 ============ */

        vm.prank(versionManager);
        uint256 v1 = beacon.registerVersion(IExtensionFactory.ExtensionType.YIELD_TO_ONE, yieldToOneImplV1);

        vm.prank(versionManager);
        beacon.setLatestVersion(IExtensionFactory.ExtensionType.YIELD_TO_ONE, v1);

        assertEq(v1, 1);
        assertEq(beacon.latestVersion(IExtensionFactory.ExtensionType.YIELD_TO_ONE), v1);
        assertEq(beacon.versionCount(), 1);

        IVersionedBeacon.Version memory version1 = beacon.getVersion(v1);
        assertEq(version1.implementation, yieldToOneImplV1);

        /* ============ Builder deploys a beacon extension ============ */

        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "Builder YieldToOne",
            symbol: "bYTO",
            yieldRecipient: yieldRecipient,
            admin: builder,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address proxy = factory.deployBeaconYieldToOne("builder-yto", v1, params);

        // Verify factory registration
        assertTrue(factory.isApprovedExtension(proxy));
        assertTrue(swapFacility.isApprovedExtension(proxy));

        assertEq(uint8(factory.getExtensionType(proxy)), uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE));

        // Verify beacon registration
        assertEq(beacon.proxyVersion(proxy), v1);
        assertEq(beacon.proxyOwner(proxy), builder);
        assertEq(beacon.implementationFor(proxy), yieldToOneImplV1);

        // Verify extension metadata
        YieldToOne extension = YieldToOne(proxy);
        assertEq(extension.name(), "Builder YieldToOne");
        assertEq(extension.symbol(), "bYTO");
        assertEq(extension.pyusdx(), address(pyusdx));
        assertEq(extension.swapFacility(), address(swapFacility));

        // Verify the extension actually works: wrap PYUSDX for alice
        uint256 wrapAmount = 1000e6;

        vm.prank(earnerManager);
        pyusdx.setAccountInfo(proxy, 500, 0, address(0));

        _mintPYUSDX(alice, wrapAmount);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), wrapAmount);

        vm.prank(alice);
        swapFacility.swapIn(proxy, wrapAmount, alice);

        assertEq(extension.balanceOf(alice), wrapAmount);

        // ping() does not exist on v1, call reverts
        (bool success, ) = proxy.staticcall(abi.encodeWithSignature("ping()"));
        assertFalse(success);

        /* ============ M0 publishes v2, builder upgrades ============ */

        vm.prank(versionManager);
        uint256 v2 = beacon.registerVersion(IExtensionFactory.ExtensionType.YIELD_TO_ONE, yieldToOneImplV2);

        vm.prank(versionManager);
        beacon.setLatestVersion(IExtensionFactory.ExtensionType.YIELD_TO_ONE, v2);

        assertEq(v2, 2);
        assertEq(beacon.latestVersion(IExtensionFactory.ExtensionType.YIELD_TO_ONE), v2);

        // Builder is still on v1 (pinned), not affected by setLatestVersion
        assertEq(beacon.implementationFor(proxy), yieldToOneImplV1);

        // Builder decides to upgrade
        vm.prank(builder);
        beacon.pinVersion(proxy, v2);

        // Now resolves to v2
        assertEq(beacon.proxyVersion(proxy), v2);
        assertEq(beacon.implementationFor(proxy), yieldToOneImplV2);

        // Alice's balance is preserved, proxy storage is untouched by the impl swap
        assertEq(extension.balanceOf(alice), wrapAmount);

        // ping() now works on v2
        assertEq(YieldToOneV2(proxy).ping(), "pong");

        // Extension still works — alice can unwrap
        vm.prank(alice);
        IERC20(proxy).approve(address(swapFacility), wrapAmount);

        vm.prank(alice);
        swapFacility.swapOut(proxy, wrapAmount, alice);

        assertEq(extension.balanceOf(alice), 0);
        assertEq(IERC20(address(pyusdx)).balanceOf(alice), wrapAmount);
    }
}
