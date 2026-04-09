// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";

import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { IReentrancyLock } from "../../src/swap/interfaces/IReentrancyLock.sol";

import { ExtensionFactoryHarness } from "../harness/ExtensionFactoryHarness.sol";

import { MockExtensionBeacon } from "../mock/MockExtensionBeacon.sol";
import { MockPYUSDXExtension } from "../mock/MockPYUSDXExtension.sol";
import { MockTrustedRouter } from "../mock/MockTrustedRouter.sol";
import { MockRouterAwareExtension } from "../mock/MockRouterAwareExtension.sol";
import { MockReentrantExtension } from "../mock/MockReentrantExtension.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract ReentrancyLockUnitTests is PYUSDXBaseUnitTest {
    SwapFacility public swapFacility;
    MockPYUSDXExtension public extensionA;
    MockRouterAwareExtension public routerAwareExtension;
    ExtensionFactoryHarness public factory;

    uint256 public constant AMOUNT = 1000e6;

    function setUp() public override {
        super.setUp();

        // Predict factory proxy address
        // After super.setUp(), nonce is 4
        // new SwapFacility impl: 4 -> 5
        // deployTransparentProxy: 5 -> 6
        // new MockExtensionBeacon: 6 -> 7
        // new ExtensionFactoryHarness: 7 -> 8
        // deployTransparentProxy: 8 -> 9
        // Factory proxy is at nonce 8 = 4 + 4

        uint64 nonceBeforeDeployments = vm.getNonce(address(this));
        address predictedFactory = vm.computeCreateAddress(address(this), nonceBeforeDeployments + 4);

        address swapFacilityImplementation = address(new SwapFacility(address(pyusdx), predictedFactory));
        swapFacility = SwapFacility(
            UnsafeUpgrades.deployTransparentProxy(
                swapFacilityImplementation,
                admin,
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin, pauser)
            )
        );

        // Deploy mock beacon (unit tests use mocks, not real extensions)
        MockExtensionBeacon mockBeacon = new MockExtensionBeacon();

        // Deploy factory with actual SwapFacility address
        factory = ExtensionFactoryHarness(
            UnsafeUpgrades.deployTransparentProxy(
                address(new ExtensionFactoryHarness(address(pyusdx), address(swapFacility), address(mockBeacon))),
                admin,
                abi.encodeWithSelector(ExtensionFactory.initialize.selector, admin, factoryManager)
            )
        );

        extensionA = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        routerAwareExtension = new MockRouterAwareExtension(address(pyusdx), address(swapFacility));

        // Register mock extensions by default
        factory.registerExtension(address(extensionA), IExtensionBeacon.ExtensionType.YIELD_TO_ONE);
        factory.registerExtension(address(routerAwareExtension), IExtensionBeacon.ExtensionType.YIELD_TO_ONE);
    }

    function _setupSwapIn(address user, uint256 amount) internal {
        issuerGateway.mint(user, amount);

        vm.prank(user);
        IERC20(address(pyusdx)).approve(address(swapFacility), amount);
    }

    /* ============ setTrustedRouter (Admin) ============ */

    function test_setTrustedRouter_notAdmin() public {
        address router = makeAddr("router");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                swapFacility.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(alice);
        swapFacility.setTrustedRouter(router, true);
    }

    function test_setTrustedRouter_zeroRouter() public {
        vm.expectRevert(IReentrancyLock.ZeroRouter.selector);

        vm.prank(admin);
        swapFacility.setTrustedRouter(address(0), true);
    }

    function test_setTrustedRouter() public {
        address router = makeAddr("router");

        vm.expectEmit();
        emit IReentrancyLock.TrustedRouterSet(router, true);

        vm.prank(admin);
        swapFacility.setTrustedRouter(router, true);

        assertTrue(swapFacility.isTrustedRouter(router));
    }

    function test_setTrustedRouter_remove() public {
        address router = makeAddr("router");

        vm.prank(admin);
        swapFacility.setTrustedRouter(router, true);

        vm.expectEmit();
        emit IReentrancyLock.TrustedRouterSet(router, false);

        vm.prank(admin);
        swapFacility.setTrustedRouter(router, false);

        assertFalse(swapFacility.isTrustedRouter(router));
    }

    /* ============ msgSender (View) ============ */

    function test_msgSender_zero() public view {
        assertEq(swapFacility.msgSender(), address(0));
    }

    function test_msgSender_trustedRouter_resolvesOriginalUser_duringSwapCallback() public {
        MockTrustedRouter trustedRouter = new MockTrustedRouter();

        vm.prank(admin);
        swapFacility.setTrustedRouter(address(trustedRouter), true);

        _setupSwapIn(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(trustedRouter), AMOUNT);

        vm.prank(alice);
        trustedRouter.swapIn(IERC20(address(pyusdx)), swapFacility, address(routerAwareExtension), AMOUNT, alice);

        assertEq(routerAwareExtension.lastResolvedSender(), alice);
        assertEq(swapFacility.msgSender(), address(0));
    }

    function test_msgSender_untrustedRouter_resolvesRouter_duringSwapCallback() public {
        MockTrustedRouter untrustedRouter = new MockTrustedRouter();

        _setupSwapIn(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(untrustedRouter), AMOUNT);

        vm.prank(alice);
        untrustedRouter.swapIn(IERC20(address(pyusdx)), swapFacility, address(routerAwareExtension), AMOUNT, alice);

        assertEq(routerAwareExtension.lastResolvedSender(), address(untrustedRouter));
        assertEq(swapFacility.msgSender(), address(0));
    }

    /* ============ Reentrancy Protection ============ */

    function test_reentrancy_blocked() public {
        MockReentrantExtension reentrantExtension = new MockReentrantExtension(address(pyusdx), address(swapFacility));

        factory.registerExtension(address(reentrantExtension), IExtensionBeacon.ExtensionType.YIELD_TO_ONE);

        _setupSwapIn(alice, AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(reentrantExtension), AMOUNT, alice);

        assertTrue(reentrantExtension.reentrancyAttempted());
        assertTrue(reentrantExtension.reentrancyBlocked());
        assertEq(swapFacility.msgSender(), address(0));
    }
}
