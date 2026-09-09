// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { ERC1967Utils } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IERC1967 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { UUPSUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";
import { ExtensionBeacon } from "../../src/platform/ExtensionBeacon.sol";
import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";
import { ExtensionBeaconProxy } from "../../src/platform/ExtensionBeaconProxy.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";

import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { MockIssuerGateway } from "../mock/MockIssuerGateway.sol";
import { MockSwapFacility } from "../mock/MockSwapFacility.sol";
import { BaseTest } from "../utils/BaseTest.sol";

import { MultiMintUUPSBridge, MultiMintLeanBridge, MultiMintSelfManagedV2, StandaloneToken } from "./SpikeImplementations.sol";

/// @dev Spike: can a deployed MultiMint ExtensionBeaconProxy be moved off the shared beacon and
///      manage its own upgrades (UUPS) without redeploying the proxy?
contract BeaconToUUPSSpike is BaseTest {
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant _ORIGIN_BEACON_SLOT = 0x0db096ce50da19b63b97b47df5b0c87e2ed1677b3d801ad424e1bbfc0bb0c300;

    MockIssuerGateway public issuerGateway;
    PYUSDXHarness public pyusdx;
    MockSwapFacility public swapFacility;
    MockERC20 public usdc;

    ExtensionBeacon public beacon;
    MultiMint public implV1;
    MultiMintUUPSBridge public bridgeImpl;
    MultiMintLeanBridge public leanBridgeImpl;
    MultiMintSelfManagedV2 public selfManagedImpl;
    StandaloneToken public standaloneImpl;

    MultiMint public concUSD; // the extension being converted
    MultiMint public bystander; // an unrelated extension that stays in beacon mode

    address public issuer = makeAddr("issuer");
    address public concreteAdmin; // DEFAULT_ADMIN of concUSD

    uint256 internal constant ALICE_PYUSDX = 1_000e6;
    uint256 internal constant BOB_USDC = 500e6;

    struct Snapshot {
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        uint256 aliceBalance;
        uint256 bobBalance;
        uint256 aliceAllowanceToBob;
        address yieldRecipient;
        uint256 usdcBalance;
        uint256 usdcCap;
        uint256 totalAssets;
        uint256 pyusdxHeld;
        bool adminRole;
        bool versionManagerRole;
        bool assetCapManagerRole;
        bool freezeManagerRole;
        address originBeacon;
    }

    function setUp() public override {
        super.setUp();

        concreteAdmin = admin;

        issuerGateway = new MockIssuerGateway(address(0));
        pyusdx = PYUSDXHarness(
            UnsafeUpgrades.deployTransparentProxy(
                address(new PYUSDXHarness()),
                admin,
                abi.encodeCall(
                    PYUSDX.initialize,
                    (
                        IPYUSDX.InitializeParams({
                            name: "PayPal USD Yield",
                            symbol: "PYUSDX",
                            admin: admin,
                            pauser: pauser,
                            freezeManager: freezeManager,
                            forcedTransferManager: address(1),
                            earnerManager: earnerManager,
                            rateLimitManager: rateManager,
                            issuer: address(issuerGateway)
                        })
                    )
                )
            )
        );
        issuerGateway.setPyusdx(address(pyusdx));
        vm.prank(rateManager);
        pyusdx.setRateLimit(address(issuerGateway), type(uint128).max, 0, true);

        swapFacility = new MockSwapFacility(address(pyusdx));
        usdc = new MockERC20("USD Coin", "USDC", 6);

        implV1 = new MultiMint(address(pyusdx), address(swapFacility));
        bridgeImpl = new MultiMintUUPSBridge(address(pyusdx), address(swapFacility));
        selfManagedImpl = new MultiMintSelfManagedV2(address(pyusdx), address(swapFacility));
        standaloneImpl = new StandaloneToken();

        beacon = ExtensionBeacon(
            UnsafeUpgrades.deployTransparentProxy(
                address(new ExtensionBeacon(address(pyusdx), address(swapFacility))),
                admin,
                abi.encodeWithSelector(ExtensionBeacon.initialize.selector, admin, beaconManager, address(implV1))
            )
        );

        concUSD = _deployExtension("Concrete USD", "ConcUSD");
        bystander = _deployExtension("Other MultiMint", "OMM");
        leanBridgeImpl = new MultiMintLeanBridge(address(pyusdx), address(swapFacility), address(concUSD));

        // Give concUSD real state: PYUSDX backing from alice, USDC backing from bob, an allowance.
        vm.prank(assetCapManager);
        concUSD.setAssetCap(address(usdc), 1_000_000e6);

        issuerGateway.mint(alice, ALICE_PYUSDX);
        vm.startPrank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), ALICE_PYUSDX);
        swapFacility.swapIn(address(concUSD), ALICE_PYUSDX, alice);
        IERC20(address(concUSD)).approve(bob, 7e6);
        vm.stopPrank();

        usdc.mint(bob, BOB_USDC);
        vm.startPrank(bob);
        usdc.approve(address(swapFacility), BOB_USDC);
        swapFacility.swapInAsset(address(concUSD), address(usdc), BOB_USDC, bob);
        vm.stopPrank();
    }

    /* ============ Helpers ============ */

    function _deployExtension(string memory name_, string memory symbol_) internal returns (MultiMint) {
        bytes memory initData = abi.encodeWithSelector(
            MultiMint.initialize.selector,
            name_,
            symbol_,
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            yieldRecipientManager,
            versionManager
        );
        return MultiMint(address(new ExtensionBeaconProxy(address(beacon), initData)));
    }

    function _slot(address proxy, bytes32 slot) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, slot))));
    }

    function _snapshot(address ext) internal view returns (Snapshot memory s) {
        MultiMint mm = MultiMint(ext);
        s.name = mm.name();
        s.symbol = mm.symbol();
        s.decimals = mm.decimals();
        s.totalSupply = mm.totalSupply();
        s.aliceBalance = mm.balanceOf(alice);
        s.bobBalance = mm.balanceOf(bob);
        s.aliceAllowanceToBob = mm.allowance(alice, bob);
        s.yieldRecipient = mm.yieldRecipient();
        s.usdcBalance = mm.assetBalanceOf(address(usdc));
        s.usdcCap = mm.assetCap(address(usdc));
        s.totalAssets = mm.totalAssets();
        s.pyusdxHeld = pyusdx.balanceOf(ext);
        s.adminRole = mm.hasRole(0x00, concreteAdmin);
        s.versionManagerRole = mm.hasRole(mm.VERSION_MANAGER_ROLE(), versionManager);
        s.assetCapManagerRole = mm.hasRole(mm.ASSET_CAP_MANAGER_ROLE(), assetCapManager);
        s.freezeManagerRole = mm.hasRole(mm.FREEZE_MANAGER_ROLE(), freezeManager);
        s.originBeacon = mm.originBeacon();
    }

    function _assertSnapshotEq(Snapshot memory a, Snapshot memory b) internal pure {
        assertEq(keccak256(abi.encode(a)), keccak256(abi.encode(b)), "state changed across upgrade");
    }

    /// @dev Registers the bridge and immediately re-registers V1 so `latest` is unchanged for
    ///      beacon-mode extensions. Returns the bridge's version number.
    function _registerBridgeAtomically() internal returns (uint256 bridgeVersion) {
        vm.startPrank(beaconManager);
        bridgeVersion = beacon.registerImplementation(address(bridgeImpl));
        beacon.registerImplementation(address(implV1));
        vm.stopPrank();
    }

    function _pinToBridge() internal returns (uint256 bridgeVersion) {
        bridgeVersion = _registerBridgeAtomically();
        vm.prank(versionManager);
        concUSD.pinVersion(bridgeVersion);
    }

    /* ============ Preconditions ============ */

    function test_precondition_beaconModeProxyHasEmptyImplementationSlot() public view {
        assertEq(_slot(address(concUSD), _IMPLEMENTATION_SLOT), address(0));
        assertEq(_slot(address(concUSD), _BEACON_SLOT), address(beacon));
        assertEq(_slot(address(concUSD), _ORIGIN_BEACON_SLOT), address(beacon));
        assertEq(concUSD.balanceOf(alice), ALICE_PYUSDX);
        assertEq(concUSD.balanceOf(bob), BOB_USDC);
    }

    function test_precondition_pinVersionOnlyAcceptsBeaconRegisteredImplementations() public {
        // There is no way to pin to an implementation M0 has not registered.
        vm.prank(versionManager);
        vm.expectRevert(IExtensionBeacon.NoImplementationRegistered.selector);
        concUSD.pinVersion(2);
    }

    /* ============ What breaks: the shared beacon ============ */

    function test_break_registeringBridgeMovesEveryBeaconModeExtension() public {
        vm.prank(beaconManager);
        beacon.registerImplementation(address(bridgeImpl));

        // `bystander` never opted in, yet it now runs the bridge code (UUPS surface is live on it).
        assertEq(UUPSUpgradeable(address(bystander)).UPGRADE_INTERFACE_VERSION(), "5.0.0");

        // Mitigation: re-register V1 so latest points back at plain MultiMint. Must be atomic
        // with the bridge registration (same tx / same Safe batch) to avoid a window.
        vm.prank(beaconManager);
        beacon.registerImplementation(address(implV1));

        vm.expectRevert();
        UUPSUpgradeable(address(bystander)).UPGRADE_INTERFACE_VERSION();
        assertEq(beacon.latestVersion(), 3);
        assertEq(beacon.implementation(2), address(bridgeImpl));
    }

    function test_break_upgradeToAndCallRevertsWhileInBeaconMode() public {
        vm.prank(beaconManager);
        beacon.registerImplementation(address(bridgeImpl));

        // The proxy resolves the bridge via the beacon, but UUPS's onlyProxy check reads the
        // ERC-1967 implementation slot, which is zero in beacon mode. Pinning is mandatory first.
        vm.prank(versionManager);
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        UUPSUpgradeable(address(concUSD)).upgradeToAndCall(address(selfManagedImpl), "");
    }

    /* ============ The conversion ============ */

    function test_convert_pinToBridgeFlipsProxyToDirectMode() public {
        Snapshot memory before = _snapshot(address(concUSD));

        uint256 bridgeVersion = _pinToBridge();

        assertEq(bridgeVersion, 2);
        assertEq(_slot(address(concUSD), _IMPLEMENTATION_SLOT), address(bridgeImpl));
        assertEq(_slot(address(concUSD), _BEACON_SLOT), address(0));
        assertEq(_slot(address(concUSD), _ORIGIN_BEACON_SLOT), address(beacon));
        assertTrue(concUSD.isPinned());
        _assertSnapshotEq(before, _snapshot(address(concUSD)));
    }

    function test_convert_selfManagedUpgradeWithoutM0() public {
        _pinToBridge();
        Snapshot memory before = _snapshot(address(concUSD));

        vm.expectEmit(true, false, false, false, address(concUSD));
        emit IERC1967.Upgraded(address(selfManagedImpl));

        vm.prank(versionManager);
        UUPSUpgradeable(address(concUSD)).upgradeToAndCall(address(selfManagedImpl), "");

        // Proxy now points at code M0 never registered. Same address, same storage.
        assertEq(_slot(address(concUSD), _IMPLEMENTATION_SLOT), address(selfManagedImpl));
        assertEq(_slot(address(concUSD), _BEACON_SLOT), address(0));
        assertEq(MultiMintSelfManagedV2(address(concUSD)).spikeVersion(), 2);
        _assertSnapshotEq(before, _snapshot(address(concUSD)));

        // Platform flows keep working: transfer, wrap, unwrap through the swap facility.
        vm.prank(alice);
        concUSD.transfer(carol, 10e6);
        assertEq(concUSD.balanceOf(carol), 10e6);

        issuerGateway.mint(carol, 5e6);
        vm.startPrank(carol);
        IERC20(address(pyusdx)).approve(address(swapFacility), 5e6);
        swapFacility.swapIn(address(concUSD), 5e6, carol);
        assertEq(concUSD.balanceOf(carol), 15e6);
        IERC20(address(concUSD)).approve(address(swapFacility), 15e6);
        swapFacility.swapOut(address(concUSD), 15e6, carol);
        vm.stopPrank();
        assertEq(concUSD.balanceOf(carol), 0);
        assertEq(pyusdx.balanceOf(carol), 15e6);

        // The beacon no longer reaches this proxy.
        vm.prank(beaconManager);
        beacon.registerImplementation(address(bridgeImpl));
        assertEq(_slot(address(concUSD), _IMPLEMENTATION_SLOT), address(selfManagedImpl));
        assertEq(MultiMintSelfManagedV2(address(concUSD)).spikeVersion(), 2);

        // And the return path is severed.
        vm.startPrank(versionManager);
        vm.expectRevert(MultiMintSelfManagedV2.Detached.selector);
        concUSD.unpinVersion();
        vm.expectRevert(MultiMintSelfManagedV2.Detached.selector);
        concUSD.pinVersion(1);
        vm.stopPrank();
    }

    function test_convert_upgradeIsGatedByVersionManagerRole() public {
        _pinToBridge();
        bytes32 role = concUSD.VERSION_MANAGER_ROLE();

        vm.prank(concreteAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, concreteAdmin, role)
        );
        UUPSUpgradeable(address(concUSD)).upgradeToAndCall(address(selfManagedImpl), "");
    }

    function test_convert_cannotUpgradeToNonUUPSImplementation() public {
        _pinToBridge();

        // OZ's UUPS requires the target to answer proxiableUUID(). Plain MultiMint does not.
        vm.prank(versionManager);
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(implV1)));
        UUPSUpgradeable(address(concUSD)).upgradeToAndCall(address(implV1), "");
    }

    /* ============ What breaks: the bridge alone is not a one-way door ============ */

    function test_break_bridgeStillAllowsUnpinBackToBeacon() public {
        _pinToBridge();

        vm.prank(versionManager);
        concUSD.unpinVersion();

        assertEq(_slot(address(concUSD), _IMPLEMENTATION_SLOT), address(0));
        assertEq(_slot(address(concUSD), _BEACON_SLOT), address(beacon));
        vm.expectRevert();
        UUPSUpgradeable(address(concUSD)).UPGRADE_INTERFACE_VERSION();
    }

    /* ============ The migration: leave the platform entirely ============ */

    function test_migrate_leavePlatformKeepingBalancesAndRoles() public {
        _pinToBridge();
        Snapshot memory before = _snapshot(address(concUSD));

        vm.prank(versionManager);
        UUPSUpgradeable(address(concUSD)).upgradeToAndCall(
            address(standaloneImpl),
            abi.encodeCall(StandaloneToken.migrate, (issuer))
        );

        StandaloneToken token = StandaloneToken(address(concUSD));

        // Everything in the ERC-7201 namespaces survives: metadata, balances, allowance, roles.
        assertEq(token.name(), before.name);
        assertEq(token.symbol(), before.symbol);
        assertEq(token.decimals(), before.decimals);
        assertEq(token.totalSupply(), before.totalSupply);
        assertEq(token.balanceOf(alice), before.aliceBalance);
        assertEq(token.balanceOf(bob), before.bobBalance);
        assertEq(token.allowance(alice, bob), before.aliceAllowanceToBob);
        assertTrue(token.hasRole(0x00, concreteAdmin));
        assertTrue(token.hasRole(token.ISSUER_ROLE(), issuer));

        // New issuance model works.
        vm.prank(issuer);
        token.mint(carol, 42e6);
        assertEq(token.balanceOf(carol), 42e6);
        vm.prank(alice);
        token.transfer(carol, 1e6);
        assertEq(token.balanceOf(carol), 43e6);

        // Platform hooks are gone: the swap facility can no longer wrap into this address.
        issuerGateway.mint(carol, 1e6);
        vm.startPrank(carol);
        IERC20(address(pyusdx)).approve(address(swapFacility), 1e6);
        vm.expectRevert();
        swapFacility.swapIn(address(concUSD), 1e6, carol);
        vm.stopPrank();

        // The PYUSDX and USDC backing are now ordinary balances under the new code's control.
        assertEq(pyusdx.balanceOf(address(token)), before.pyusdxHeld);
        assertEq(usdc.balanceOf(address(token)), before.usdcBalance);
        vm.prank(concreteAdmin);
        token.sweep(address(pyusdx), concreteAdmin, before.pyusdxHeld);
        assertEq(pyusdx.balanceOf(concreteAdmin), before.pyusdxHeld);

        // Reinitializer cannot be replayed.
        vm.prank(versionManager);
        vm.expectRevert();
        token.migrate(issuer);
    }

    /* ============ Lean, per-extension bridge ============ */

    function test_lean_scopedBridgeUpgradesOnlyItsOwnProxy() public {
        vm.startPrank(beaconManager);
        uint256 leanVersion = beacon.registerImplementation(address(leanBridgeImpl));
        beacon.registerImplementation(address(implV1));
        vm.stopPrank();

        vm.startPrank(versionManager);
        concUSD.pinVersion(leanVersion);
        bystander.pinVersion(leanVersion);

        // The bystander's version manager holds the same role but this bridge refuses it.
        vm.expectRevert(abi.encodeWithSelector(MultiMintLeanBridge.NotAllowedProxy.selector, address(bystander)));
        MultiMintLeanBridge(address(bystander)).upgradeToAndCall(address(selfManagedImpl), "");

        // Plain MultiMint is rejected as a target: no proxiableUUID().
        vm.expectRevert();
        MultiMintLeanBridge(address(concUSD)).upgradeToAndCall(address(implV1), "");

        Snapshot memory before = _snapshot(address(concUSD));
        MultiMintLeanBridge(address(concUSD)).upgradeToAndCall(address(selfManagedImpl), "");
        vm.stopPrank();

        assertEq(_slot(address(concUSD), _IMPLEMENTATION_SLOT), address(selfManagedImpl));
        assertEq(MultiMintSelfManagedV2(address(concUSD)).spikeVersion(), 2);
        _assertSnapshotEq(before, _snapshot(address(concUSD)));

        // Bystander unpins back to the beacon, unharmed.
        vm.prank(versionManager);
        bystander.unpinVersion();
        assertEq(_slot(address(bystander), _BEACON_SLOT), address(beacon));
    }
}
