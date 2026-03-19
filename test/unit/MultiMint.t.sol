// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Test } from "../../lib/evm-m-extensions/lib/forge-std/src/Test.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";
import { MockIssuerGateway } from "../mock/MockIssuerGateway.sol";
import { MockSwapFacility } from "../mock/MockSwapFacility.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { IMultiMint } from "../../src/platform/projects/interfaces/IMultiMint.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { PausableUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { MockFeeOnTransfer } from "../mock/MockFeeOnTransfer.sol";

contract MultiMintTest is Test {
    MockIssuerGateway public issuerGateway;
    PYUSDXHarness public pyusdx;
    MockSwapFacility public swapFacility;
    MultiMint public extension;

    MockERC20 public usdc; // 6 decimals
    MockERC20 public dai; // 18 decimals
    MockERC20 public fourDec; // 4 decimals

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public freezeManager = makeAddr("freezeManager");
    address public earnerManager = makeAddr("earnerManager");
    address public rateManager = makeAddr("rateManager");
    address public assetCapManager = makeAddr("assetCapManager");
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

        address extensionImpl = address(new MultiMint(address(pyusdx), address(swapFacility)));
        extension = MultiMint(
            UnsafeUpgrades.deployTransparentProxy(
                extensionImpl,
                admin,
                abi.encodeWithSelector(
                    MultiMint.initialize.selector,
                    "MultiMint",
                    "MM",
                    yieldRecipient,
                    admin,
                    assetCapManager,
                    freezeManager,
                    pauser,
                    yieldRecipientManager
                )
            )
        );

        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(extension), 500, 0, address(0));

        pyusdx.setAccountRateBps(address(extension), uint24(500));

        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai", "DAI", 18);
        fourDec = new MockERC20("FourDec", "4DEC", 4);

        vm.startPrank(assetCapManager);
        extension.setAssetCap(address(usdc), 1_000_000e6);
        extension.setAssetCap(address(dai), 1_000_000e18);
        extension.setAssetCap(address(fourDec), 1_000_000e4);
        vm.stopPrank();
    }

    /* ============ Helpers ============ */

    function _wrapPyusdxFor(address to, address recipient, uint256 amount) internal {
        issuerGateway.mint(to, amount);

        vm.startPrank(to);
        IERC20(address(pyusdx)).approve(address(swapFacility), amount);
        swapFacility.swapIn(address(extension), amount, recipient);
        vm.stopPrank();
    }

    function _wrapAssetFor(address user, address asset, uint256 amount) internal {
        MockERC20(asset).mint(user, amount);

        vm.startPrank(user);
        IERC20(asset).approve(address(swapFacility), amount);
        swapFacility.swapInAsset(address(extension), asset, amount, user);
        vm.stopPrank();
    }

    /* ============ Initialization ============ */

    function test_initialize() public view {
        assertEq(extension.name(), "MultiMint");
        assertEq(extension.symbol(), "MM");
        assertEq(extension.decimals(), 6);
        assertEq(extension.yieldRecipient(), yieldRecipient);
        assertEq(extension.pyusdx(), address(pyusdx));
        assertEq(extension.swapFacility(), address(swapFacility));
        assertTrue(extension.hasRole(extension.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(extension.hasRole(extension.ASSET_CAP_MANAGER_ROLE(), assetCapManager));
        assertTrue(extension.hasRole(extension.YIELD_RECIPIENT_MANAGER_ROLE(), yieldRecipientManager));
    }

    /* ============ PYUSDX Wrapping (inherited) ============ */

    function test_wrap_pyusdx() public {
        _wrapPyusdxFor(alice, alice, MINT_AMOUNT);

        assertEq(extension.balanceOf(alice), MINT_AMOUNT);
        assertEq(extension.totalSupply(), MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(address(extension)), MINT_AMOUNT);
    }

    /* ============ Gating ============ */

    function test_wrap_revert_notSwapFacility() public {
        vm.prank(alice);
        vm.expectRevert(IExtension.NotSwapFacility.selector);
        extension.wrap(alice, MINT_AMOUNT);
    }

    function test_unwrap_revert_notSwapFacility() public {
        vm.prank(alice);
        vm.expectRevert(IExtension.NotSwapFacility.selector);
        extension.unwrap(MINT_AMOUNT);
    }

    function test_wrapAsset_revert_notSwapFacility() public {
        vm.prank(alice);
        vm.expectRevert(IExtension.NotSwapFacility.selector);
        extension.wrap(address(usdc), alice, MINT_AMOUNT);
    }

    function test_replaceAsset_revert_notSwapFacility() public {
        vm.prank(alice);
        vm.expectRevert(IExtension.NotSwapFacility.selector);
        extension.replaceAsset(address(usdc), alice, MINT_AMOUNT);
    }

    /* ============ Multi-Asset Wrapping ============ */

    function test_wrap_asset_6decimals() public {
        _wrapAssetFor(alice, address(usdc), 500e6);

        assertEq(extension.balanceOf(alice), 500e6);
        assertEq(extension.totalSupply(), 500e6);
        assertEq(extension.totalAssets(), 500e6);
        assertEq(extension.assetBalanceOf(address(usdc)), 500e6);
        assertEq(usdc.balanceOf(address(extension)), 500e6);
    }

    function test_wrap_asset_18decimals() public {
        _wrapAssetFor(alice, address(dai), 500e18);

        assertEq(extension.balanceOf(alice), 500e6);
        assertEq(extension.totalSupply(), 500e6);
        assertEq(extension.totalAssets(), 500e6);
        assertEq(extension.assetBalanceOf(address(dai)), 500e18);
    }

    function test_wrap_asset_4decimals() public {
        _wrapAssetFor(alice, address(fourDec), 500e4);

        assertEq(extension.balanceOf(alice), 500e6);
        assertEq(extension.totalSupply(), 500e6);
        assertEq(extension.totalAssets(), 500e6);
        assertEq(extension.assetBalanceOf(address(fourDec)), 500e4);
    }

    function test_wrap_asset_revert_invalidAsset_zero() public {
        vm.prank(address(swapFacility));
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InvalidAsset.selector, address(0)));
        extension.wrap(address(0), alice, 100e6);
    }

    function test_wrap_asset_revert_invalidAsset_pyusdx() public {
        vm.prank(address(swapFacility));
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InvalidAsset.selector, address(pyusdx)));
        extension.wrap(address(pyusdx), alice, 100e6);
    }

    function test_wrap_asset_revert_capReached() public {
        vm.prank(assetCapManager);
        extension.setAssetCap(address(usdc), 100e6);

        usdc.mint(alice, 200e6);
        vm.startPrank(alice);
        usdc.approve(address(swapFacility), 200e6);
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.AssetCapReached.selector, address(usdc)));
        swapFacility.swapInAsset(address(extension), address(usdc), 200e6, alice);
        vm.stopPrank();
    }

    function test_wrap_asset_revert_feeOnTransfer() public {
        MockFeeOnTransfer feeToken = new MockFeeOnTransfer("FeeToken", "FEE", 6);

        vm.prank(assetCapManager);
        extension.setAssetCap(address(feeToken), 1_000_000e6);

        feeToken.mint(alice, 200e6);
        vm.startPrank(alice);
        feeToken.approve(address(swapFacility), 200e6);
        // Fee-on-transfer causes the swap facility to receive less than `amount`.
        // The extension's safeTransferFrom then reverts because the facility's balance is insufficient.
        vm.expectRevert();
        swapFacility.swapInAsset(address(extension), address(feeToken), 200e6, alice);
        vm.stopPrank();
    }

    function test_wrap_asset_revert_zeroAmount() public {
        vm.prank(address(swapFacility));
        vm.expectRevert(IExtension.ZeroAmount.selector);
        extension.wrap(address(usdc), alice, 0);
    }

    function test_wrap_asset_revert_frozen() public {
        vm.prank(freezeManager);
        extension.freeze(alice);

        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(swapFacility), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swapInAsset(address(extension), address(usdc), 100e6, alice);
        vm.stopPrank();
    }

    function test_wrap_asset_revert_paused() public {
        vm.prank(pauser);
        extension.pause();

        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(swapFacility), 100e6);
        vm.expectRevert();
        swapFacility.swapInAsset(address(extension), address(usdc), 100e6, alice);
        vm.stopPrank();
    }

    function test_wrap_asset_revert_truncatesToZero() public {
        dai.mint(alice, 1);
        vm.startPrank(alice);
        dai.approve(address(swapFacility), 1);
        vm.expectRevert(IExtension.ZeroAmount.selector);
        swapFacility.swapInAsset(address(extension), address(dai), 1, alice);
        vm.stopPrank();
    }

    /* ============ Unwrap with Backing Constraint ============ */

    function test_unwrap_revert_insufficientPYUSDXBacking() public {
        _wrapPyusdxFor(alice, alice, 60e6);
        _wrapAssetFor(alice, address(usdc), 40e6);

        assertEq(extension.totalSupply(), 100e6);
        assertEq(extension.totalAssets(), 40e6);

        vm.startPrank(alice);
        IERC20(address(extension)).approve(address(swapFacility), 70e6);
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InsufficientPYUSDXBacking.selector, 70e6, 60e6));
        swapFacility.swapOut(address(extension), 70e6, alice);
        vm.stopPrank();
    }

    function test_unwrap_fullPYUSDXBacking() public {
        _wrapPyusdxFor(alice, alice, MINT_AMOUNT);

        vm.startPrank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);
        swapFacility.swapOut(address(extension), MINT_AMOUNT, alice);
        vm.stopPrank();

        assertEq(extension.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
    }

    function test_unwrap_partialWithAltAssets() public {
        _wrapPyusdxFor(alice, alice, 60e6);
        _wrapAssetFor(alice, address(usdc), 40e6);

        vm.startPrank(alice);
        IERC20(address(extension)).approve(address(swapFacility), 60e6);
        swapFacility.swapOut(address(extension), 60e6, alice);
        vm.stopPrank();

        assertEq(extension.balanceOf(alice), 40e6);
        assertEq(pyusdx.balanceOf(alice), 60e6);
    }

    /* ============ Replace Asset with PYUSDX ============ */

    function test_replaceAsset() public {
        _wrapAssetFor(alice, address(usdc), 100e6);

        issuerGateway.mint(bob, 50e6);
        vm.startPrank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), 50e6);
        swapFacility.replaceAsset(address(extension), address(usdc), 50e6, bob);
        vm.stopPrank();

        assertEq(usdc.balanceOf(bob), 50e6);
        assertEq(extension.assetBalanceOf(address(usdc)), 50e6);
        assertEq(pyusdx.balanceOf(address(extension)), 50e6);
        assertEq(extension.totalAssets(), 50e6);
        assertEq(extension.totalSupply(), 100e6);
    }

    function test_replaceAsset_revert_insufficientAssetBacking() public {
        _wrapAssetFor(alice, address(usdc), 50e6);

        issuerGateway.mint(bob, 100e6);
        vm.startPrank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), 100e6);
        vm.expectRevert(
            abi.encodeWithSelector(IMultiMint.InsufficientAssetBacking.selector, address(usdc), 100e6, 50e6)
        );
        swapFacility.replaceAsset(address(extension), address(usdc), 100e6, bob);
        vm.stopPrank();
    }

    function test_replaceAsset_revert_invalidAsset() public {
        vm.prank(address(swapFacility));
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InvalidAsset.selector, address(0)));
        extension.replaceAsset(address(0), bob, 50e6);
    }

    function test_replaceAsset_crossDecimal() public {
        _wrapAssetFor(alice, address(dai), 500e18);

        issuerGateway.mint(bob, 200e6);
        vm.startPrank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), 200e6);
        swapFacility.replaceAsset(address(extension), address(dai), 200e6, bob);
        vm.stopPrank();

        assertEq(dai.balanceOf(bob), 200e18);
        assertEq(extension.assetBalanceOf(address(dai)), 300e18);
        assertEq(extension.totalAssets(), 300e6);
    }

    function test_replaceAsset_revert_paused() public {
        _wrapAssetFor(alice, address(usdc), 100e6);

        issuerGateway.mint(bob, 50e6);
        vm.startPrank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), 50e6);
        vm.stopPrank();

        vm.prank(pauser);
        extension.pause();

        vm.prank(bob);
        vm.expectRevert();
        swapFacility.replaceAsset(address(extension), address(usdc), 50e6, bob);
    }

    function test_replaceAsset_emitsEvent() public {
        _wrapAssetFor(alice, address(usdc), 100e6);

        issuerGateway.mint(bob, 50e6);
        vm.startPrank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), 50e6);
        vm.expectEmit(true, true, false, true, address(extension));
        emit IMultiMint.AssetReplacedWithPYUSDX(address(usdc), 50e6, bob, 50e6);
        swapFacility.replaceAsset(address(extension), address(usdc), 50e6, bob);
        vm.stopPrank();
    }

    /* ============ Asset Cap Management ============ */

    function test_setAssetCap() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 8);

        vm.prank(assetCapManager);
        extension.setAssetCap(address(newToken), 500e8);

        assertEq(extension.assetCap(address(newToken)), 500e8);
        assertEq(extension.assetDecimals(address(newToken)), 8);
        assertTrue(extension.isAllowedAsset(address(newToken)));
    }

    function test_setAssetCap_revert_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        extension.setAssetCap(address(usdc), 999e6);
    }

    function test_setAssetCap_revert_invalidAsset() public {
        vm.prank(assetCapManager);
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InvalidAsset.selector, address(0)));
        extension.setAssetCap(address(0), 100e6);
    }

    function test_setAssetCap_disableAsset() public {
        vm.prank(assetCapManager);
        extension.setAssetCap(address(usdc), 0);

        assertFalse(extension.isAllowedAsset(address(usdc)));

        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(swapFacility), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.AssetCapReached.selector, address(usdc)));
        swapFacility.swapInAsset(address(extension), address(usdc), 100e6, alice);
        vm.stopPrank();
    }

    /* ============ Yield ============ */

    function test_yield_withAltAssets() public {
        _wrapPyusdxFor(alice, alice, 60e6);
        _wrapAssetFor(alice, address(usdc), 40e6);

        assertEq(extension.yield(), 0);
        assertEq(extension.totalSupply(), 100e6);

        vm.warp(block.timestamp + 365 days);

        // Yield is visible before claim.
        assertGt(extension.yield(), 0);

        // After external claimFor, yield() still shows excess (realized but unminted).
        pyusdx.claimFor(address(extension));
        uint256 yieldAfterClaim = extension.yield();
        assertGt(yieldAfterClaim, 0);

        // claimYield recovers it.
        uint256 claimed = extension.claimYield();
        assertEq(claimed, yieldAfterClaim);
        assertEq(extension.balanceOf(yieldRecipient), claimed);
        assertEq(extension.yield(), 0);
        assertEq(extension.totalSupply(), 100e6 + claimed);
    }

    function test_claimYield() public {
        _wrapPyusdxFor(alice, alice, MINT_AMOUNT);

        vm.warp(block.timestamp + 365 days);

        uint256 claimed = extension.claimYield();

        assertGt(claimed, 0);
        assertEq(extension.balanceOf(yieldRecipient), claimed);
        assertEq(extension.totalSupply(), MINT_AMOUNT + claimed);
        assertEq(extension.yield(), 0);
    }

    function test_claimYield_directBypass() public {
        _wrapPyusdxFor(alice, alice, 60e6);
        _wrapAssetFor(alice, address(usdc), 40e6);

        vm.warp(block.timestamp + 365 days);

        // Direct claimFor bypass.
        pyusdx.claimFor(address(extension));
        uint256 excess = pyusdx.balanceOf(address(extension)) - (extension.totalSupply() - extension.totalAssets());
        assertGt(excess, 0);

        // claimYield recovers the excess.
        uint256 claimed = extension.claimYield();
        assertEq(claimed, excess);
        assertEq(extension.balanceOf(yieldRecipient), claimed);
    }

    function test_setYieldRecipient() public {
        _wrapPyusdxFor(alice, alice, MINT_AMOUNT);
        vm.warp(block.timestamp + 365 days);

        address newRecipient = makeAddr("newRecipient");

        vm.prank(yieldRecipientManager);
        extension.setYieldRecipient(newRecipient);

        assertEq(extension.yieldRecipient(), newRecipient);
        assertGt(extension.balanceOf(yieldRecipient), 0);
    }

    /* ============ View Functions ============ */

    function test_isAllowedAsset() public {
        assertTrue(extension.isAllowedAsset(address(usdc)));
        assertFalse(extension.isAllowedAsset(makeAddr("randomToken")));
    }

    function test_isAllowedToWrap() public {
        assertTrue(extension.isAllowedToWrap(address(usdc), 100e6));
        assertFalse(extension.isAllowedToWrap(address(usdc), 0));
    }

    function test_isAllowedToUnwrap() public {
        _wrapPyusdxFor(alice, alice, MINT_AMOUNT);
        assertTrue(extension.isAllowedToUnwrap(500e6));
        assertFalse(extension.isAllowedToUnwrap(0));
    }

    /* ============ Freeze via SwapFacility ============ */

    function test_unwrap_revert_frozen() public {
        _wrapPyusdxFor(alice, alice, MINT_AMOUNT);

        vm.prank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);

        vm.prank(freezeManager);
        extension.freeze(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swapOut(address(extension), MINT_AMOUNT, alice);
    }

    function test_replaceAsset_revert_frozen() public {
        _wrapAssetFor(alice, address(usdc), 100e6);

        issuerGateway.mint(bob, 50e6);

        vm.prank(freezeManager);
        extension.freeze(bob);

        vm.startPrank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), 50e6);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));
        swapFacility.replaceAsset(address(extension), address(usdc), 50e6, bob);
        vm.stopPrank();
    }

    /* ============ Initialization — ZeroAssetCapManager ============ */

    function test_initialize_revert_zeroAssetCapManager() public {
        address impl = address(new MultiMint(address(pyusdx), address(swapFacility)));
        vm.expectRevert(IMultiMint.ZeroAssetCapManager.selector);
        UnsafeUpgrades.deployTransparentProxy(
            impl,
            admin,
            abi.encodeWithSelector(
                MultiMint.initialize.selector,
                "MM",
                "MM",
                yieldRecipient,
                admin,
                address(0),
                freezeManager,
                pauser,
                yieldRecipientManager
            )
        );
    }

    /* ============ InvalidAsset — PYUSDX branch ============ */

    function test_setAssetCap_revert_invalidAsset_pyusdx() public {
        vm.prank(assetCapManager);
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InvalidAsset.selector, address(pyusdx)));
        extension.setAssetCap(address(pyusdx), 100e6);
    }

    function test_replaceAsset_revert_invalidAsset_pyusdx() public {
        vm.prank(address(swapFacility));
        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InvalidAsset.selector, address(pyusdx)));
        extension.replaceAsset(address(pyusdx), bob, 50e6);
    }

    /* ============ Frozen Recipient (caller != recipient) ============ */

    function test_wrap_asset_revert_frozen_recipient() public {
        vm.prank(freezeManager);
        extension.freeze(bob);

        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(swapFacility), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));
        swapFacility.swapInAsset(address(extension), address(usdc), 100e6, bob);
        vm.stopPrank();
    }

    function test_replaceAsset_revert_frozen_recipient() public {
        _wrapAssetFor(alice, address(usdc), 100e6);

        vm.prank(freezeManager);
        extension.freeze(alice);

        issuerGateway.mint(bob, 50e6);
        vm.startPrank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), 50e6);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.replaceAsset(address(extension), address(usdc), 50e6, alice);
        vm.stopPrank();
    }

    /* ============ Pausable — Unwrap ============ */

    function test_unwrap_revert_paused() public {
        _wrapPyusdxFor(alice, alice, MINT_AMOUNT);

        vm.prank(pauser);
        extension.pause();

        vm.startPrank(alice);
        IERC20(address(extension)).approve(address(swapFacility), MINT_AMOUNT);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        swapFacility.swapOut(address(extension), MINT_AMOUNT, alice);
        vm.stopPrank();
    }

    /* ============ Zero-Amount / Zero-Recipient ============ */

    function test_replaceAsset_revert_zeroAmount() public {
        vm.prank(address(swapFacility));
        vm.expectRevert(IExtension.ZeroAmount.selector);
        extension.replaceAsset(address(usdc), bob, 0);
    }

    function test_wrap_asset_revert_zeroRecipient() public {
        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(swapFacility), 100e6);
        vm.expectRevert(IExtension.ZeroAccount.selector);
        swapFacility.swapInAsset(address(extension), address(usdc), 100e6, address(0));
        vm.stopPrank();
    }

    /* ============ Event Emission ============ */

    function test_wrap_asset_emitsEvent() public {
        dai.mint(alice, 500e18);
        vm.startPrank(alice);
        dai.approve(address(swapFacility), 500e18);
        vm.expectEmit(true, true, false, true, address(extension));
        emit IMultiMint.AssetWrapped(address(dai), 500e18, alice, 500e6);
        swapFacility.swapInAsset(address(extension), address(dai), 500e18, alice);
        vm.stopPrank();
    }

    function test_setAssetCap_emitsEvent() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 8);
        vm.prank(assetCapManager);
        vm.expectEmit(true, false, false, true, address(extension));
        emit IMultiMint.AssetCapSet(address(newToken), 500e8);
        extension.setAssetCap(address(newToken), 500e8);
    }

    /* ============ isAllowedToReplaceAssetWithPYUSDX ============ */

    function test_isAllowedToReplaceAssetWithPYUSDX() public {
        _wrapAssetFor(alice, address(usdc), 100e6);

        assertTrue(extension.isAllowedToReplaceAssetWithPYUSDX(address(usdc), 50e6));
        assertTrue(extension.isAllowedToReplaceAssetWithPYUSDX(address(usdc), 100e6));
    }

    function test_isAllowedToReplaceAssetWithPYUSDX_zeroOrExcessive() public {
        _wrapAssetFor(alice, address(usdc), 100e6);

        assertFalse(extension.isAllowedToReplaceAssetWithPYUSDX(address(usdc), 0));
        assertFalse(extension.isAllowedToReplaceAssetWithPYUSDX(address(usdc), 101e6));
    }

    /* ============ InsufficientAssetReceived ============ */

    function test_wrap_asset_revert_insufficientAssetReceived() public {
        MockFeeOnTransfer feeToken = new MockFeeOnTransfer("FeeToken", "FEE", 6);

        vm.prank(assetCapManager);
        extension.setAssetCap(address(feeToken), 1_000_000e6);

        // Pre-fund swap facility so safeTransferFrom (L238) succeeds despite prior fee loss.
        feeToken.mint(address(swapFacility), 100e6);

        feeToken.mint(alice, 200e6);
        vm.startPrank(alice);
        feeToken.approve(address(swapFacility), 200e6);
        vm.expectRevert(
            abi.encodeWithSelector(IMultiMint.InsufficientAssetReceived.selector, address(feeToken), 200e6, 198e6)
        );
        swapFacility.swapInAsset(address(extension), address(feeToken), 200e6, alice);
        vm.stopPrank();
    }
}
