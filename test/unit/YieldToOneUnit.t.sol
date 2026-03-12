// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Test } from "../../lib/evm-m-extensions/lib/forge-std/src/Test.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";
import { IssuerGatewayMock } from "../mock/IssuerGatewayMock.sol";
import { MockSwapFacility } from "../mock/MockSwapFacility.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";
import { IYieldToOne } from "../../src/platform/projects/interfaces/IYieldToOne.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { IERC20Extended } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20Extended.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";

contract YieldToOneUnitTests is Test {
    IssuerGatewayMock public issuerGateway;
    PYUSDXHarness public pyusdx;
    MockSwapFacility public swapFacility;
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
        issuerGateway = new IssuerGatewayMock(address(0));

        address pyusdxImplementation = address(new PYUSDXHarness());
        pyusdx = PYUSDXHarness(
            UnsafeUpgrades.deployTransparentProxy(
                pyusdxImplementation,
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

        swapFacility = new MockSwapFacility(address(pyusdx));

        address extensionImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
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
        pyusdx.setAccountInfo(address(extension), 500, 0, address(0));

        pyusdx.setAccountRateBps(address(extension), uint24(500));
    }

    /* ============ Helpers ============ */

    function _wrapFor(address to, address recipient, uint256 amount) internal {
        issuerGateway.mint(to, amount);

        vm.startPrank(to);
        IERC20(address(pyusdx)).approve(address(swapFacility), amount);
        swapFacility.swapIn(address(extension), amount, recipient);
        vm.stopPrank();
    }

    /* ============ Initialization ============ */

    function test_initialize() public view {
        assertEq(extension.name(), "Branded USD");
        assertEq(extension.symbol(), "bUSD");
        assertEq(extension.decimals(), 6);
        assertEq(extension.yieldRecipient(), yieldRecipient);
        assertEq(extension.pyusdx(), address(pyusdx));
        assertEq(extension.swapFacility(), address(swapFacility));
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

    function test_wrap_revert_notSwapFacility() public {
        vm.prank(alice);
        vm.expectRevert(IExtension.NotSwapFacility.selector);
        extension.wrap(alice, MINT_AMOUNT);
    }

    /* ============ Unwrap ============ */

    function test_unwrap() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.startPrank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);
        swapFacility.swapOut(address(extension), MINT_AMOUNT, alice);
        vm.stopPrank();

        assertEq(extension.balanceOf(alice), 0);
        assertEq(extension.totalSupply(), 0);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
    }

    function test_unwrap_revert_notSwapFacility() public {
        vm.prank(alice);
        vm.expectRevert(IExtension.NotSwapFacility.selector);
        extension.unwrap(MINT_AMOUNT);
    }

    /* ============ Swap Extensions ============ */

    function test_swapExtensions() public {
        // Deploy a second extension sharing the same swap facility.
        address extensionBImpl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        YieldToOne extensionB = YieldToOne(
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

        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.startPrank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);
        swapFacility.swapExtensions(address(extension), address(extensionB), MINT_AMOUNT, alice);
        vm.stopPrank();

        assertEq(extension.balanceOf(alice), 0);
        assertEq(extensionB.balanceOf(alice), MINT_AMOUNT);
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
        pyusdx.setAccountInfo(address(extension), 500, 1000, address(0));

        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.warp(block.timestamp + 365 days);

        (uint256 grossYield, , ) = pyusdx.accruedYieldAndFeeOf(address(extension));

        extension.claimYield();

        uint256 yieldRecipientBalance = extension.balanceOf(yieldRecipient);
        assertGt(yieldRecipientBalance, 0);
        assertLt(yieldRecipientBalance, grossYield);
        assertGt(pyusdx.balanceOf(earnerManager), 0);
    }

    function test_claimYield_zeroWhenYieldRedirected() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        // Redirect yield away from the extension
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(extension), 500, 0, alice);

        vm.warp(block.timestamp + 365 days);

        assertGt(pyusdx.accruedYieldOf(address(extension)), 0);
        assertEq(extension.yield(), 0);

        uint256 claimed = extension.claimYield();
        assertEq(claimed, 0);
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

    function test_yield_includesExcessAfterDirectClaimFor() public {
        _wrapFor(alice, alice, MINT_AMOUNT);
        vm.warp(block.timestamp + 365 days);

        uint256 yieldBefore = extension.yield();
        assertGt(yieldBefore, 0);

        // Direct claimFor bypass — yield lands in extension but no tokens minted.
        pyusdx.claimFor(address(extension));

        // yield() should still show the excess (realized but unminted).
        uint256 yieldAfter = extension.yield();
        assertGt(yieldAfter, 0);
        assertEq(yieldAfter, pyusdx.balanceOf(address(extension)) - extension.totalSupply());

        // claimYield should recover the excess.
        uint256 claimed = extension.claimYield();
        assertEq(claimed, yieldAfter);
        assertEq(extension.balanceOf(yieldRecipient), claimed);
        assertEq(extension.yield(), 0);
    }

    function test_yield_includesRandomPyusdxTransfer() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        // Someone sends PYUSDX directly to the extension.
        uint256 gift = 100e6;
        issuerGateway.mint(bob, gift);
        vm.prank(bob);
        IERC20(address(pyusdx)).transfer(address(extension), gift);

        // yield() should reflect the excess.
        assertGe(extension.yield(), gift);

        // claimYield recovers it.
        uint256 claimed = extension.claimYield();
        assertGe(claimed, gift);
        assertEq(extension.balanceOf(yieldRecipient), claimed);
    }

    /* ============ Freeze via SwapFacility ============ */

    function test_unwrap_revert_frozen() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swapOut(address(extension), MINT_AMOUNT, alice);
    }

    function test_wrap_revert_frozen() public {
        issuerGateway.mint(alice, MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(alice);

        vm.startPrank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), MINT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swapIn(address(extension), MINT_AMOUNT, alice);
        vm.stopPrank();
    }
}
