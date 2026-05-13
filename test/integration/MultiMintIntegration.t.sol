// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { IMultiMint } from "../../src/platform/projects/interfaces/IMultiMint.sol";

import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

contract MultiMintIntegrationTests is IntegrationForkTest {
    MultiMint public multiMint;

    uint256 public constant AMOUNT = 1000e6;

    function setUp() public override {
        super.setUp();

        // Deploy MultiMint through factory
        IExtensionFactory.MultiMintParams memory mmParams = IExtensionFactory.MultiMintParams({
            name: "MultiMint",
            symbol: "MM",
            yieldRecipient: yieldRecipient,
            admin: admin,
            assetCapManager: assetCapManager,
            freezeManager: freezeManager,
            pauser: pauser,
            yieldRecipientManager: yieldRecipientManager,
            versionManager: versionManager
        });

        vm.prank(admin);
        (address multiMintProxy, ) = factory.deployMultiMint(string("mm-integration"), mmParams);
        multiMint = MultiMint(multiMintProxy);

        // Register the deployed MultiMint so SwapFacility recognises it
        vm.prank(factoryManager);
        factory.setExtensionType(multiMintProxy, IExtensionFactory.ExtensionType.MULTI_MINT);

        // Enable PYUSDX earning for MultiMint (claimRecipient = address(0) means yield stays on contract)
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(multiMint), 500, 0, address(0));

        // Set USDC asset cap to max
        vm.prank(assetCapManager);
        multiMint.setAssetCap(address(USDC), type(uint256).max);

        // Set PYUSD asset cap to max
        vm.prank(assetCapManager);
        multiMint.setAssetCap(address(PYUSD), type(uint256).max);
    }

    /* ============ Helpers ============ */

    /// @dev Deals USDC, approves swap facility, swaps USDC into MultiMint for user
    function _wrapUSDCFor(address user, uint256 amount) internal {
        _dealUSDC(user, amount);

        vm.prank(user);
        IERC20(address(USDC)).approve(address(swapFacility), amount);

        vm.prank(user);
        swapFacility.swap(address(USDC), address(multiMint), amount, user);
    }

    /// @dev Deals PYUSD, approves swap facility, swaps PYUSD into MultiMint for user
    function _wrapPYUSDFor(address user, uint256 amount) internal {
        _dealPYUSD(user, amount);

        vm.prank(user);
        IERC20(address(PYUSD)).approve(address(swapFacility), amount);

        vm.prank(user);
        swapFacility.swap(address(PYUSD), address(multiMint), amount, user);
    }

    /// @dev Mints PYUSDX, approves swap facility, swaps PYUSDX into MultiMint for user
    function _wrapPYUSDXFor(address user, uint256 amount) internal {
        _mintPYUSDX(user, amount);

        vm.prank(user);
        IERC20(address(pyusdx)).approve(address(swapFacility), amount);

        vm.prank(user);
        swapFacility.swapIn(address(multiMint), amount, user);
    }

    /* ============ setAssetCap ============ */

    function testIntegration_setAssetCap_disableBlocksWrap() public {
        // Disable USDC
        vm.prank(assetCapManager);
        multiMint.setAssetCap(address(USDC), 0);

        assertFalse(multiMint.isAllowedAsset(address(USDC)));

        // Attempt to wrap USDC — should fail
        _dealUSDC(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.InvalidSwapPath.selector, address(USDC), address(multiMint))
        );

        vm.prank(alice);
        swapFacility.swap(address(USDC), address(multiMint), AMOUNT, alice);
    }

    /* ============ wrapAsset ============ */

    function testIntegration_wrapAsset() public {
        _wrapUSDCFor(alice, AMOUNT);

        assertEq(multiMint.balanceOf(alice), AMOUNT);
        assertEq(multiMint.totalSupply(), AMOUNT);
        assertEq(multiMint.assetBalanceOf(address(USDC)), AMOUNT);
        assertEq(multiMint.totalAssets(), AMOUNT);
        assertEq(USDC.balanceOf(address(multiMint)), AMOUNT);
        assertEq(pyusdx.balanceOf(address(multiMint)), 0);
    }

    function testIntegration_wrapAsset_revert_capReached() public {
        // Set tight cap
        vm.prank(assetCapManager);
        multiMint.setAssetCap(address(USDC), 1500e6);

        // First wrap succeeds (under cap)
        _wrapUSDCFor(alice, AMOUNT);

        // Second wrap exceeds cap
        _dealUSDC(bob, 600e6);

        vm.prank(bob);
        IERC20(address(USDC)).approve(address(swapFacility), 600e6);

        vm.expectRevert(abi.encodeWithSelector(IMultiMint.AssetCapReached.selector, address(USDC)));

        vm.prank(bob);
        swapFacility.swap(address(USDC), address(multiMint), 600e6, bob);
    }

    /* ============ replaceAsset ============ */

    function testIntegration_replaceAsset() public {
        // Bob wraps USDC — MM holds 1000e6 USDC
        _wrapUSDCFor(bob, AMOUNT);

        // Alice mints PYUSDX to deposit
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.replaceAsset(address(USDC), address(pyusdx), address(multiMint), AMOUNT, alice);

        assertEq(USDC.balanceOf(alice), AMOUNT);
        assertEq(multiMint.assetBalanceOf(address(USDC)), 0);
        assertEq(USDC.balanceOf(address(multiMint)), 0);
        assertEq(multiMint.totalAssets(), 0);
        assertEq(pyusdx.balanceOf(address(multiMint)), AMOUNT);
        assertEq(multiMint.totalSupply(), AMOUNT);
    }

    function testIntegration_replaceAsset_whitelistedCaller() public {
        _wrapUSDCFor(bob, AMOUNT);

        vm.prank(assetCapManager);
        multiMint.setReplaceAssetWhitelistCaller(alice, true);

        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.replaceAsset(address(USDC), address(pyusdx), address(multiMint), AMOUNT, alice);

        assertEq(USDC.balanceOf(alice), AMOUNT);
    }

    function testIntegration_replaceAsset_revert_insufficientAssetBacking() public {
        // Only 500e6 USDC deposited
        _wrapUSDCFor(alice, 500e6);

        // Bob tries to replace 1000e6 worth
        _mintPYUSDX(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IMultiMint.InsufficientAssetBacking.selector, address(USDC), AMOUNT, 500e6)
        );

        vm.prank(bob);
        swapFacility.replaceAsset(address(USDC), address(pyusdx), address(multiMint), AMOUNT, bob);
    }

    /* ============ unwrap ============ */

    function testIntegration_unwrap_revert_insufficientPYUSDXBacking() public {
        // MM holds USDC only — pyusdxBacking = 0
        _wrapUSDCFor(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(multiMint)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InsufficientPYUSDXBacking.selector, AMOUNT, 0));

        vm.prank(alice);
        swapFacility.swapOut(address(multiMint), AMOUNT, alice);
    }

    function testIntegration_unwrap_withMixedBacking() public {
        // 500 USDC + 500 PYUSDX backing
        _wrapUSDCFor(alice, 500e6);
        _wrapPYUSDXFor(alice, 500e6);

        // Alice holds 1000e6 MM tokens
        assertEq(multiMint.balanceOf(alice), 1000e6);

        // Unwrap 500 — succeeds (backed by PYUSDX)
        vm.prank(alice);
        IERC20(address(multiMint)).approve(address(swapFacility), 500e6);

        vm.prank(alice);
        swapFacility.swapOut(address(multiMint), 500e6, alice);

        assertEq(pyusdx.balanceOf(alice), 500e6);
        assertEq(multiMint.balanceOf(alice), 500e6);

        // Trying to unwrap remaining 500 fails — no more PYUSDX backing
        vm.prank(alice);
        IERC20(address(multiMint)).approve(address(swapFacility), 500e6);

        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InsufficientPYUSDXBacking.selector, 500e6, 0));

        vm.prank(alice);
        swapFacility.swapOut(address(multiMint), 500e6, alice);
    }

    /* ============ yield ============ */

    function testIntegration_claimYield_mixedBacking() public {
        // 500 USDC + 500 PYUSDX backing
        _wrapUSDCFor(alice, 500e6);
        _wrapPYUSDXFor(bob, 500e6);

        // totalSupply = 1000, PYUSDX balance = 500, totalAssets = 500
        assertEq(multiMint.totalSupply(), 1000e6);
        assertEq(multiMint.totalAssets(), 500e6);

        vm.warp(block.timestamp + 365 days);

        assertGt(multiMint.yield(), 0);

        vm.prank(yieldRecipientManager);
        uint256 claimed = multiMint.claimYield();

        assertGt(claimed, 0);
        assertEq(multiMint.yield(), 0);
        assertEq(multiMint.balanceOf(yieldRecipient), claimed);
        assertEq(pyusdx.balanceOf(address(multiMint)), 500e6 + claimed);
    }

    function testIntegration_yield_excessAccountsForTotalAssets() public {
        // totalAssets = 500, totalSupply = 500
        _wrapUSDCFor(alice, 500e6);
        // totalAssets = 500, totalSupply = 1000, pyusdxBalance = 500
        _wrapPYUSDXFor(bob, 500e6);

        // Excess = pyusdxBalance(500) - (totalSupply(1000) - totalAssets(500)) = 0
        assertEq(multiMint.yield(), 0);

        // Direct transfer 200e6 PYUSDX to multiMint (bypass swap, creates excess)
        _mintPYUSDX(carol, 200e6);

        vm.prank(carol);
        IERC20(address(pyusdx)).transfer(address(multiMint), 200e6);

        // Excess = 700 - 500 = 200
        assertEq(multiMint.yield(), 200e6);

        vm.prank(yieldRecipientManager);
        uint256 claimed = multiMint.claimYield();

        assertGe(claimed, 200e6);
        assertEq(multiMint.balanceOf(yieldRecipient), claimed);
        assertEq(multiMint.yield(), 0);
    }

    /* ============ complex scenarios ============ */

    function testIntegration_assetOnlyBacking_noYield() public {
        // MM holds only USDC, 0 PYUSDX
        _wrapUSDCFor(alice, AMOUNT);

        assertEq(pyusdx.balanceOf(address(multiMint)), 0);

        vm.warp(block.timestamp + 365 days);

        assertEq(multiMint.yield(), 0);

        vm.prank(yieldRecipientManager);
        uint256 claimed = multiMint.claimYield();

        assertEq(claimed, 0);
    }

    function testIntegration_replaceAsset_increasesYieldBase() public {
        // All USDC backing — no yield
        _wrapUSDCFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        assertEq(multiMint.yield(), 0);

        // Replace USDC with PYUSDX
        _mintPYUSDX(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.replaceAsset(address(USDC), address(pyusdx), address(multiMint), AMOUNT, bob);

        // Now MM holds AMOUNT PYUSDX, totalAssets = 0
        assertEq(multiMint.totalAssets(), 0);

        vm.warp(block.timestamp + 365 days);

        assertGt(multiMint.yield(), 0);

        vm.prank(yieldRecipientManager);
        uint256 claimed = multiMint.claimYield();

        assertGt(claimed, 0);
    }

    function testIntegration_unwrap_blockedThenEnabledByPYUSDXWrap() public {
        // All USDC — unwrap blocked
        _wrapUSDCFor(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(multiMint)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IMultiMint.InsufficientPYUSDXBacking.selector, AMOUNT, 0));

        vm.prank(alice);
        swapFacility.swapOut(address(multiMint), AMOUNT, alice);

        // Bob adds PYUSDX backing
        _wrapPYUSDXFor(bob, AMOUNT);

        // Now alice can unwrap
        vm.prank(alice);
        swapFacility.swapOut(address(multiMint), AMOUNT, alice);

        assertEq(pyusdx.balanceOf(alice), AMOUNT);
        assertEq(multiMint.balanceOf(alice), 0);
    }

    function testIntegration_multipleAssets_independentTracking() public {
        _wrapUSDCFor(alice, 600e6);
        _wrapPYUSDFor(bob, 400e6);

        assertEq(multiMint.assetBalanceOf(address(USDC)), 600e6);
        assertEq(multiMint.assetBalanceOf(address(PYUSD)), 400e6);
        assertEq(multiMint.totalAssets(), 1000e6);
        assertEq(multiMint.totalSupply(), 1000e6);
        assertEq(USDC.balanceOf(address(multiMint)), 600e6);
        assertEq(PYUSD.balanceOf(address(multiMint)), 400e6);

        // Set tight cap on USDC
        vm.prank(assetCapManager);
        multiMint.setAssetCap(address(USDC), 600e6);

        assertFalse(multiMint.isAllowedToWrap(address(USDC), 1));
        assertTrue(multiMint.isAllowedToWrap(address(PYUSD), 100e6));
    }

    function testIntegration_fullLifecycle() public {
        // 1. Alice wraps USDC, Bob wraps PYUSDX
        _wrapUSDCFor(alice, 500e6);
        _wrapPYUSDXFor(bob, 500e6);

        assertEq(multiMint.totalSupply(), 1000e6);
        assertEq(multiMint.totalAssets(), 500e6);

        // 2. Yield accrues on 500 PYUSDX
        vm.warp(block.timestamp + 365 days);

        vm.prank(yieldRecipientManager);
        uint256 claimed = multiMint.claimYield();

        assertGt(claimed, 0);

        // 3. Replace USDC with PYUSDX
        _mintPYUSDX(carol, 500e6);

        vm.prank(carol);
        IERC20(address(pyusdx)).approve(address(swapFacility), 500e6);

        vm.prank(carol);
        swapFacility.replaceAsset(address(USDC), address(pyusdx), address(multiMint), 500e6, carol);

        assertEq(USDC.balanceOf(carol), 500e6);
        assertEq(multiMint.totalAssets(), 0);

        // 4. Alice unwraps her 500e6
        vm.prank(alice);
        IERC20(address(multiMint)).approve(address(swapFacility), 500e6);

        vm.prank(alice);
        swapFacility.swapOut(address(multiMint), 500e6, alice);

        assertEq(pyusdx.balanceOf(alice), 500e6);

        // 5. Bob unwraps his 500e6
        vm.prank(bob);
        IERC20(address(multiMint)).approve(address(swapFacility), 500e6);

        vm.prank(bob);
        swapFacility.swapOut(address(multiMint), 500e6, bob);

        assertEq(pyusdx.balanceOf(bob), 500e6);

        // Only yield tokens remain (held by yield recipient)
        assertEq(multiMint.totalSupply(), claimed);
        assertEq(pyusdx.balanceOf(address(multiMint)), claimed);
    }

    function testIntegration_claimYield_afterPartialReplacement() public {
        // Mixed backing
        _wrapUSDCFor(alice, 500e6);
        _wrapPYUSDXFor(bob, 500e6);

        vm.warp(block.timestamp + 365 days);

        vm.prank(yieldRecipientManager);
        uint256 yieldFirstPeriod = multiMint.claimYield();

        assertGt(yieldFirstPeriod, 0);

        // Replace 500 USDC with PYUSDX — doubles earning base
        _mintPYUSDX(carol, 500e6);

        vm.prank(carol);
        IERC20(address(pyusdx)).approve(address(swapFacility), 500e6);

        vm.prank(carol);
        swapFacility.replaceAsset(address(USDC), address(pyusdx), address(multiMint), 500e6, carol);

        vm.warp(block.timestamp + 365 days);

        vm.prank(yieldRecipientManager);
        uint256 yieldSecondPeriod = multiMint.claimYield();

        assertGt(yieldSecondPeriod, yieldFirstPeriod);
        assertEq(multiMint.yield(), 0);
    }

    function testIntegration_freeze_recipientBlocksWrapAsset() public {
        vm.prank(freezeManager);
        multiMint.freeze(bob);

        _dealUSDC(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        swapFacility.swap(address(USDC), address(multiMint), AMOUNT, bob);
    }

    function testIntegration_claimYield_afterExtensionRevoked() public {
        _wrapPYUSDXFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        // Revoke extension
        vm.prank(factoryManager);
        factory.setExtensionType(address(multiMint), IExtensionFactory.ExtensionType.NONE);

        assertFalse(swapFacility.isApprovedExtension(address(multiMint)));

        // claimYield still works (bypasses swap facility)
        vm.prank(yieldRecipientManager);
        uint256 claimed = multiMint.claimYield();

        assertGt(claimed, 0);

        // Asset wraps are blocked
        _dealUSDC(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.InvalidSwapPath.selector, address(USDC), address(multiMint))
        );

        vm.prank(bob);
        swapFacility.swap(address(USDC), address(multiMint), AMOUNT, bob);
    }
}
