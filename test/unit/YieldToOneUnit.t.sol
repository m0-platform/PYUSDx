// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Test } from "../../lib/evm-m-extensions/lib/forge-std/src/Test.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";
import { MockIssuerGateway } from "../mock/MockIssuerGateway.sol";
import { MockSwapFacility } from "../mock/MockSwapFacility.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";
import { IYieldToOne } from "../../src/platform/projects/interfaces/IYieldToOne.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { MockVersionedBeacon } from "../mock/MockVersionedBeacon.sol";

contract YieldToOneUnitTests is Test {
    MockIssuerGateway public issuerGateway;
    PYUSDXHarness public pyusdx;
    MockSwapFacility public swapFacility;
    YieldToOne public extension;
    MockVersionedBeacon public mockBeacon;

    /// @dev ERC-1967 beacon storage slot (same as YieldToOne._BEACON_SLOT).
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

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
        issuerGateway = new MockIssuerGateway(address(0));

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
                    yieldRecipientManager
                )
            )
        );

        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(extension), 500, 0, address(0));

        pyusdx.setAccountRateBps(address(extension), uint24(500));

        // Deploy a mock beacon and wire it into the extension's ERC-1967 beacon slot.
        mockBeacon = new MockVersionedBeacon();
        vm.store(address(extension), _BEACON_SLOT, bytes32(uint256(uint160(address(mockBeacon)))));
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

    function test_initialize_revert_zeroAdmin() public {
        address impl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        vm.expectRevert(IYieldToOne.ZeroAdmin.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                YieldToOne.initialize.selector,
                "Branded USD",
                "bUSD",
                yieldRecipient,
                address(0),
                freezeManager,
                yieldRecipientManager
            )
        );
    }

    function test_initialize_revert_zeroYieldRecipientManager() public {
        address impl = address(new YieldToOne(address(pyusdx), address(swapFacility)));
        vm.expectRevert(IYieldToOne.ZeroYieldRecipientManager.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                YieldToOne.initialize.selector,
                "Branded USD",
                "bUSD",
                yieldRecipient,
                admin,
                freezeManager,
                address(0)
            )
        );
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
                    yieldRecipientManager
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

    /* ============ Pausable ============ */

    function test_claimYield_succeedsWhenPaused() public {
        _wrapFor(alice, alice, MINT_AMOUNT);
        vm.warp(block.timestamp + 365 days);

        vm.prank(pauser);
        extension.pause();

        uint256 claimed = extension.claimYield();
        assertGt(claimed, 0);
        assertEq(extension.balanceOf(yieldRecipient), claimed);
    }

    /* ============ Access Control ============ */

    function test_setYieldRecipient_revert_notManager() public {
        address newRecipient = makeAddr("newRecipient");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                extension.YIELD_RECIPIENT_MANAGER_ROLE()
            )
        );
        vm.prank(alice);
        extension.setYieldRecipient(newRecipient);
    }

    function test_setYieldRecipient_revert_zeroAddress() public {
        vm.prank(yieldRecipientManager);
        vm.expectRevert(IYieldToOne.ZeroYieldRecipient.selector);
        extension.setYieldRecipient(address(0));
    }

    /* ============ Event Emission ============ */

    function test_claimYield_emitsYieldClaimed() public {
        _wrapFor(alice, alice, MINT_AMOUNT);
        vm.warp(block.timestamp + 365 days);

        uint256 expectedYield = extension.yield();
        assertGt(expectedYield, 0);

        vm.expectEmit();
        emit IYieldToOne.YieldClaimed(expectedYield);

        extension.claimYield();
    }

    /* ============ transfer ============ */

    function test_transfer_revert_insufficientBalance() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IExtension.InsufficientBalance.selector, alice, MINT_AMOUNT, MINT_AMOUNT + 1)
        );
        extension.transfer(bob, MINT_AMOUNT + 1);
    }

    /* ============ Pausable (beacon-based) ============ */

    function test_wrap_revert_paused() public {
        issuerGateway.mint(alice, MINT_AMOUNT);

        mockBeacon.setPaused(true);

        vm.startPrank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), MINT_AMOUNT);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        swapFacility.swapIn(address(extension), MINT_AMOUNT, alice);
        vm.stopPrank();
    }

    function test_transfer_revert_paused() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        mockBeacon.setPaused(true);

        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        extension.transfer(bob, 400e6);
    }

    function test_unwrap_revert_paused() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        mockBeacon.setPaused(true);

        vm.startPrank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        swapFacility.swapOut(address(extension), MINT_AMOUNT, alice);
        vm.stopPrank();
    }

    function test_approve_succeedsWhenPaused() public {
        _wrapFor(alice, alice, MINT_AMOUNT);

        mockBeacon.setPaused(true);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);
    }

    function test_claimYield_succeedsWhenPaused() public {
        _wrapFor(alice, alice, MINT_AMOUNT);
        vm.warp(block.timestamp + 365 days);

        mockBeacon.setPaused(true);

        uint256 claimed = extension.claimYield();
        assertGt(claimed, 0);
        assertEq(extension.balanceOf(yieldRecipient), claimed);
    }
}
