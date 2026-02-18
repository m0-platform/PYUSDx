// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Test } from "../../lib/m-extensions/lib/forge-std/src/Test.sol";
import { UnsafeUpgrades } from "../../lib/m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";
import { MinterGatewayMock } from "../mock/MinterGatewayMock.sol";
import { YieldToOne } from "../../src/YieldToOne.sol";
import { IYieldToOne } from "../../src/interfaces/IYieldToOne.sol";
import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/m-extensions/src/components/freezable/IFreezable.sol";
import { IERC20Extended } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20Extended.sol";
import { MaliciousExtensionMock } from "../mock/MaliciousExtensionMock.sol";
import { ReentrantExtensionMock } from "../mock/ReentrantExtensionMock.sol";
import { WrongPyusdxExtensionMock } from "../mock/WrongPyusdxExtensionMock.sol";
import { IPYUSDXExtension } from "../../src/interfaces/IPYUSDXExtension.sol";
import { ReentrancyGuardTransientUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardTransientUpgradeable.sol";

contract YieldToOneUnitTests is Test {
    MinterGatewayMock public minterGateway;
    PYUSDXHarness public pyusdx;
    YieldToOne public extension;

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public freezeManager = makeAddr("freezeManager");
    address public earnerManager = makeAddr("earnerManager");
    address public rateManager = makeAddr("rateManager");
    address public yieldRecipientManager = makeAddr("yieldRecipientManager");

    address public yieldRecipient = makeAddr("yieldRecipient");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant MINT_AMOUNT = 1000e6;

    function setUp() public {
        minterGateway = new MinterGatewayMock(address(0));

        address pyusdxImpl = address(new PYUSDXHarness(address(minterGateway)));
        pyusdx = PYUSDXHarness(
            UnsafeUpgrades.deployTransparentProxy(
                pyusdxImpl,
                admin,
                abi.encodeWithSelector(
                    PYUSDX.initialize.selector,
                    "PayPal USD Yield",
                    "PYUSDX",
                    admin,
                    pauser,
                    freezeManager,
                    address(1),
                    earnerManager,
                    rateManager
                )
            )
        );
        minterGateway.setPyusdx(address(pyusdx));

        address extensionImpl = address(new YieldToOne(address(pyusdx)));
        extension = YieldToOne(
            UnsafeUpgrades.deployTransparentProxy(
                extensionImpl,
                admin,
                abi.encodeWithSelector(
                    YieldToOne.initialize.selector,
                    "Branded USD",
                    "bUSD",
                    yieldRecipient,
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    pauser
                )
            )
        );

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(address(extension), true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(address(extension), uint24(500));

        vm.prank(rateManager);
        pyusdx.setEarnerRate(address(extension), 500);
    }

    /* ============ Helpers ============ */

    function _wrapFor(address to, address recipient, uint256 amount) internal {
        minterGateway.mint(to, amount);

        vm.prank(to);
        IERC20(address(pyusdx)).approve(address(extension), amount);

        vm.prank(to);
        extension.wrap(recipient, amount);
    }

    /* ============ Initialization ============ */

    function test_initialize() public view {
        assertEq(extension.name(), "Branded USD");
        assertEq(extension.symbol(), "bUSD");
        assertEq(extension.decimals(), 6);
        assertEq(extension.yieldRecipient(), yieldRecipient);
        assertEq(extension.pyusdx(), address(pyusdx));
        assertTrue(extension.hasRole(extension.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(extension.hasRole(extension.YIELD_RECIPIENT_MANAGER_ROLE(), yieldRecipientManager));
    }

    /* ============ Wrap ============ */

    function test_wrap() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        assertEq(extension.balanceOf(alice), MINT_AMOUNT);
        assertEq(extension.totalSupply(), MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(address(extension)), MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), 0);
    }

    function test_wrap_toRecipient() public {
        _wrapFor(alice, bob, MINT_AMOUNT);

        assertEq(extension.balanceOf(alice), 0);
        assertEq(extension.balanceOf(bob), MINT_AMOUNT);
    }

    /* ============ Unwrap ============ */

    function test_unwrap() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        extension.unwrap(MINT_AMOUNT);

        assertEq(extension.balanceOf(alice), 0);
        assertEq(extension.totalSupply(), 0);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
    }

    /* ============ WrapFrom ============ */

    function _deployExtensionB() internal returns (YieldToOne) {
        address extensionBImpl = address(new YieldToOne(address(pyusdx)));
        return
            YieldToOne(
                UnsafeUpgrades.deployTransparentProxy(
                    extensionBImpl,
                    admin,
                    abi.encodeWithSelector(
                        YieldToOne.initialize.selector,
                        "Branded USD B",
                        "bUSDB",
                        yieldRecipient,
                        admin,
                        freezeManager,
                        yieldRecipientManager,
                        pauser
                    )
                )
            );
    }

    function test_wrapFrom() public {
        YieldToOne extensionB = _deployExtensionB();

        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(extensionB), MINT_AMOUNT);

        vm.prank(alice);
        extensionB.wrapFrom(address(extension), MINT_AMOUNT);

        assertEq(extension.balanceOf(alice), 0);
        assertEq(extensionB.balanceOf(alice), MINT_AMOUNT);
    }

    function test_wrapFrom_revert_frozenOnSourceExtension() public {
        YieldToOne extensionB = _deployExtensionB();

        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(extensionB), MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        extensionB.wrapFrom(address(extension), MINT_AMOUNT);
    }

    function test_wrapFrom_revert_frozenOnDestinationExtension() public {
        YieldToOne extensionB = _deployExtensionB();

        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(extensionB), MINT_AMOUNT);

        vm.prank(freezeManager);
        extensionB.freeze(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        extensionB.wrapFrom(address(extension), MINT_AMOUNT);
    }

    function test_wrapFrom_revert_frozenOnBothExtensions() public {
        YieldToOne extensionB = _deployExtensionB();

        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(extensionB), MINT_AMOUNT);

        vm.startPrank(freezeManager);
        extension.freeze(alice);
        extensionB.freeze(alice);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        extensionB.wrapFrom(address(extension), MINT_AMOUNT);
    }

    function test_wrapFrom_emitsSwappedFrom() public {
        YieldToOne extensionB = _deployExtensionB();

        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(extensionB), MINT_AMOUNT);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(extensionB));
        emit IPYUSDXExtension.SwappedFrom(address(extension), alice, MINT_AMOUNT);
        extensionB.wrapFrom(address(extension), MINT_AMOUNT);
    }

    function test_wrapFrom_revert_zeroExtension() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPYUSDXExtension.InvalidExtension.selector, address(0)));
        extension.wrapFrom(address(0), MINT_AMOUNT);
    }

    function test_wrapFrom_revert_wrongPyusdx() public {
        WrongPyusdxExtensionMock wrongExtension = new WrongPyusdxExtensionMock();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPYUSDXExtension.InvalidExtension.selector, address(wrongExtension)));
        extension.wrapFrom(address(wrongExtension), MINT_AMOUNT);
    }

    function test_wrapFrom_revert_maliciousExtension() public {
        MaliciousExtensionMock malicious = new MaliciousExtensionMock(address(pyusdx));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        extension.wrapFrom(address(malicious), MINT_AMOUNT);
    }

    function test_wrapFrom_revert_reentrancy() public {
        ReentrantExtensionMock reentrant = new ReentrantExtensionMock(address(extension), address(pyusdx));

        vm.prank(alice);
        vm.expectRevert(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector);
        extension.wrapFrom(address(reentrant), MINT_AMOUNT);
    }

    /* ============ Transfer ============ */

    function test_transfer() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        extension.transfer(bob, 400e6);

        assertEq(extension.balanceOf(alice), 600e6);
        assertEq(extension.balanceOf(bob), 400e6);
        assertEq(extension.totalSupply(), MINT_AMOUNT);
    }

    function test_transferFrom() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        extension.approve(bob, 400e6);

        vm.prank(bob);
        extension.transferFrom(alice, bob, 400e6);

        assertEq(extension.balanceOf(alice), 600e6);
        assertEq(extension.balanceOf(bob), 400e6);
    }

    /* ============ ClaimYield ============ */

    function test_claimYield() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.warp(block.timestamp + 365 days);

        assertGt(pyusdx.accruedYieldOf(address(extension)), 0);
        assertGt(extension.yield(), 0);

        uint256 claimed = extension.claimYield();

        assertGt(claimed, 0);
        assertEq(extension.balanceOf(yieldRecipient), claimed);
        assertEq(extension.totalSupply(), MINT_AMOUNT + claimed);
        assertEq(extension.yield(), 0);
    }

    function test_claimYield_noYield() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        uint256 claimed = extension.claimYield();
        assertEq(claimed, 0);
        assertEq(extension.balanceOf(yieldRecipient), 0);
    }

    function test_claimYield_withFee() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(address(extension), true, earnerManager, 1000, address(0));

        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.warp(block.timestamp + 365 days);

        uint256 grossYield = pyusdx.accruedYieldOf(address(extension));

        extension.claimYield();

        uint256 yieldRecipientBalance = extension.balanceOf(yieldRecipient);
        assertGt(yieldRecipientBalance, 0);
        assertLt(yieldRecipientBalance, grossYield);
        assertGt(pyusdx.balanceOf(earnerManager), 0);
    }

    /* ============ SetYieldRecipient ============ */

    function test_setYieldRecipient() public {
        _wrapFor(alice, alice, MINT_AMOUNT);
        vm.warp(block.timestamp + 365 days);

        address newRecipient = makeAddr("newRecipient");

        vm.prank(yieldRecipientManager);
        extension.setYieldRecipient(newRecipient);

        assertEq(extension.yieldRecipient(), newRecipient);
        assertGt(extension.balanceOf(yieldRecipient), 0);

        vm.warp(block.timestamp + 365 days);
        extension.claimYield();

        assertGt(extension.balanceOf(newRecipient), 0);
    }

    /* ============ Yield View ============ */

    function test_yield_nonzeroBeforeClaim() public {
        _wrapFor(alice, alice, MINT_AMOUNT);
        vm.warp(block.timestamp + 365 days);

        assertGt(extension.yield(), 0);
    }

    function test_yield_zeroAfterExternalClaim() public {
        _wrapFor(alice, alice, MINT_AMOUNT);
        vm.warp(block.timestamp + 365 days);

        pyusdx.claimFor(address(extension));

        assertEq(extension.yield(), 0);
    }
}
