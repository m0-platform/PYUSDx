// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { IVersionedBeacon } from "../../src/platform/interfaces/IVersionedBeacon.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";
import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @dev V2 extension that adds a `ping()` function. Demonstrates new functionality after upgrade.
contract YieldToOneV2 is YieldToOne {
    constructor(address pyusdx_, address swapFacility_) YieldToOne(pyusdx_, swapFacility_) {}

    function ping() external pure returns (string memory) {
        return "pong";
    }
}

/// @dev V2 MultiMint with a ping function for version testing.
contract MultiMintV2 is MultiMint {
    constructor(address pyusdx_, address swapFacility_) MultiMint(pyusdx_, swapFacility_) {}

    function ping() external pure returns (string memory) {
        return "pong";
    }
}

contract VersionedBeaconIntegrationTests is IntegrationForkTest {
    bytes32 public constant YIELD_TO_ONE_TYPE_KEY = keccak256("YIELD_TO_ONE");
    bytes32 public constant MULTI_MINT_TYPE_KEY = keccak256("MULTI_MINT");
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
        address proxy = factory.deployBeaconYieldToOne("builder-yto", params);

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
        address existingProxy = factory.deployBeaconYieldToOne("existing-ext", params);

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

        // Register the new YIELD_SPLIT type key, then register versions
        vm.prank(admin);
        beacon.registerTypeKey(YIELD_SPLIT_TYPE_KEY);

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

    function test_registerVersion_revert_unregisteredTypeKey() public {
        bytes32 unregisteredKey = keccak256("UNREGISTERED");

        vm.expectRevert(IVersionedBeacon.TypeKeyNotRegistered.selector);
        vm.prank(admin);
        beacon.registerVersion(unregisteredKey, yieldToOneImplV1);
    }

    function test_registerTypeKey_revert_zeroKey() public {
        vm.expectRevert(IVersionedBeacon.InvalidTypeKey.selector);
        vm.prank(admin);
        beacon.registerTypeKey(bytes32(0));
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
        address proxy = factory.deployBeaconYieldToOne("builder-pin-test", params);

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
        beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

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
        address proxy = factory.deployBeaconYieldToOne("builder-invalid-ver", params);

        // Builder tries to pin to a version that doesn't exist
        vm.prank(builder);
        vm.expectRevert(IVersionedBeacon.InvalidVersion.selector);
        beacon.pinVersion(proxy, 99);
    }

    /* ============ Pause Lifecycle ============ */

    function test_pauseLifecycle() public {
        /* ============ Register v1, deploy ext on v1, then register v2 ============ */

        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        // Deploy first extension while v1 is latest
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "Extension V1",
            symbol: "EV1",
            yieldRecipient: yieldRecipient,
            admin: builder,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address proxyV1 = factory.deployBeaconYieldToOne("pause-test-v1", params);

        // Now register v2 and promote it to latest
        vm.prank(admin);
        uint256 v2 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV2);

        vm.prank(admin);
        beacon.setLatestVersion(YIELD_TO_ONE_TYPE_KEY, v2);

        // Deploy second extension on v2 (now latest)
        params.name = "Extension V2";
        params.symbol = "EV2";

        vm.prank(builder);
        address proxyV2 = factory.deployBeaconYieldToOne("pause-test-v2", params);

        YieldToOne extV1 = YieldToOne(proxyV1);
        YieldToOne extV2 = YieldToOne(proxyV2);

        /* ============ Wrap PYUSDX into both extensions ============ */

        uint256 wrapAmount = 1000e6;

        vm.prank(earnerManager);
        pyusdx.setAccountInfo(proxyV1, 500, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setAccountInfo(proxyV2, 500, 0, address(0));

        _mintPYUSDX(alice, wrapAmount * 2);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), wrapAmount * 2);

        vm.prank(alice);
        swapFacility.swapIn(proxyV1, wrapAmount, alice);

        vm.prank(alice);
        swapFacility.swapIn(proxyV2, wrapAmount, alice);

        assertEq(extV1.balanceOf(alice), wrapAmount);
        assertEq(extV2.balanceOf(alice), wrapAmount);

        /* ============ Version pause: M0 pauses v2 only ============ */

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v2);

        assertTrue(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v2));
        assertFalse(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v1));

        // v2 proxy: implementation still returns normal impl (no swap)
        assertEq(beacon.implementationFor(proxyV2), yieldToOneImplV2);

        // v2 proxy: paused() returns true via beacon check
        assertTrue(extV2.paused());
        assertTrue(beacon.isProxyPaused(proxyV2));

        // v2 proxy: view functions still work
        assertEq(extV2.balanceOf(alice), wrapAmount);
        assertEq(extV2.totalSupply(), wrapAmount);
        assertEq(extV2.name(), "Extension V2");
        assertEq(extV2.symbol(), "EV2");

        // v2 proxy: transfer reverts with EnforcedPause
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        IERC20(proxyV2).transfer(bob, 100e6);

        // v2 proxy: approve still works (not guarded by _requireNotPaused)
        vm.prank(alice);
        IERC20(proxyV2).approve(address(swapFacility), wrapAmount);

        // v1 proxy: completely unaffected, transfers work
        assertEq(beacon.implementationFor(proxyV1), yieldToOneImplV1);
        assertFalse(extV1.paused());

        vm.prank(alice);
        IERC20(proxyV1).transfer(bob, 100e6);

        assertEq(extV1.balanceOf(alice), wrapAmount - 100e6);
        assertEq(extV1.balanceOf(bob), 100e6);

        /* ============ Version unpause: M0 unpauses v2 ============ */

        vm.prank(admin);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, v2);

        assertFalse(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v2));
        assertFalse(extV2.paused());
        assertEq(beacon.implementationFor(proxyV2), yieldToOneImplV2);

        // v2 proxy can transfer again
        vm.prank(alice);
        IERC20(proxyV2).transfer(bob, 100e6);

        assertEq(extV2.balanceOf(alice), wrapAmount - 100e6);
        assertEq(extV2.balanceOf(bob), 100e6);

        /* ============ Type pause: M0 pauses all YieldToOne extensions ============ */

        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        assertTrue(beacon.isTypePaused(YIELD_TO_ONE_TYPE_KEY));

        // Both proxies are paused
        assertTrue(extV1.paused());
        assertTrue(extV2.paused());
        assertTrue(beacon.isProxyPaused(proxyV1));
        assertTrue(beacon.isProxyPaused(proxyV2));

        // Implementation still returns normal impls (no swap)
        assertEq(beacon.implementationFor(proxyV1), yieldToOneImplV1);
        assertEq(beacon.implementationFor(proxyV2), yieldToOneImplV2);

        // Both: views work
        assertEq(extV1.balanceOf(bob), 100e6);
        assertEq(extV2.balanceOf(bob), 100e6);

        // Both: transfers revert with EnforcedPause
        vm.prank(bob);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        IERC20(proxyV1).transfer(alice, 50e6);

        vm.prank(bob);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        IERC20(proxyV2).transfer(alice, 50e6);

        /* ============ Type unpause: resume normal operations ============ */

        vm.prank(admin);
        beacon.unpauseType(YIELD_TO_ONE_TYPE_KEY);

        assertFalse(beacon.isTypePaused(YIELD_TO_ONE_TYPE_KEY));
        assertFalse(extV1.paused());
        assertFalse(extV2.paused());

        // Both proxies resolve to their real impls
        assertEq(beacon.implementationFor(proxyV1), yieldToOneImplV1);
        assertEq(beacon.implementationFor(proxyV2), yieldToOneImplV2);

        // Alice can unwrap from both extensions
        uint256 aliceV1Balance = extV1.balanceOf(alice);
        uint256 aliceV2Balance = extV2.balanceOf(alice);

        vm.prank(alice);
        IERC20(proxyV1).approve(address(swapFacility), aliceV1Balance);

        vm.prank(alice);
        swapFacility.swapOut(proxyV1, aliceV1Balance, alice);

        vm.prank(alice);
        IERC20(proxyV2).approve(address(swapFacility), aliceV2Balance);

        vm.prank(alice);
        swapFacility.swapOut(proxyV2, aliceV2Balance, alice);

        assertEq(extV1.balanceOf(alice), 0);
        assertEq(extV2.balanceOf(alice), 0);
    }

    /* ============ Pause Access Control ============ */

    function test_pauseVersion_revert_notPauseManager() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                builder,
                beacon.PAUSE_MANAGER_ROLE()
            )
        );

        vm.prank(builder);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);
    }

    function test_unpauseVersion_revert_notPauseManager() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                builder,
                beacon.PAUSE_MANAGER_ROLE()
            )
        );

        vm.prank(builder);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);
    }

    function test_pauseType_revert_notPauseManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                builder,
                beacon.PAUSE_MANAGER_ROLE()
            )
        );

        vm.prank(builder);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);
    }

    function test_unpauseType_revert_notPauseManager() public {
        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                builder,
                beacon.PAUSE_MANAGER_ROLE()
            )
        );

        vm.prank(builder);
        beacon.unpauseType(YIELD_TO_ONE_TYPE_KEY);
    }

    /* ============ Pause Validation ============ */

    function test_pauseVersion_revert_invalidVersion() public {
        vm.prank(admin);
        beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        // Version 0 is invalid
        vm.expectRevert(IVersionedBeacon.InvalidVersion.selector);

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, 0);

        // Version 99 does not exist
        vm.expectRevert(IVersionedBeacon.InvalidVersion.selector);

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, 99);
    }

    function test_unpauseVersion_revert_invalidVersion() public {
        vm.expectRevert(IVersionedBeacon.InvalidVersion.selector);

        vm.prank(admin);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, 0);

        vm.expectRevert(IVersionedBeacon.InvalidVersion.selector);

        vm.prank(admin);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, 99);
    }

    function test_pauseType_revert_zeroTypeKey() public {
        vm.expectRevert(IVersionedBeacon.InvalidTypeKey.selector);

        vm.prank(admin);
        beacon.pauseType(bytes32(0));
    }

    function test_unpauseType_revert_zeroTypeKey() public {
        vm.expectRevert(IVersionedBeacon.InvalidTypeKey.selector);

        vm.prank(admin);
        beacon.unpauseType(bytes32(0));
    }

    /* ============ Pause Idempotency ============ */

    function test_pauseVersion_idempotent() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertTrue(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v1));

        // Pausing again does not revert and does not emit (early return)
        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertTrue(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v1));
    }

    function test_unpauseVersion_idempotent() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        // Unpausing a non-paused version does not revert and does not emit (early return)
        vm.prank(admin);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertFalse(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v1));
    }

    function test_pauseType_idempotent() public {
        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        assertTrue(beacon.isTypePaused(YIELD_TO_ONE_TYPE_KEY));

        // Pausing again does not revert and does not emit (early return)
        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        assertTrue(beacon.isTypePaused(YIELD_TO_ONE_TYPE_KEY));
    }

    function test_unpauseType_idempotent() public {
        // Unpausing a non-paused type does not revert and does not emit (early return)
        vm.prank(admin);
        beacon.unpauseType(YIELD_TO_ONE_TYPE_KEY);

        assertFalse(beacon.isTypePaused(YIELD_TO_ONE_TYPE_KEY));
    }

    /* ============ Pause Events ============ */

    function test_pauseVersion() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.expectEmit();
        emit IVersionedBeacon.VersionPaused(YIELD_TO_ONE_TYPE_KEY, v1);

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertTrue(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v1));
    }

    function test_unpauseVersion() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        vm.expectEmit();
        emit IVersionedBeacon.VersionUnpaused(YIELD_TO_ONE_TYPE_KEY, v1);

        vm.prank(admin);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertFalse(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v1));
    }

    function test_pauseType() public {
        vm.expectEmit();
        emit IVersionedBeacon.TypePaused(YIELD_TO_ONE_TYPE_KEY);

        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        assertTrue(beacon.isTypePaused(YIELD_TO_ONE_TYPE_KEY));
    }

    function test_unpauseType() public {
        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        vm.expectEmit();
        emit IVersionedBeacon.TypeUnpaused(YIELD_TO_ONE_TYPE_KEY);

        vm.prank(admin);
        beacon.unpauseType(YIELD_TO_ONE_TYPE_KEY);

        assertFalse(beacon.isTypePaused(YIELD_TO_ONE_TYPE_KEY));
    }

    function test_pauseVersion_noEmitWhenAlreadyPaused() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        vm.recordLogs();

        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_unpauseVersion_noEmitWhenNotPaused() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.recordLogs();

        vm.prank(admin);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_pauseType_noEmitWhenAlreadyPaused() public {
        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        vm.recordLogs();

        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_unpauseType_noEmitWhenNotPaused() public {
        vm.recordLogs();

        vm.prank(admin);
        beacon.unpauseType(YIELD_TO_ONE_TYPE_KEY);

        assertEq(vm.getRecordedLogs().length, 0);
    }

    /* ============ isProxyPaused Edge Cases ============ */

    function test_isProxyPaused_unregisteredProxy() public {
        assertFalse(beacon.isProxyPaused(makeAddr("unknown")));
        assertFalse(beacon.isProxyPaused(address(0)));
    }

    /* ============ Version Pause with Unpinned Proxies ============ */

    function test_versionPause_affectsUnpinnedProxies() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        // Deploy proxy pinned to v1
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "Unpinned Test",
            symbol: "UT",
            yieldRecipient: yieldRecipient,
            admin: builder,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address proxy = factory.deployBeaconYieldToOne("unpinned-test", params);

        // Initially pinned to v1
        assertEq(beacon.proxyVersion(proxy), v1);

        // Register v2 and unpin the proxy to follow latest
        vm.prank(admin);
        uint256 v2 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV2);

        vm.prank(admin);
        beacon.setLatestVersion(YIELD_TO_ONE_TYPE_KEY, v2);

        vm.prank(builder);
        beacon.pinVersion(proxy, 0);

        // Unpinned: resolves to latest (v2)
        assertEq(beacon.implementationFor(proxy), yieldToOneImplV2);
        assertFalse(beacon.isProxyPaused(proxy));

        // Pause v2 — unpinned proxy should be paused because it resolves to v2
        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v2);

        assertTrue(beacon.isProxyPaused(proxy));
        assertTrue(YieldToOne(proxy).paused());

        // v1 is NOT paused — pinning to v1 would resolve as unpaused
        assertFalse(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v1));

        // Pin to v1 — proxy should no longer be paused
        vm.prank(builder);
        beacon.pinVersion(proxy, v1);

        assertFalse(beacon.isProxyPaused(proxy));
        assertFalse(YieldToOne(proxy).paused());
    }

    /* ============ Deploy to Paused Version ============ */

    function test_deployBeaconExtension_toPausedVersion_isImmediatelyPaused() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.prank(admin);
        beacon.setLatestVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        // Pause v1 before deploying
        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertTrue(beacon.isVersionPaused(YIELD_TO_ONE_TYPE_KEY, v1));

        // Deploy — proxy should be immediately paused
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "Paused From Birth",
            symbol: "PFB",
            yieldRecipient: yieldRecipient,
            admin: builder,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address proxy = factory.deployBeaconYieldToOne("paused-from-birth", params);

        assertTrue(beacon.isProxyPaused(proxy));
        assertTrue(YieldToOne(proxy).paused());

        // View functions still work
        assertEq(YieldToOne(proxy).name(), "Paused From Birth");
        assertEq(YieldToOne(proxy).symbol(), "PFB");

        // Transfers revert
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        IERC20(proxy).transfer(bob, 100e6);

        // Unpause v1 — proxy resumes
        vm.prank(admin);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertFalse(beacon.isProxyPaused(proxy));
        assertFalse(YieldToOne(proxy).paused());
    }

    /* ============ SwapFacility Operations When Beacon-Paused ============ */

    function test_swapFacility_blockedWhenBeaconPaused() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "Swap Pause Test",
            symbol: "SPT",
            yieldRecipient: yieldRecipient,
            admin: builder,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address proxy = factory.deployBeaconYieldToOne("swap-pause-test", params);

        YieldToOne ext = YieldToOne(proxy);

        // Enable earning
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(proxy, 500, 0, address(0));

        // Wrap before pause
        uint256 wrapAmount = 1000e6;

        _mintPYUSDX(alice, wrapAmount);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), wrapAmount);

        vm.prank(alice);
        swapFacility.swapIn(proxy, wrapAmount, alice);

        assertEq(ext.balanceOf(alice), wrapAmount);

        // Pause v1 at beacon level
        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertTrue(ext.paused());

        // swapIn reverts
        _mintPYUSDX(bob, wrapAmount);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), wrapAmount);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(bob);
        swapFacility.swapIn(proxy, wrapAmount, bob);

        // swapOut reverts
        vm.prank(alice);
        IERC20(proxy).approve(address(swapFacility), wrapAmount);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swapOut(proxy, wrapAmount, alice);

        // swapExtensions reverts (transfer triggers _requireNotPaused)
        vm.prank(alice);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        IERC20(proxy).transfer(bob, 100e6);

        // Unpause — all operations resume
        vm.prank(admin);
        beacon.unpauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertFalse(ext.paused());

        vm.prank(alice);
        swapFacility.swapOut(proxy, wrapAmount, alice);

        assertEq(ext.balanceOf(alice), 0);
        assertEq(IERC20(address(pyusdx)).balanceOf(alice), wrapAmount);
    }

    /* ============ Type Pause Does Not Affect Other Types ============ */

    function test_typePause_isolationAcrossTypes() public {
        vm.prank(admin);
        beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        // Deploy a YieldToOne extension
        IExtensionFactory.YieldToOneParams memory ytoParams = IExtensionFactory.YieldToOneParams({
            name: "YTO Isolation",
            symbol: "YTOI",
            yieldRecipient: yieldRecipient,
            admin: builder,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address yieldToOneProxy = factory.deployBeaconYieldToOne("yto-isolation", ytoParams);

        // Register MULTI_MINT type key and deploy a MultiMint extension
        address multiMintImplV1 = address(new MultiMint(address(pyusdx), address(swapFacility)));

        vm.prank(admin);
        beacon.registerVersion(MULTI_MINT_TYPE_KEY, multiMintImplV1);

        IExtensionFactory.MultiMintParams memory multiMintParams = IExtensionFactory.MultiMintParams({
            name: "MM Isolation",
            symbol: "MMI",
            yieldRecipient: yieldRecipient,
            admin: builder,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address multiMintProxy = factory.deployBeaconMultiMint("mm-isolation", multiMintParams);

        // Pause YIELD_TO_ONE type
        vm.prank(admin);
        beacon.pauseType(YIELD_TO_ONE_TYPE_KEY);

        assertTrue(beacon.isTypePaused(YIELD_TO_ONE_TYPE_KEY));
        assertFalse(beacon.isTypePaused(MULTI_MINT_TYPE_KEY));

        assertTrue(YieldToOne(yieldToOneProxy).paused());
        assertFalse(MultiMint(multiMintProxy).paused());
    }

    /* ============ Version Pause Cross-Version Isolation ============ */

    function test_versionPause_onlyAffectsPinnedVersion() public {
        vm.prank(admin);
        uint256 v1 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV1);

        vm.prank(admin);
        uint256 v2 = beacon.registerVersion(YIELD_TO_ONE_TYPE_KEY, yieldToOneImplV2);

        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "V1 Ext",
            symbol: "V1E",
            yieldRecipient: yieldRecipient,
            admin: builder,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: builder
        });

        vm.prank(builder);
        address proxyV1 = factory.deployBeaconYieldToOne("v1-cross-ver", params);

        params.name = "V2 Ext";
        params.symbol = "V2E";

        vm.prank(admin);
        beacon.setLatestVersion(YIELD_TO_ONE_TYPE_KEY, v2);

        vm.prank(builder);
        address proxyV2 = factory.deployBeaconYieldToOne("v2-cross-ver", params);

        // Pause only v1
        vm.prank(admin);
        beacon.pauseVersion(YIELD_TO_ONE_TYPE_KEY, v1);

        assertTrue(beacon.isProxyPaused(proxyV1));
        assertFalse(beacon.isProxyPaused(proxyV2));

        assertTrue(YieldToOne(proxyV1).paused());
        assertFalse(YieldToOne(proxyV2).paused());
    }
}
