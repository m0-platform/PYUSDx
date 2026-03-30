// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { IVersionedBeacon } from "../../src/platform/interfaces/IVersionedBeacon.sol";
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
    bytes32 public constant YIELD_TO_ONE_TYPE_KEY = keccak256("YIELD_TO_ONE");
    bytes32 public constant YIELD_SPLIT_TYPE_KEY = keccak256("YIELD_SPLIT");

    address public builder;

    address public yieldToOneImplV1;
    address public yieldToOneImplV2;

    function setUp() public override {
        super.setUp();

        builder = makeAddr("builder");

        // Deploy v1 (base YieldToOne) and v2 (YieldToOneV2 with ping())
        yieldToOneImplV1 = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        yieldToOneImplV2 = address(new YieldToOneV2(address(pyusdx), address(swapFacility)));
    }

    function test_fullBeaconLifecycle() public {
        /* ============ M0 registers version 1 ============ */

        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.prank(admin);
        beacon.setLatestVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertEq(v1, 1);
        assertEq(beacon.latestVersion(YIELD_TO_ONE_TYPE_KEY), v1);
        assertEq(beacon.versionCount(YIELD_TO_ONE_TYPE_KEY), 1);
        assertEq(beacon.getVersion(YIELD_TO_ONE_TYPE_KEY, v1), yieldToOneImplV1);

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

        vm.prank(admin);
        uint256 v2 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV2);

        vm.prank(admin);
        beacon.setLatestVersion(YIELD_TO_ONE_TYPE_KEY, v2);

        assertEq(v2, 2);
        assertEq(beacon.latestVersion(YIELD_TO_ONE_TYPE_KEY), v2);

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

    /* ============ Extension Type/Version Lifecycle ============ */

    function test_newExtensionTypeRegistration() public {
        // A brand new type key that the beacon has never seen
        assertEq(beacon.versionCount(YIELD_SPLIT_TYPE_KEY), 0);

        // Deploy a YieldToOne extension BEFORE registering the new type
        vm.prank(admin);
        uint256 ytoV1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "Existing Extension",
            symbol: "EXT",
            yieldRecipient: yieldRecipient,
            admin: builder,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address existingProxy = factory.deployBeaconYieldToOne("existing-ext", ytoV1, params);

        // Wrap PYUSDX so we can verify balances are preserved
        uint256 wrapAmount = 500e6;

        vm.prank(earnerManager);
        pyusdx.setAccountInfo(existingProxy, 500, 0, address(0));

        _mintPYUSDX(alice, wrapAmount);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), wrapAmount);

        vm.prank(alice);
        swapFacility.swapIn(existingProxy, wrapAmount, alice);

        assertEq(YieldToOne(existingProxy).balanceOf(alice), wrapAmount);

        // Now register versions for the new YIELD_SPLIT type
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_SPLIT_TYPE_KEY, yieldToOneImplV1);

        vm.prank(admin);
        uint256 v2 = beacon.registerVersion(YIELD_SPLIT_TYPE_KEY, yieldToOneImplV2);

        // New type has correct state
        assertEq(v1, 1);
        assertEq(v2, 2);
        assertEq(beacon.versionCount(YIELD_SPLIT_TYPE_KEY), 2);
        assertEq(beacon.latestVersion(YIELD_SPLIT_TYPE_KEY), 1);
        assertEq(beacon.getVersion(YIELD_SPLIT_TYPE_KEY, v1), yieldToOneImplV1);

        // Version IDs are independent per type
        assertEq(beacon.versionCount(YIELD_TO_ONE_TYPE_KEY), 1);
        assertEq(beacon.versionCount(YIELD_SPLIT_TYPE_KEY), 2);

        // Sanity check that a completely unknown type returns 0
        assertEq(beacon.versionCount(keccak256("DOES_NOT_EXIST")), 0);

        // Cross-type isolation: existing YieldToOne proxy is completely unaffected
        assertEq(beacon.implementationFor(existingProxy), yieldToOneImplV1);
        assertEq(beacon.proxyVersion(existingProxy), ytoV1);
        assertEq(YieldToOne(existingProxy).balanceOf(alice), wrapAmount);

        // Existing extension still works: alice can unwrap
        vm.prank(alice);
        IERC20(existingProxy).approve(address(swapFacility), wrapAmount);

        vm.prank(alice);
        swapFacility.swapOut(existingProxy, wrapAmount, alice);

        assertEq(YieldToOne(existingProxy).balanceOf(alice), 0);
    }

    function test_registerVersion_revert_zeroTypeKey() public {
        vm.prank(admin);
        vm.expectRevert(IVersionedBeacon.InvalidTypeKey.selector);
        beacon.registerVersion(bytes32(0), yieldToOneImplV1);
    }

    function test_pinVersion_revert_nonOwner() public {
        // Setup: register version and deploy extension owned by builder
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

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
        address proxy = factory.deployBeaconYieldToOne("builder-pin-test", v1, params);

        // Random user cannot pin
        address randomUser = makeAddr("randomUser");

        vm.prank(randomUser);
        vm.expectRevert(IVersionedBeacon.NotProxyOwner.selector);
        beacon.pinVersion(proxy, v1);

        // Even M0 admin cannot force-upgrade a builder's extension
        vm.prank(admin);
        vm.expectRevert(IVersionedBeacon.NotProxyOwner.selector);
        beacon.pinVersion(proxy, v1);
    }

    function test_pinVersion_revert_invalidVersion() public {
        // Setup: register one version and deploy extension
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

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
        address proxy = factory.deployBeaconYieldToOne("builder-invalid-ver", v1, params);

        // Builder tries to pin to a version that doesn't exist
        vm.prank(builder);
        vm.expectRevert(IVersionedBeacon.InvalidVersion.selector);
        beacon.pinVersion(proxy, 99);
    }
}
