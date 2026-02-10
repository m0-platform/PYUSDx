// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/m-extensions/src/components/freezable/IFreezable.sol";
import { IForcedTransferable } from "../../lib/m-extensions/src/components/forcedTransferable/IForcedTransferable.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";
import { AccessControlUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { UIntMath } from "../../lib/m-extensions/lib/common/src/libs/UIntMath.sol";
import { IndexingMath } from "../../lib/m-extensions/lib/common/src/libs/IndexingMath.sol";
import { VmSafe } from "../../lib/m-extensions/lib/forge-std/src/Vm.sol";

import { UnsafeUpgrades } from "../../lib/m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";
import { MinterGatewayMock } from "../mock/MinterGatewayMock.sol";

contract PYUSDXUnitTests is PYUSDXBaseUnitTest {
    event Transfer(address indexed from, address indexed to, uint256 value);

    uint256 public constant MINT_AMOUNT = 100e6; // 100 PYUSDX (6 decimals)
    uint256 public constant BURN_AMOUNT = 50e6; // 50 PYUSDX (6 decimals)
    uint256 public constant TRANSFER_AMOUNT = 30e6; // 30 PYUSDX (6 decimals)

    /* ============ constructor ============ */

    function test_constructor_revertIfZeroMinterGateway() public {
        vm.expectRevert(IPYUSDX.ZeroMinterGateway.selector);

        new PYUSDXHarness(address(0));
    }

    function test_constructor() public {
        address expectedMinterGateway = makeAddr("expectedMinterGateway");

        PYUSDXHarness newPyusdx = new PYUSDXHarness(expectedMinterGateway);

        assertEq(address(newPyusdx.minterGateway()), expectedMinterGateway);
    }

    /* ============ initialize ============ */

    function test_initialize_revertIfZeroAdmin() public {
        address implementation = address(new PYUSDXHarness(makeAddr("MinterGateway")));
        PYUSDXHarness newPyusdx = PYUSDXHarness(UnsafeUpgrades.deployTransparentProxy(implementation, admin, ""));

        vm.expectRevert(IPYUSDX.ZeroAdmin.selector);

        newPyusdx.initialize(
            "PayPal USD Yield",
            "PYUSDX",
            address(0),
            pauser,
            freezeManager,
            forcedTransferManager,
            earnerManager,
            makeAddr("rateManager")
        );
    }

    function test_initialize_revertIfZeroEarnerManager() public {
        address implementation = address(new PYUSDXHarness(makeAddr("MinterGateway")));
        PYUSDXHarness newPyusdx = PYUSDXHarness(UnsafeUpgrades.deployTransparentProxy(implementation, admin, ""));

        vm.expectRevert(IPYUSDX.ZeroEarnerManager.selector);

        newPyusdx.initialize(
            "PayPal USD Yield",
            "PYUSDX",
            admin,
            pauser,
            freezeManager,
            forcedTransferManager,
            address(0),
            makeAddr("rateManager")
        );
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert();

        pyusdx.initialize(
            "PayPal USD Yield",
            "PYUSDX",
            admin,
            pauser,
            freezeManager,
            forcedTransferManager,
            earnerManager,
            rateManager
        );
    }

    function test_initialize() public {
        assertEq(pyusdx.name(), "PayPal USD Yield");
        assertEq(pyusdx.symbol(), "PYUSDX");
        assertEq(pyusdx.decimals(), 6);
        assertTrue(pyusdx.hasRole(pyusdx.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(pyusdx.hasRole(pyusdx.MINTER_ROLE(), address(minterGateway)));
        assertTrue(pyusdx.hasRole(pyusdx.EARNER_MANAGER_ROLE(), earnerManager));
    }

    /* ============ mint ============ */

    function test_mint_revertIfCallerNotMinterGateway() public {
        vm.expectRevert(IPYUSDX.NotMinterGateway.selector);

        vm.prank(alice);
        pyusdx.mint(bob, MINT_AMOUNT);
    }

    function test_mint_revertIfPaused() public {
        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        minterGateway.mint(alice, MINT_AMOUNT);
    }

    function test_mint_revertIfZeroAmount() public {
        vm.expectRevert(IPYUSDX.ZeroAmount.selector);

        minterGateway.mint(alice, 0);
    }

    function test_mint_revertIfZeroAccount() public {
        vm.expectRevert(IPYUSDX.ZeroAccount.selector);

        minterGateway.mint(address(0), MINT_AMOUNT);
    }

    function test_mint_revertIfAccountFrozen() public {
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        minterGateway.mint(alice, MINT_AMOUNT);
    }

    function test_mint_nonEarningAccount() public {
        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        assertFalse(pyusdx.isEarning(alice));

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, MINT_AMOUNT);

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + MINT_AMOUNT);
    }

    function test_mint_earningAccount() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        assertTrue(pyusdx.isEarning(alice));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, MINT_AMOUNT);

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + MINT_AMOUNT);

        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipal);
    }

    function testFuzz_mint_earningAccount(uint256 amount, uint128 index) public {
        uint256 boundedAmount = bound(amount, 1, uint256(type(uint112).max) - 1);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        pyusdx.setAccountLastIndex(alice, boundedIndex);

        minterGateway.mint(alice, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + boundedAmount);

        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, boundedIndex);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
    }

    function test_mint_earningAccount_withIndexGrowth() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        vm.warp(365 days);

        uint128 indexAfterWarp = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfterWarp > indexBefore);

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 indexAfterMint = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfterMint >= indexAfterWarp);
    }

    function test_mint_maxSafeAmount() public {
        // The maximum safe amount is limited by uint240 totalSupply
        uint240 maxSafeAmount = type(uint240).max;

        minterGateway.mint(alice, uint256(maxSafeAmount));

        assertEq(pyusdx.balanceOf(alice), uint256(maxSafeAmount));
        assertEq(pyusdx.totalSupply(), uint256(maxSafeAmount));
    }

    function test_mint_revertIfOverflowsTotalSupply() public {
        // Mint to the maximum first
        minterGateway.mint(alice, uint256(type(uint240).max));

        // Now try to mint more - should revert
        vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        minterGateway.mint(bob, 1);
    }

    function test_mint_overflow_edgeCase() public {
        // Test the boundary where totalSupply is at maximum
        uint240 maxSafeAmount = type(uint240).max;

        minterGateway.mint(alice, uint256(maxSafeAmount));

        assertEq(pyusdx.totalSupply(), uint256(maxSafeAmount));

        // Trying to mint even 1 more should revert
        vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        minterGateway.mint(alice, 1);
    }

    function test_mint_nonEarningToEarning_transition() public {
        // Mint to alice as non-earning
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Set alice as earning
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        assertTrue(pyusdx.isEarning(alice));

        // Mint again - should now go to earning balance
        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);

        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
    }

    function test_mint_earningToNonEarning_transition() public {
        // Set alice as earning first
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Mint to alice as earning
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);
        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexBefore);

        assertEq(principalBefore, expectedPrincipal);

        // Set alice as non-earning
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, address(0), 0, address(0));

        assertFalse(pyusdx.isEarning(alice));

        // Principal should be reset to 0 when transitioning to non-earning
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Mint again - should now go to non-earning balance
        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
    }

    /* ============ burn ============ */

    function test_burn_revertIfCallerNotMinterGateway() public {
        vm.expectRevert(IPYUSDX.NotMinterGateway.selector);

        vm.prank(alice);
        pyusdx.burn(bob, BURN_AMOUNT);
    }

    function test_burn_revertIfPaused() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        minterGateway.burn(alice, BURN_AMOUNT);
    }

    function test_burn_revertIfZeroAmount() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.expectRevert(IPYUSDX.ZeroAmount.selector);

        minterGateway.burn(alice, 0);
    }

    function test_burn_revertIfAccountFrozen() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        minterGateway.burn(alice, BURN_AMOUNT);
    }

    function test_burn_revertIfInsufficientBalance() public {
        minterGateway.mint(alice, 100e6);

        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, 100e6, 101e6));

        minterGateway.burn(alice, 101e6);
    }

    function test_burn_nonEarningAccount() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        assertFalse(pyusdx.isEarning(alice));

        vm.expectEmit();
        emit IERC20.Transfer(alice, address(0), BURN_AMOUNT);

        minterGateway.burn(alice, BURN_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore - BURN_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore - BURN_AMOUNT);
    }

    function test_burn_earningAccount() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        assertTrue(pyusdx.isEarning(alice));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        vm.expectEmit();
        emit IERC20.Transfer(alice, address(0), BURN_AMOUNT);

        minterGateway.burn(alice, BURN_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore - BURN_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore - BURN_AMOUNT);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexBefore);
        uint112 expectedPrincipalAfter = principalBefore - expectedPrincipalSubtracted;
        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
    }

    function testFuzz_burn_earningAccount(uint256 amount, uint128 index) public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        uint256 boundedMintAmount = bound(amount, 1, uint256(type(uint112).max) - 1);
        uint256 boundedBurnAmount = bound(amount, 1, boundedMintAmount);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));

        pyusdx.setAccountLastIndex(alice, boundedIndex);

        minterGateway.mint(alice, boundedMintAmount);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, boundedBurnAmount);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(boundedBurnAmount, boundedIndex);
        uint112 expectedPrincipalAfter = principalBefore -
            UIntMath.min112(principalBefore, expectedPrincipalSubtracted);

        assertEq(pyusdx.earningPrincipalOf(alice), expectedPrincipalAfter);
    }

    function test_burn_earningAccount_withIndexGrowth() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        vm.warp(365 days);

        uint128 indexAfterWarp = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfterWarp > indexBefore);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        uint128 indexAfterBurn = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfterBurn >= indexAfterWarp);

        // Principal was subtracted using indexAfterWarp (before updateIndex)
        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexAfterWarp);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipalSubtracted);
    }

    function test_burn_fullBalance() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 fullBalance = pyusdx.balanceOf(alice);

        minterGateway.burn(alice, fullBalance);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.totalSupply(), 0);
    }

    function test_burn_fullBalance_earning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 fullBalance = pyusdx.balanceOf(alice);

        minterGateway.burn(alice, fullBalance);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
    }

    function test_burn_nonEarningToEarning_transition() public {
        // Mint as non-earning
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Set alice as earning
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        assertTrue(pyusdx.isEarning(alice));

        // Mint again as earning
        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);

        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);

        // Now burn - should burn from earning balance (entire balance is earning now)
        uint112 principalBeforeBurn = pyusdx.earningPrincipalOf(alice);
        uint128 indexBeforeBurn = pyusdx.currentAccountIndex(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexBeforeBurn);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBeforeBurn - expectedPrincipalSubtracted);
    }

    function test_burn_earningAccount_principalUnderflowProtection() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Manually set earning principal to a low value to test underflow protection
        pyusdx.setEarningPrincipal(alice, 100);

        // Burn amount that would require more principal than available
        // This should NOT revert - instead min112 caps the subtraction
        minterGateway.burn(alice, BURN_AMOUNT);

        // Principal should be capped at 0, not underflow
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Balance should still decrease
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT - BURN_AMOUNT);
    }

    /* ============ transfer ============ */

    function test_transfer_revertIfPaused() public {
        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_transfer_revertIfFrozen_sender() public {
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_transfer_revertIfFrozen_recipient() public {
        vm.prank(freezeManager);
        pyusdx.freeze(bob);

        assertTrue(pyusdx.isFrozen(bob));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);
    }

    function test_transfer_revertIfFrozen_msgSender() public {
        // Approve carol to spend alice's tokens
        vm.prank(alice);
        pyusdx.approve(carol, TRANSFER_AMOUNT);

        vm.prank(freezeManager);
        pyusdx.freeze(carol);

        assertTrue(pyusdx.isFrozen(carol));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, carol));

        // Carol is the msg.sender in transferFrom
        vm.prank(carol);
        pyusdx.transferFrom(alice, bob, TRANSFER_AMOUNT);
    }

    function test_transfer_insufficientBalance() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, MINT_AMOUNT, MINT_AMOUNT + 1)
        );

        vm.prank(alice);
        pyusdx.transfer(bob, MINT_AMOUNT + 1);
    }

    function test_transfer_toZeroAddress() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        vm.expectRevert(IPYUSDX.ZeroAccount.selector);

        vm.prank(alice);
        pyusdx.transfer(address(0), TRANSFER_AMOUNT);
    }

    function test_transfer_nonEarningToNonEarning() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + TRANSFER_AMOUNT);

        // Unchanged totals (in-kind transfer)
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function testFuzz_transfer_nonEarningToNonEarning(uint256 amount) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max - 1);

        minterGateway.mint(alice, boundedAmount);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - boundedAmount);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + boundedAmount);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_transfer_earningToEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + TRANSFER_AMOUNT);

        // Principal transferred (rounded up)
        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
    }

    function test_transfer_earningToEarning_withIndexGrowth() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(bob, uint24(500));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        vm.warp(365 days);

        uint128 indexAfterWarp = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfterWarp > indexBefore);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Subtraction from sender uses roundUp, addition to recipient uses roundDown
        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, indexAfterWarp);
        uint112 expectedPrincipalAdded = _getExpectedPrincipal(TRANSFER_AMOUNT, indexAfterWarp);
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipalAdded);
    }

    function testFuzz_transfer_earningToEarning(uint256 amount, uint128 index) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max - 1);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        pyusdx.setAccountLastIndex(alice, boundedIndex);
        pyusdx.setAccountLastIndex(bob, boundedIndex);

        minterGateway.mint(alice, boundedAmount);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        uint112 expectedPrincipal = UIntMath.min112(
            alicePrincipalBefore,
            _getExpectedPrincipalRoundedUp(boundedAmount, boundedIndex)
        );

        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
    }

    function test_transfer_nonEarningToEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint128 indexBefore = pyusdx.currentAccountIndex(bob);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // totalSupply unchanged (transfer)
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);

        // Earning principal increased (rounded down - protocol-favoring)
        uint112 expectedPrincipal = _getExpectedPrincipal(TRANSFER_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(bob), expectedPrincipal);
    }

    function test_transfer_earningToNonEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Principal subtracted (rounded up - protocol-favoring)
        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, indexBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipalSubtracted);

        // totalSupply unchanged (transfer)
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function testFuzz_transfer_earningToNonEarning(uint256 amount, uint128 index) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max - 1);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        pyusdx.setAccountLastIndex(alice, boundedIndex);

        minterGateway.mint(alice, boundedAmount);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        uint112 expectedPrincipalSubtracted = UIntMath.min112(
            alicePrincipalBefore,
            _getExpectedPrincipalRoundedUp(boundedAmount, boundedIndex)
        );

        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_transfer_toSelf() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        vm.expectEmit();
        emit IERC20.Transfer(alice, alice, TRANSFER_AMOUNT);

        vm.prank(alice);
        pyusdx.transfer(alice, TRANSFER_AMOUNT);

        // Balance should be unchanged (subtracting and adding same amount)
        assertEq(pyusdx.balanceOf(alice), balanceBefore);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_transfer_zeroAmount() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, 0);

        vm.prank(alice);
        pyusdx.transfer(bob, 0);

        // Balances unchanged
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_transfer_fullBalance() public {
        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 fullBalance = pyusdx.balanceOf(alice);

        vm.prank(alice);
        pyusdx.transfer(bob, fullBalance);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(bob), fullBalance);
    }

    function test_transfer_fullBalance_earningToEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 fullBalance = pyusdx.balanceOf(alice);
        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);

        vm.prank(alice);
        pyusdx.transfer(bob, fullBalance);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(bob), fullBalance);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // All principal transferred to bob
        assertEq(pyusdx.earningPrincipalOf(bob), alicePrincipalBefore);
    }

    function test_transfer_earningToNonEarning_indexGrowth() public {
        vm.warp(365 days);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(1000));

        minterGateway.mint(alice, MINT_AMOUNT);

        uint128 index = pyusdx.currentAccountIndex(alice);
        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        uint112 principalSubtracted = alicePrincipalBefore - pyusdx.earningPrincipalOf(alice);

        // Calculate both rounded down and up
        uint112 principalRoundedDown = _getExpectedPrincipal(TRANSFER_AMOUNT, index);
        uint112 principalRoundedUp = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, index);

        // Verify we used rounded up (protocol-favoring)
        assertEq(principalSubtracted, principalRoundedUp);
        assertTrue(principalSubtracted >= principalRoundedDown);
    }

    function testFuzz_transfer_nonEarningToEarning(uint256 amount, uint128 index) public {
        uint256 boundedAmount = bound(amount, 1, type(uint112).max - 1);
        uint128 boundedIndex = uint128(bound(index, PRECISION, type(uint128).max));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        pyusdx.setAccountLastIndex(bob, boundedIndex);

        minterGateway.mint(alice, boundedAmount);

        uint256 totalSupplyBefore = pyusdx.totalSupply();

        vm.prank(alice);
        pyusdx.transfer(bob, boundedAmount);

        uint112 expectedPrincipal = _getExpectedPrincipal(boundedAmount, boundedIndex);

        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
        assertEq(pyusdx.earningPrincipalOf(bob), expectedPrincipal);
    }

    /* ============ Index Boundary Unit Tests ============ */

    /* ============ 3.1 Index Initialization Tests ============ */

    function test_mint_earningAccount_atInitialIndex() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Verify index starts at PRECISION (1e12)
        assertEq(pyusdx.currentAccountIndex(alice), PRECISION);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        // At initial index, principal should equal present amount
        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + MINT_AMOUNT);
        assertEq(pyusdx.currentAccountIndex(alice), indexBefore); // Index unchanged at 1e12
    }

    function test_transfer_earningToEarning_atInitialIndex() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        assertEq(pyusdx.currentAccountIndex(alice), PRECISION);

        minterGateway.mint(alice, MINT_AMOUNT);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // At initial index, principal transfer should equal amount transferred
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + TRANSFER_AMOUNT);
        assertEq(pyusdx.currentAccountIndex(alice), indexBefore);
    }

    function test_burn_earningAccount_atInitialIndex() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        assertEq(pyusdx.currentAccountIndex(alice), PRECISION);

        minterGateway.mint(alice, MINT_AMOUNT);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        // At initial index, principal burned should equal amount burned
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - BURN_AMOUNT);
        assertEq(pyusdx.currentAccountIndex(alice), indexBefore);
    }

    /* ============ 3.2 Precision Loss Tests ============ */

    function test_mint_earningAccount_smallAmount_highIndex() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set index to a high value (100x PRECISION)
        uint128 highIndex = PRECISION * 100;
        pyusdx.setAccountLastIndex(alice, highIndex);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Mint small amount at high index
        // Principal = amount * PRECISION / index = amount * 1e12 / (100 * 1e12) = amount / 100
        minterGateway.mint(alice, 100); // 100 PYUSDX

        // At 100x index, 100 tokens should only add 1 principal (rounded down)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + 1);
        assertEq(pyusdx.balanceOf(alice), 100);
    }

    function test_mint_earningAccount_principalRoundsToZero() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set index to very high value
        uint128 veryHighIndex = PRECISION * 1000;
        pyusdx.setAccountLastIndex(alice, veryHighIndex);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Mint amount that rounds to zero principal
        // Principal = 10 * 1e12 / (1000 * 1e12) = 0.01 -> rounds to 0
        minterGateway.mint(alice, 10);

        // Principal should be unchanged (rounded to zero)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore);
        assertEq(pyusdx.balanceOf(alice), 10);
    }

    function test_transfer_earningToEarning_smallAmount_highIndex() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set index to high value
        uint128 highIndex = PRECISION * 100;
        pyusdx.setAccountLastIndex(alice, highIndex);
        pyusdx.setAccountLastIndex(bob, highIndex);

        // Mint enough to get some principal
        minterGateway.mint(alice, 10000);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        // Transfer small amount at high index (using rounded up)
        vm.prank(alice);
        pyusdx.transfer(bob, 100);

        // At 100x index: 100 tokens = 1 principal (rounded up from transfer)
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - 1);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + 1);
    }

    function test_burn_earningAccount_smallAmount_nearZeroPrincipal() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set index to high value (but not too high that principal rounds to zero on mint)
        uint128 highIndex = PRECISION * 100; // 100x index
        pyusdx.setAccountLastIndex(alice, highIndex);

        // Mint amount that gives small principal: 1e6 * 1e12 / (100 * 1e12) = 10000
        minterGateway.mint(alice, 1e6);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        uint256 balanceBefore = pyusdx.balanceOf(alice);

        // Verify we got some principal
        assertGt(principalBefore, 0);

        // Burn small amount - principal should round up
        // Principal to burn = 10 * 1e12 / (100 * 1e12) = 0.1 -> rounds up to 1
        minterGateway.burn(alice, 10);

        // Principal should decrease by 1 (rounded up from 0.1)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - 1);
        assertEq(pyusdx.balanceOf(alice), balanceBefore - 10);
    }

    /* ============ 3.3 Extreme Index Tests ============ */

    function test_mint_earningAccount_after10YearsCompounding() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        uint128 indexBefore = pyusdx.currentAccountIndex(alice);

        // Warp 10 years
        vm.warp(365 days * 10);

        uint128 indexAfter10Years = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfter10Years > indexBefore);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.mint(alice, MINT_AMOUNT);

        assertEq(pyusdx.balanceOf(alice), balanceBefore + MINT_AMOUNT);

        // Principal should be less than amount at higher index
        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, indexAfter10Years);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
        assertTrue(expectedPrincipal < MINT_AMOUNT);
    }

    function test_transfer_earningToEarning_after50Years() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(1000));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(bob, uint24(1000));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Warp 50 years
        vm.warp(365 days * 50);

        uint128 indexAfter50Years = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfter50Years > PRECISION);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Principal subtracted from sender uses roundUp, principal added to recipient uses roundDown
        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, indexAfter50Years);
        uint112 expectedPrincipalAdded = _getExpectedPrincipal(TRANSFER_AMOUNT, indexAfter50Years);

        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipalAdded);
        assertTrue(expectedPrincipalSubtracted < TRANSFER_AMOUNT);
    }

    function test_burn_earningAccount_after100YearsMaxRate() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(10000));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Warp 100 years (extreme compounding)
        vm.warp(365 days * 100);

        uint128 indexAfter100Years = pyusdx.currentAccountIndex(alice);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        // Principal burned should be much less than amount at extreme index
        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexAfter100Years);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipal);
        assertTrue(expectedPrincipal < BURN_AMOUNT);
    }

    function test_index_growth_capsAtMax() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(10000));

        // Warp far into the future to try to overflow index
        vm.warp(365 days * 1000);

        uint128 extremeIndex = pyusdx.currentAccountIndex(alice);

        // Index should be capped at type(uint128).max via bound128
        assertLe(extremeIndex, type(uint128).max);

        // Mint should still work
        minterGateway.mint(alice, MINT_AMOUNT);
        assertEq(pyusdx.balanceOf(alice), MINT_AMOUNT);
    }

    /* ============ 3.4 Rate Change Tests ============ */

    function test_mint_earningAccount_withRateChange() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        // Warp to grow index
        vm.warp(365 days);
        uint128 indexAt5Percent = pyusdx.currentAccountIndex(alice);

        // Change rate - snapshot account index before changing rate
        pyusdx.setAccountLastIndex(alice, indexAt5Percent);
        pyusdx.setAccountRateBps(alice, uint24(1000));

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Mint at new rate (index already updated by setRate)
        minterGateway.mint(alice, MINT_AMOUNT);

        uint112 expectedPrincipal = _getExpectedPrincipal(MINT_AMOUNT, pyusdx.currentAccountIndex(alice));
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);

        // Index should have grown
        assertTrue(pyusdx.currentAccountIndex(alice) >= indexAt5Percent);
    }

    function test_transfer_earningToEarning_withRateChange() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(bob, uint24(500));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Warp
        vm.warp(180 days);

        // Change rate mid-stream - snapshot account indices before changing rate
        uint128 indexBeforeRateChange = pyusdx.currentAccountIndex(alice);
        pyusdx.setAccountLastIndex(alice, indexBeforeRateChange);
        pyusdx.setAccountRateBps(alice, uint24(2000));
        pyusdx.setAccountLastIndex(bob, indexBeforeRateChange);
        pyusdx.setAccountRateBps(bob, uint24(2000));

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
        uint128 currentAliceIndex = pyusdx.currentAccountIndex(alice);
        uint128 currentBobIndex = pyusdx.currentAccountIndex(bob);

        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Subtraction uses roundUp (sender), addition uses roundDown (recipient)
        uint112 expectedPrincipalSubtracted = _getExpectedPrincipalRoundedUp(TRANSFER_AMOUNT, currentAliceIndex);
        uint112 expectedPrincipalAdded = _getExpectedPrincipal(TRANSFER_AMOUNT, currentBobIndex);
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipalAdded);
    }

    function test_burn_earningAccount_withRateChange() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(1000));

        minterGateway.mint(alice, MINT_AMOUNT);

        // Grow index
        vm.warp(365 days);

        uint128 indexBeforeRateChange = pyusdx.currentAccountIndex(alice);

        // Change rate to 0% - snapshot the account index before changing rate
        pyusdx.setAccountLastIndex(alice, indexBeforeRateChange);
        pyusdx.setAccountRateBps(alice, uint24(0));

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        minterGateway.burn(alice, BURN_AMOUNT);

        // Burn uses index after rate change
        uint128 indexAfterRateChange = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfterRateChange >= indexBeforeRateChange);

        uint112 expectedPrincipal = _getExpectedPrincipalRoundedUp(BURN_AMOUNT, indexAfterRateChange);
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipal);
    }

    /* ============ 3.5 Rounding Invariant Tests ============ */

    function test_invariant_mint_principalMatchesRoundedDown() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Test at various index values
        uint128[4] memory indices = [PRECISION, PRECISION * 10, PRECISION * 100, PRECISION * 1000];

        for (uint256 i = 0; i < indices.length; i++) {
            pyusdx.setAccountLastIndex(alice, indices[i]);

            uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
            uint128 indexBefore = pyusdx.currentAccountIndex(alice);

            minterGateway.mint(alice, MINT_AMOUNT);

            // Verify principal matches rounded down calculation
            uint112 expectedPrincipal = _expectedPrincipalRoundDown(uint240(MINT_AMOUNT), indexBefore);
            assertEq(pyusdx.earningPrincipalOf(alice), principalBefore + expectedPrincipal);
        }
    }

    function test_invariant_burn_principalMatchesRoundedUp() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Test at various index values
        uint128[4] memory indices = [PRECISION, PRECISION * 10, PRECISION * 100, PRECISION * 1000];

        for (uint256 i = 0; i < indices.length; i++) {
            pyusdx.setAccountLastIndex(alice, indices[i]);

            minterGateway.mint(alice, MINT_AMOUNT);

            uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
            uint128 indexBefore = pyusdx.currentAccountIndex(alice);

            minterGateway.burn(alice, BURN_AMOUNT);

            // Verify principal subtracted matches rounded up calculation
            uint112 expectedPrincipal = _expectedPrincipalRoundUp(uint240(BURN_AMOUNT), indexBefore);
            assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - expectedPrincipal);
        }
    }

    function test_invariant_transfer_principalMatchesRoundedUp() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Test at various index values
        uint128[4] memory indices = [PRECISION, PRECISION * 10, PRECISION * 100, PRECISION * 1000];

        for (uint256 i = 0; i < indices.length; i++) {
            pyusdx.setAccountLastIndex(alice, indices[i]);
            pyusdx.setAccountLastIndex(bob, indices[i]);

            minterGateway.mint(alice, MINT_AMOUNT);

            uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
            uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
            uint128 indexBefore = pyusdx.currentAccountIndex(alice);

            vm.prank(alice);
            pyusdx.transfer(bob, TRANSFER_AMOUNT);

            // Verify principal transferred matches rounded up calculation
            uint112 expectedPrincipal = _expectedPrincipalRoundUp(uint240(TRANSFER_AMOUNT), indexBefore);
            assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipal);
            assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);
        }
    }

    function test_invariant_transfer_crossEarning_principalAsymmetry() public {
        // Test E->N and N->E paths to verify different rounding behavior
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index for visible rounding differences
        pyusdx.setAccountLastIndex(alice, PRECISION * 100);

        minterGateway.mint(alice, MINT_AMOUNT);

        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint128 index = pyusdx.currentAccountIndex(alice);

        // E->N transfer: subtract earning principal (rounded up), no totalSupply change
        vm.prank(alice);
        pyusdx.transfer(bob, TRANSFER_AMOUNT);

        // Verify E->N uses rounded up for subtraction
        uint112 expectedPrincipalSubtracted = _expectedPrincipalRoundUp(uint240(TRANSFER_AMOUNT), index);
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - expectedPrincipalSubtracted);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);

        // Now test N->E with a different scenario
        // Mint to david as non-earning, then set him to earning, then transfer to carol
        minterGateway.mint(david, TRANSFER_AMOUNT);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(carol, true, earnerManager, 0, address(0));
        pyusdx.setAccountLastIndex(carol, PRECISION * 100);

        uint256 davidBalance = pyusdx.balanceOf(david);

        // David (non-earning) transfers to Carol (earning)
        vm.prank(david);
        pyusdx.transfer(carol, davidBalance);

        // N->E: subtract non-earning (1:1), add earning principal (rounded down)
        // Carol should get principal rounded down from the amount
        uint112 expectedPrincipalAdded = _expectedPrincipalRoundDown(uint240(davidBalance), index);
        assertEq(pyusdx.earningPrincipalOf(carol), expectedPrincipalAdded);
    }

    /* ============ Rounding Edge Case Tests ============ */

    /* ============ Principal Depletion Tests ============ */

    function test_burn_earningAccount_depletesPrincipal_nonZeroBalanceRemains() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index so small amounts give tiny principal
        pyusdx.setAccountLastIndex(alice, PRECISION * 1000);

        // Mint enough to get some principal
        minterGateway.mint(alice, 1000);
        uint112 initialPrincipal = pyusdx.earningPrincipalOf(alice);
        assertTrue(initialPrincipal > 0);

        // Burn most of the balance, leaving some
        // Each burn rounds up principal, so we may drain principal before balance
        minterGateway.burn(alice, 500);

        uint256 balanceAfter = pyusdx.balanceOf(alice);
        uint112 principalAfter = pyusdx.earningPrincipalOf(alice);

        // We may have principal depletion (balance > 0 but principal = 0)
        // This is allowed due to rounding up in burns
        if (balanceAfter > 0 && principalAfter == 0) {
            // Principal depletion detected - this is expected behavior
            assertTrue(_hasPrincipalDepletion(alice));
        } else {
            // No depletion - principal should be consistent with balance at high index
            assertTrue(principalAfter <= initialPrincipal);
        }
    }

    function test_transfer_earningToEarning_depletesPrincipal() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index (100x, not 1000x to get some principal on mint)
        pyusdx.setAccountLastIndex(alice, PRECISION * 100);
        pyusdx.setAccountLastIndex(bob, PRECISION * 100);

        // Mint small amount: 100 * 1e12 / (100 * 1e12) = 1 principal
        minterGateway.mint(alice, 100);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        assertEq(alicePrincipalBefore, 1); // Exactly 1 principal

        // Transfer at high index - principal subtracted rounds up
        // With 100x index: 100 tokens = 1 principal -> rounds up to 1
        vm.prank(alice);
        pyusdx.transfer(bob, 100);

        // Alice's principal should be 0 (depletion)
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertTrue(pyusdx.balanceOf(alice) == 0); // Full transfer

        // Bob should have received 1 principal (rounded up)
        assertEq(pyusdx.earningPrincipalOf(bob), 1);
        assertEq(pyusdx.balanceOf(bob), 100);
    }

    function test_transfer_crossEarning_depletesPrincipal() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index (100x, not 1000x to get some principal on mint)
        pyusdx.setAccountLastIndex(alice, PRECISION * 100);

        // Mint small amount that gives small principal: 100 * 1e12 / (100 * 1e12) = 1
        minterGateway.mint(alice, 100);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);
        assertEq(principalBefore, 1); // Exactly 1 principal

        // Transfer to non-earning bob - E->N: principal subtracted (rounded up), bob gets non-earning 1:1
        vm.prank(alice);
        pyusdx.transfer(bob, 100);

        // Alice's principal should be depleted to 0 (since 100 * 1e12 / (100 * 1e12) = 1, rounded up)
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertEq(pyusdx.balanceOf(alice), 0);

        // Bob should have full balance as non-earning
        assertEq(pyusdx.balanceOf(bob), 100);
        assertEq(pyusdx.earningPrincipalOf(bob), 0);
    }

    /* ============ Repeated Operations Compound Rounding Tests ============ */

    function test_repeatedTransfers_principalConsistency() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(carol, true, earnerManager, 0, address(0));

        // Set high index for visible rounding
        pyusdx.setAccountLastIndex(alice, PRECISION * 100);
        pyusdx.setAccountLastIndex(bob, PRECISION * 100);
        pyusdx.setAccountLastIndex(carol, PRECISION * 100);

        minterGateway.mint(alice, 1000);
        uint112 aliceInitialPrincipal = pyusdx.earningPrincipalOf(alice);

        // Transfer alice -> bob -> carol
        vm.prank(alice);
        pyusdx.transfer(bob, 500);

        vm.prank(bob);
        pyusdx.transfer(carol, 500);

        uint112 carolPrincipal = pyusdx.earningPrincipalOf(carol);
        uint112 aliceFinalPrincipal = pyusdx.earningPrincipalOf(alice);

        // Carol should have received the rounded-up principal from bob
        assertTrue(carolPrincipal > 0);

        // Alice should have less principal
        assertTrue(aliceFinalPrincipal < aliceInitialPrincipal);
    }

    function test_repeatedMintBurn_principalConsistency() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set index
        pyusdx.setAccountLastIndex(alice, PRECISION * 10);

        uint256 totalMinted = 0;
        uint256 totalBurned = 0;

        // Repeated mint/burn cycles
        for (uint256 i = 0; i < 10; i++) {
            minterGateway.mint(alice, 100);
            totalMinted += 100;

            minterGateway.burn(alice, 50);
            totalBurned += 50;
        }

        uint256 finalBalance = pyusdx.balanceOf(alice);
        uint112 finalPrincipal = pyusdx.earningPrincipalOf(alice);

        // Final balance should match net minted
        assertEq(finalBalance, totalMinted - totalBurned);

        // Principal should be positive (mint adds, burn subtracts)
        assertTrue(finalPrincipal > 0);
    }

    function test_repeatedMintTransfer_principalConsistency() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index
        pyusdx.setAccountLastIndex(alice, PRECISION * 50);
        pyusdx.setAccountLastIndex(bob, PRECISION * 50);

        // Mint and transfer in cycles
        for (uint256 i = 0; i < 5; i++) {
            minterGateway.mint(alice, 100);

            vm.prank(alice);
            pyusdx.transfer(bob, 100);
        }

        // Bob should have all the balance
        assertEq(pyusdx.balanceOf(bob), 500);
        assertEq(pyusdx.balanceOf(alice), 0);

        // Bob should have some principal (accumulated from transfers)
        uint112 bobPrincipal = pyusdx.earningPrincipalOf(bob);
        assertTrue(bobPrincipal > 0);

        // At 50x index, 500 tokens ≈ 10 principal (rounded up per transfer)
        assertTrue(bobPrincipal >= 5); // At minimum
        assertTrue(bobPrincipal <= 10);
    }

    /* ============ Small Amounts at High Index Tests ============ */

    function test_mint_smallAmount_highIndex_principalRoundsToZero() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set extremely high index
        pyusdx.setAccountLastIndex(alice, PRECISION * 10000);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Mint tiny amount
        // Principal = 1 * 1e12 / (10000 * 1e12) = 0.0001 -> rounds to 0
        minterGateway.mint(alice, 1);

        // Principal should be unchanged (rounded to zero)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore);
        assertEq(pyusdx.balanceOf(alice), 1);
    }

    function test_burn_smallAmount_highIndex_principalRoundsUp() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index (100x, not 1000x to avoid rounding to zero on mint)
        pyusdx.setAccountLastIndex(alice, PRECISION * 100);

        // Mint larger amount to get principal: 1e6 * 1e12 / (100 * 1e12) = 10000
        minterGateway.mint(alice, 1e6);

        uint112 principalBefore = pyusdx.earningPrincipalOf(alice);

        // Burn small amount - principal rounds up
        // Principal = 1 * 1e12 / (100 * 1e12) = 0.01 -> rounds up to 1
        minterGateway.burn(alice, 1);

        // Principal should decrease by 1 (rounded up)
        assertEq(pyusdx.earningPrincipalOf(alice), principalBefore - 1);
        assertEq(pyusdx.balanceOf(alice), 1e6 - 1);
    }

    function test_transfer_smallAmount_highIndex_roundingAsymmetry() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index (100x, not 1000x to avoid rounding to zero on mint)
        pyusdx.setAccountLastIndex(alice, PRECISION * 100);
        pyusdx.setAccountLastIndex(bob, PRECISION * 100);

        // Mint larger amount to get principal: 1e6 * 1e12 / (100 * 1e12) = 10000
        minterGateway.mint(alice, 1e6);

        uint112 alicePrincipalBefore = pyusdx.earningPrincipalOf(alice);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        // Transfer small amount
        vm.prank(alice);
        pyusdx.transfer(bob, 10);

        // Sender principal rounds up: 10 * 1e12 / (100 * 1e12) = 0.1 -> rounds up to 1
        // Recipient principal rounds down: 10 * 1e12 / (100 * 1e12) = 0.1 -> rounds down to 0
        assertEq(pyusdx.earningPrincipalOf(alice), alicePrincipalBefore - 1);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + 0);
        assertEq(pyusdx.balanceOf(bob), 10);
    }

    /* ============ Large Amounts at Low Index Tests ============ */

    function test_mint_largeAmount_totalSupplyOverflow() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set total supply near max
        pyusdx.setTotalSupply(type(uint240).max - 50);

        // Try to mint large amount - should revert due to overflow
        vm.expectRevert(IPYUSDX.OverflowsPrincipalOfTotalSupply.selector);
        minterGateway.mint(alice, 100);
    }

    function test_transfer_largeAmount_lowIndex_principalOverflow() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // At low index, principal equals amount
        pyusdx.setAccountLastIndex(alice, PRECISION);
        pyusdx.setAccountLastIndex(bob, PRECISION);

        // Set bob's principal near max
        pyusdx.setEarningPrincipal(bob, type(uint112).max - 50);

        // Mint and transfer large amount
        minterGateway.mint(alice, 100);

        // Transfer succeeds - earningPrincipal addition is unchecked (wraps around)
        vm.prank(alice);
        pyusdx.transfer(bob, 100);

        // Verify balances transferred correctly
        assertEq(pyusdx.balanceOf(bob), 100);
        assertEq(pyusdx.balanceOf(alice), 0);
    }

    /* ============ min112 Capping Behavior Tests ============ */

    function test_transfer_insufficientPrincipal_min112Caps() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index so transfer needs more principal than available
        pyusdx.setAccountLastIndex(alice, PRECISION * 1000);
        pyusdx.setAccountLastIndex(bob, PRECISION * 1000);

        minterGateway.mint(alice, 100);

        // Manually set alice's principal to very low value
        pyusdx.setEarningPrincipal(alice, 1);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        // Transfer should work - min112 caps at available principal
        vm.prank(alice);
        pyusdx.transfer(bob, 50);

        // Alice's balance should decrease
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - 50);

        // Alice's principal should be 0 (capped via min112)
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Bob's principal is computed independently via roundDown(50, 1000*PRECISION) = 0
        // Sender subtraction and recipient addition are independent calculations
        uint128 bobIndex = pyusdx.currentAccountIndex(bob);
        uint112 expectedBobPrincipal = _getExpectedPrincipal(50, bobIndex);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedBobPrincipal);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + 50);
    }

    function test_burn_insufficientPrincipal_min112Caps() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        // Set high index
        pyusdx.setAccountLastIndex(alice, PRECISION * 1000);

        minterGateway.mint(alice, 100);

        // Manually set alice's principal to very low value
        pyusdx.setEarningPrincipal(alice, 1);

        uint256 balanceBefore = pyusdx.balanceOf(alice);

        // Burn should work - min112 caps at available principal
        minterGateway.burn(alice, 50);

        // Balance should decrease
        assertEq(pyusdx.balanceOf(alice), balanceBefore - 50);

        // Principal should be 0 (capped via min112)
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
    }

    function test_transfer_min112_recipientGetsPrincipal() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, earnerManager, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Set high index
        pyusdx.setAccountLastIndex(alice, PRECISION * 1000);
        pyusdx.setAccountLastIndex(bob, PRECISION * 1000);

        minterGateway.mint(alice, 100);

        // Set alice's principal low
        pyusdx.setEarningPrincipal(alice, 1);

        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);

        // Transfer - recipient gets the capped principal
        vm.prank(alice);
        pyusdx.transfer(bob, 50);

        // Bob's principal is computed independently via roundDown(50, 1000*PRECISION) = 0
        // (separate from alice's capped subtraction)
        uint128 bobIndex = pyusdx.currentAccountIndex(bob);
        uint112 expectedBobPrincipal = _getExpectedPrincipal(50, bobIndex);
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedBobPrincipal);

        // Even though 50 tokens at 1000x index would need more principal,
        // the transfer succeeds with min112 capping
        assertEq(pyusdx.balanceOf(bob), 50);
    }

    /* ============ accruedYieldOf ============ */

    function test_accruedYieldOf_nonEarner() public view {
        uint240 yield = pyusdx.accruedYieldOf(alice);
        assertEq(yield, 0, "Non-earner should have 0 accrued yield");
    }

    function test_accruedYieldOf_earner() public {
        // Mint tokens to alice first (as non-earner)
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        // Set up alice as an earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        // Warp time to accrue yield
        vm.warp(block.timestamp + 365 days);

        // Calculate expected yield
        uint128 index = pyusdx.currentAccountIndex(alice);
        uint112 principal = pyusdx.earningPrincipalOf(alice);
        uint240 expectedBalanceWithYield = IndexingMath.getPresentAmountRoundedDown(principal, index);
        uint240 expectedYield = expectedBalanceWithYield > uint240(balance)
            ? expectedBalanceWithYield - uint240(balance)
            : 0;

        // Verify yield calculation
        uint240 actualYield = pyusdx.accruedYieldOf(alice);
        assertEq(actualYield, expectedYield, "Accrued yield should match expected");
        assertGt(actualYield, 0, "Should have positive yield after time passes");
    }

    /* ============ balanceWithYieldOf ============ */

    function test_balanceWithYieldOf() public {
        // Mint tokens to alice first (as non-earner)
        minterGateway.mint(alice, 1000e6);

        // Set up alice as an earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        vm.warp(block.timestamp + 365 days);

        uint256 balanceWithYield = pyusdx.balanceWithYieldOf(alice);
        uint256 expectedBalance = pyusdx.balanceOf(alice) + pyusdx.accruedYieldOf(alice);

        assertEq(balanceWithYield, expectedBalance, "balanceWithYieldOf should equal balance + accruedYield");
    }

    /* ============ claimFor ============ */

    function test_claimFor_happyPath() public {
        // Mint tokens to alice first (as non-earner)
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        // Set up alice as an earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        vm.warp(block.timestamp + 365 days);

        uint240 expectedYield = pyusdx.accruedYieldOf(alice);
        assertGt(expectedYield, 0, "Should have yield to claim");

        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 balanceBefore = pyusdx.balanceOf(alice);

        vm.expectEmit();
        emit IPYUSDX.Claimed(alice, alice, expectedYield);

        vm.expectEmit();
        emit Transfer(address(0), alice, expectedYield);

        uint240 claimed = pyusdx.claimFor(alice);

        assertEq(claimed, expectedYield, "Should return claimed yield");
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + expectedYield, "Total supply should increase by yield");
        assertEq(pyusdx.balanceOf(alice), balanceBefore + expectedYield, "balanceOf should increase by yield");
        assertEq(pyusdx.accruedYieldOf(alice), 0, "Accrued yield should be 0 after claim");
    }

    function test_claimFor_revert_whenPaused() public {
        // Mint tokens to alice first (as non-earner)
        minterGateway.mint(alice, 1000e6);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        pyusdx.claimFor(alice);
    }

    function test_claimFor_revert_whenFrozen() public {
        // Mint tokens to alice first (as non-earner)
        minterGateway.mint(alice, 1000e6);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        pyusdx.claimFor(alice);
    }

    /* ============ setEarningDetails ============ */

    function test_setEarningDetails_enableEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        (bool isEarning, address manager, uint16 feeRate, address recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(manager, earnerManager);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);
    }

    function test_setEarningDetails_disableEarning() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 0, address(0));

        (bool isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
    }

    function test_setEarningDetails_revert_zeroAccount() public {
        vm.expectRevert(IPYUSDX.ZeroAccount.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(address(0), true, 500, bob);
    }

    function test_setEarningDetails_revert_feeRateTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.FeeRateTooHigh.selector, 10001));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 10001, bob);
    }

    function test_setEarningDetails_revert_invalidDetails() public {
        vm.expectRevert(IPYUSDX.InvalidDetails.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 500, bob);
    }

    function test_setEarningDetails_batch() public {
        address[] memory batchAccounts = new address[](2);
        batchAccounts[0] = alice;
        batchAccounts[1] = bob;

        bool[] memory isEarning = new bool[](2);
        isEarning[0] = true;
        isEarning[1] = true;

        uint16[] memory feeRates = new uint16[](2);
        feeRates[0] = 500;
        feeRates[1] = 1000;

        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = alice;

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(batchAccounts, isEarning, feeRates, recipients);

        assertTrue(pyusdx.isEarning(alice));
        assertTrue(pyusdx.isEarning(bob));
    }

    function test_setEarningDetails_batch_revert_arrayLengthZero() public {
        vm.expectRevert(IPYUSDX.ArrayLengthZero.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(new address[](0), new bool[](0), new uint16[](0), new address[](0));
    }

    function test_setEarningDetails_batch_revert_arrayLengthMismatch() public {
        vm.expectRevert(IForcedTransferable.ArrayLengthMismatch.selector);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(new address[](2), new bool[](1), new uint16[](2), new address[](2));
    }

    function test_setEarningDetails_noop_alreadyDisabled() public {
        // Alice is not earning (default state)
        (bool isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);

        // Calling setEarningDetails with isEarning=false should be a no-op (no event)
        vm.recordLogs();
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 0, address(0));

        // Verify no EarningDetailsSet event was emitted
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], IPYUSDX.EarningDetailsSet.selector);
        }

        // State should remain unchanged
        (isEarning, , , ) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
    }

    function test_setEarningDetails_noop_sameSettings() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        (bool isEarning, address manager, uint16 feeRate, address recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);

        // Call again with same settings - should be a no-op (no event, no claim)
        vm.recordLogs();
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Verify no EarningDetailsSet event was emitted
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], IPYUSDX.EarningDetailsSet.selector);
        }

        // State should remain unchanged
        (isEarning, manager, feeRate, recipient) = pyusdx.getEarningDetails(alice);
        assertTrue(isEarning);
        assertEq(manager, earnerManager);
        assertEq(feeRate, 500);
        assertEq(recipient, bob);
    }

    function test_setEarningDetails_changedFeeRate_emitsEvent() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Change fee rate - should emit event
        vm.expectEmit();
        emit IPYUSDX.EarningDetailsSet(alice, true, earnerManager, 1000, bob);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        // Verify state updated
        (, , uint16 feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(feeRate, 1000);
    }

    function test_setEarningDetails_changedClaimRecipient_emitsEvent() public {
        // First enable earning for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        address charlie = makeAddr("charlie");

        // Change claim recipient - should emit event
        vm.expectEmit();
        emit IPYUSDX.EarningDetailsSet(alice, true, earnerManager, 500, charlie);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, charlie);

        // Verify state updated
        (, , , address recipient) = pyusdx.getEarningDetails(alice);
        assertEq(recipient, charlie);
    }

    function test_setEarningDetails_revert_earnerDetailsAlreadySet() public {
        // First earner manager sets earning details for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // A different earner manager tries to modify alice's details
        address otherEarnerManager = makeAddr("otherEarnerManager");
        bytes32 earnerManagerRole = pyusdx.EARNER_MANAGER_ROLE();
        vm.prank(admin);
        pyusdx.grantRole(earnerManagerRole, otherEarnerManager);

        // EarnerDetailsAlreadySet is thrown because alice is managed by a different active earner manager
        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.EarnerDetailsAlreadySet.selector, alice));
        vm.prank(otherEarnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);
    }

    function test_setEarningDetails_sameManagerCanUpdate() public {
        // First earner manager sets earning details for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Same earner manager can update alice's details
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        (, , uint16 feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(feeRate, 1000);
    }

    function test_setEarningDetails_revert_notEarnerManager() public {
        // Random caller without EARNER_MANAGER_ROLE
        address randomCaller = makeAddr("randomCaller");

        vm.expectRevert(IPYUSDX.NotEarnerManager.selector);
        vm.prank(randomCaller);
        pyusdx.setEarningDetails(alice, true, 500, bob);
    }

    function test_setEarningDetails_takeover_whenStoredManagerLostRole() public {
        // First earner manager sets earning details for alice
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        // Verify earnerManager is stored as alice's manager
        (, address storedManager, , ) = pyusdx.getEarningDetails(alice);
        assertEq(storedManager, earnerManager);

        // Create a new earner manager
        address newEarnerManager = makeAddr("newEarnerManager");
        bytes32 earnerManagerRole = pyusdx.EARNER_MANAGER_ROLE();
        vm.prank(admin);
        pyusdx.grantRole(earnerManagerRole, newEarnerManager);

        // Revoke role from original earner manager
        vm.prank(admin);
        pyusdx.revokeRole(earnerManagerRole, earnerManager);

        // New earner manager can now take over alice's account (stored manager lost role)
        vm.prank(newEarnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, bob);

        // Verify new manager is now stored
        uint16 feeRate;
        (, storedManager, feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(storedManager, newEarnerManager);
        assertEq(feeRate, 1000);
    }

    /* ============ freeze / freezeAccounts (earning stop) ============ */

    function test_freeze_earningAccount_claimsYieldAndStopsEarning() public {
        // Mint tokens to alice
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        // Set up alice as an earner with NO fee and NO claim recipient (yield stays with alice)
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));
        pyusdx.setAccountRateBps(alice, uint24(500));

        // Warp time to accrue yield
        vm.warp(block.timestamp + 365 days);

        uint240 expectedYield = pyusdx.accruedYieldOf(alice);
        assertGt(expectedYield, 0, "Should have yield to claim");

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);

        // Expect both StoppedEarning and Frozen events
        vm.expectEmit();
        emit IPYUSDX.StoppedEarning(alice);

        vm.expectEmit();
        emit IFreezable.Frozen(alice, block.timestamp);

        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Verify frozen
        assertTrue(pyusdx.isFrozen(alice));

        // Verify earning stopped
        (bool isEarning, address storedManager, uint16 feeRate, address claimRecipient) = pyusdx.getEarningDetails(
            alice
        );
        assertFalse(isEarning);
        assertEq(storedManager, address(0));
        assertEq(feeRate, 0);
        assertEq(claimRecipient, address(0));

        // Verify principal cleared
        assertEq(pyusdx.earningPrincipalOf(alice), 0);

        // Verify alice's balance increased from claimed yield (since no fee/redirect)
        uint256 aliceBalanceAfter = pyusdx.balanceOf(alice);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + expectedYield);
    }

    function test_freeze_earningAccount_clearsAllEarningData() public {
        // Mint tokens to alice
        minterGateway.mint(alice, 1000e6);

        // Set up alice as an earner with all fields populated
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 5000, bob); // 50% fee, bob is recipient

        // Verify earning data is set
        (bool isEarning, address storedManager, uint16 feeRate, address claimRecipient) = pyusdx.getEarningDetails(
            alice
        );
        assertTrue(isEarning);
        assertEq(storedManager, earnerManager);
        assertEq(feeRate, 5000);
        assertEq(claimRecipient, bob);
        assertGt(pyusdx.earningPrincipalOf(alice), 0);

        // Freeze
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Verify ALL earning data cleared
        (isEarning, storedManager, feeRate, claimRecipient) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
        assertEq(storedManager, address(0));
        assertEq(feeRate, 0);
        assertEq(claimRecipient, address(0));
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
    }

    function test_freeze_earningAccount_totalSupplyUnchanged() public {
        // Mint tokens to alice
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        // Set up alice as an earner
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        uint256 totalSupplyBefore = pyusdx.totalSupply();

        // Freeze
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // totalSupply unchanged (earning transition doesn't create/destroy tokens)
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
    }

    function test_freeze_nonEarningAccount_noStoppedEarningEvent() public {
        // Mint tokens to alice (non-earner by default)
        minterGateway.mint(alice, 1000e6);
        assertFalse(pyusdx.isEarning(alice));

        // Record logs to verify StoppedEarning is NOT emitted
        vm.recordLogs();

        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Verify frozen
        assertTrue(pyusdx.isFrozen(alice));

        // Verify no StoppedEarning event was emitted
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], IPYUSDX.StoppedEarning.selector);
        }
    }

    function test_freeze_alreadyFrozenAccount_noop() public {
        // Mint and set up alice as earner
        minterGateway.mint(alice, 1000e6);
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        // First freeze
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        assertTrue(pyusdx.isFrozen(alice));
        assertFalse(pyusdx.isEarning(alice));

        // Record logs for second freeze
        vm.recordLogs();

        // Second freeze should be a no-op (already frozen)
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Verify no events emitted (since account was already frozen and not earning)
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], IPYUSDX.StoppedEarning.selector);
            assertNotEq(logs[i].topics[0], IFreezable.Frozen.selector);
        }
    }

    function test_freezeAccounts_batch_stopsEarningForAll() public {
        // Mint tokens to alice, bob, carol
        minterGateway.mint(alice, 1000e6);
        minterGateway.mint(bob, 2000e6);
        minterGateway.mint(carol, 3000e6);

        // Set up alice and bob as earners (carol stays non-earner)
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, david);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, 500, david);

        // Warp time to accrue yield
        vm.warp(block.timestamp + 180 days);

        assertTrue(pyusdx.isEarning(alice));
        assertTrue(pyusdx.isEarning(bob));
        assertFalse(pyusdx.isEarning(carol));

        address[] memory accountsToFreeze = new address[](3);
        accountsToFreeze[0] = alice;
        accountsToFreeze[1] = bob;
        accountsToFreeze[2] = carol;

        // Freeze all accounts
        vm.prank(freezeManager);
        pyusdx.freezeAccounts(accountsToFreeze);

        // Verify all frozen
        assertTrue(pyusdx.isFrozen(alice));
        assertTrue(pyusdx.isFrozen(bob));
        assertTrue(pyusdx.isFrozen(carol));

        // Verify earning stopped for alice and bob
        assertFalse(pyusdx.isEarning(alice));
        assertFalse(pyusdx.isEarning(bob));
        assertFalse(pyusdx.isEarning(carol));

        // Verify all earning data cleared for alice and bob
        (bool isEarning, address manager, uint16 feeRate, address recipient) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
        assertEq(manager, address(0));
        assertEq(feeRate, 0);
        assertEq(recipient, address(0));

        (isEarning, manager, feeRate, recipient) = pyusdx.getEarningDetails(bob);
        assertFalse(isEarning);
        assertEq(manager, address(0));
        assertEq(feeRate, 0);
        assertEq(recipient, address(0));
    }

    function test_freezeAccounts_emitsEventsInOrder() public {
        // Mint tokens
        minterGateway.mint(alice, 1000e6);
        minterGateway.mint(bob, 1000e6);

        // Set up as earners
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, 0, address(0));

        address[] memory accountsToFreeze = new address[](2);
        accountsToFreeze[0] = alice;
        accountsToFreeze[1] = bob;

        // Expect events in order: StoppedEarning(alice), Frozen(alice), StoppedEarning(bob), Frozen(bob)
        vm.expectEmit();
        emit IPYUSDX.StoppedEarning(alice);

        vm.expectEmit();
        emit IFreezable.Frozen(alice, block.timestamp);

        vm.expectEmit();
        emit IPYUSDX.StoppedEarning(bob);

        vm.expectEmit();
        emit IFreezable.Frozen(bob, block.timestamp);

        vm.prank(freezeManager);
        pyusdx.freezeAccounts(accountsToFreeze);
    }

    function test_freeze_revert_notFreezeManager() public {
        vm.expectRevert();
        vm.prank(alice);
        pyusdx.freeze(bob);
    }

    function test_freezeAccounts_revert_notFreezeManager() public {
        address[] memory accountsToFreeze = new address[](1);
        accountsToFreeze[0] = alice;

        vm.expectRevert();
        vm.prank(alice);
        pyusdx.freezeAccounts(accountsToFreeze);
    }

    /* ============ forceTransfer ============ */

    function test_forceTransfer_happyPath_nonEarningToNonEarning() public {
        // Mint to alice
        minterGateway.mint(alice, MINT_AMOUNT);

        // Freeze alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        // Force transfer from frozen alice to bob
        vm.expectEmit();
        emit Transfer(alice, bob, TRANSFER_AMOUNT);

        vm.expectEmit();
        emit IForcedTransferable.ForcedTransfer(alice, bob, forcedTransferManager, TRANSFER_AMOUNT);

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, TRANSFER_AMOUNT);

        // Verify balances
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + TRANSFER_AMOUNT);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_forceTransfer_happyPath_nonEarningToEarning() public {
        // Make bob earning
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, earnerManager, 0, address(0));

        // Mint to alice (non-earning)
        minterGateway.mint(alice, MINT_AMOUNT);

        // Freeze alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint112 bobPrincipalBefore = pyusdx.earningPrincipalOf(bob);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        // Force transfer from frozen alice to earning bob
        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, TRANSFER_AMOUNT);

        // Verify balances
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + TRANSFER_AMOUNT);

        // Bob's principal should increase
        uint112 expectedPrincipal = _getExpectedPrincipal(TRANSFER_AMOUNT, pyusdx.currentAccountIndex(bob));
        assertEq(pyusdx.earningPrincipalOf(bob), bobPrincipalBefore + expectedPrincipal);

        // totalSupply unchanged (transfer)
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_forceTransfer_revert_accountNotFrozen() public {
        // Mint to alice but don't freeze
        minterGateway.mint(alice, MINT_AMOUNT);

        // Attempt force transfer from non-frozen alice
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, alice));

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, TRANSFER_AMOUNT);
    }

    function test_forceTransfer_revert_zeroRecipient() public {
        // Mint and freeze alice
        minterGateway.mint(alice, MINT_AMOUNT);
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Attempt force transfer to zero address
        vm.expectRevert(IPYUSDX.ZeroAccount.selector);

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, address(0), TRANSFER_AMOUNT);
    }

    function test_forceTransfer_revert_insufficientBalance() public {
        // Mint small amount to alice
        minterGateway.mint(alice, MINT_AMOUNT);

        // Freeze alice
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Attempt to transfer more than balance
        uint256 excessiveAmount = MINT_AMOUNT + 1;

        vm.expectRevert(
            abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, uint240(MINT_AMOUNT), excessiveAmount)
        );

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, excessiveAmount);
    }

    function test_forceTransfer_zeroAmount() public {
        // Mint and freeze alice
        minterGateway.mint(alice, MINT_AMOUNT);
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);

        // Zero amount should emit events but not change balances
        vm.expectEmit();
        emit Transfer(alice, bob, 0);

        vm.expectEmit();
        emit IForcedTransferable.ForcedTransfer(alice, bob, forcedTransferManager, 0);

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfer(alice, bob, 0);

        // Balances unchanged
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore);
    }

    function test_forceTransfer_revert_notForcedTransferManager() public {
        // Mint and freeze alice
        minterGateway.mint(alice, MINT_AMOUNT);
        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        // Attempt force transfer without role
        vm.expectRevert();
        vm.prank(alice);
        pyusdx.forceTransfer(alice, bob, TRANSFER_AMOUNT);
    }

    function test_forceTransfers_batch() public {
        // Mint to alice and bob
        minterGateway.mint(alice, MINT_AMOUNT);
        minterGateway.mint(bob, MINT_AMOUNT);

        // Freeze both
        vm.prank(freezeManager);
        pyusdx.freeze(alice);
        vm.prank(freezeManager);
        pyusdx.freeze(bob);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 carolBalanceBefore = pyusdx.balanceOf(carol);

        // Batch force transfer
        address[] memory frozenAccounts = new address[](2);
        frozenAccounts[0] = alice;
        frozenAccounts[1] = bob;

        address[] memory recipients = new address[](2);
        recipients[0] = carol;
        recipients[1] = carol;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = TRANSFER_AMOUNT;
        amounts[1] = TRANSFER_AMOUNT;

        vm.prank(forcedTransferManager);
        pyusdx.forceTransfers(frozenAccounts, recipients, amounts);

        // Verify balances
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore - TRANSFER_AMOUNT);
        assertEq(pyusdx.balanceOf(carol), carolBalanceBefore + 2 * TRANSFER_AMOUNT);
    }

    /* ============ setEarnerRate / setEarnerRateBatch ============ */

    function test_setEarnerRate_happyPath() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.expectEmit();
        emit IPYUSDX.EarnerRateSet(alice, 0, 500);

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);
    }

    function test_setEarnerRate_revert_notRateManager() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.expectRevert(IPYUSDX.NotRateManager.selector);
        vm.prank(alice);
        pyusdx.setEarnerRate(alice, 500);
    }

    function test_setEarnerRate_revert_notEarning() public {
        vm.expectRevert(IPYUSDX.NotEarning.selector);
        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);
    }

    function test_setEarnerRate_revert_rateTooHigh() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.expectRevert(IPYUSDX.RateTooHigh.selector);
        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 10001);
    }

    function test_setEarnerRate_noop_sameRate() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);

        vm.recordLogs();
        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], IPYUSDX.EarnerRateSet.selector);
        }
    }

    function test_setEarnerRate_snapshotsIndex() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);

        minterGateway.mint(alice, 1000e6);

        vm.warp(block.timestamp + 365 days);

        uint128 indexBeforeChange = pyusdx.currentAccountIndex(alice);
        assertTrue(indexBeforeChange > PRECISION);

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 1000);

        // Index immediately after should equal the snapshotted value
        uint128 indexAfterChange = pyusdx.currentAccountIndex(alice);
        assertEq(indexAfterChange, indexBeforeChange);

        vm.warp(block.timestamp + 365 days);

        // Index should grow at the new 10% rate
        uint128 indexAfterSecondYear = pyusdx.currentAccountIndex(alice);
        assertTrue(indexAfterSecondYear > indexBeforeChange);
        // Must have grown by more than 5% (old rate), confirming new rate is active
        assertTrue(
            indexAfterSecondYear > indexBeforeChange + ((indexBeforeChange * 5) / 100),
            "Should grow by more than 5% at 10% rate"
        );
    }

    function test_setEarnerRateBatch_happyPath() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, 0, address(0));

        address[] memory batchAccounts = new address[](2);
        batchAccounts[0] = alice;
        batchAccounts[1] = bob;

        uint24[] memory rates = new uint24[](2);
        rates[0] = 500;
        rates[1] = 1000;

        vm.expectEmit();
        emit IPYUSDX.EarnerRateSet(alice, 0, 500);
        vm.expectEmit();
        emit IPYUSDX.EarnerRateSet(bob, 0, 1000);

        vm.prank(rateManager);
        pyusdx.setEarnerRateBatch(batchAccounts, rates);
    }

    function test_setEarnerRateBatch_revert_arrayLengthMismatch() public {
        address[] memory batchAccounts = new address[](2);
        batchAccounts[0] = alice;
        batchAccounts[1] = bob;

        uint24[] memory rates = new uint24[](1);
        rates[0] = 500;

        vm.expectRevert(IForcedTransferable.ArrayLengthMismatch.selector);
        vm.prank(rateManager);
        pyusdx.setEarnerRateBatch(batchAccounts, rates);
    }

    /* ============ claimFor (fee and recipient paths) ============ */

    function test_claimFor_withFee() public {
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 1000, address(0));

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);

        vm.warp(block.timestamp + 365 days);

        uint240 expectedYield = pyusdx.accruedYieldOf(alice);
        assertGt(expectedYield, 0);

        uint240 expectedFee = uint240((uint256(expectedYield) * 1000) / 10_000);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 earnerManagerBalanceBefore = pyusdx.balanceOf(earnerManager);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        uint240 claimed = pyusdx.claimFor(alice);

        assertEq(claimed, expectedYield);
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore + expectedYield - expectedFee);
        assertEq(pyusdx.balanceOf(earnerManager), earnerManagerBalanceBefore + expectedFee);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + expectedYield);
    }

    function test_claimFor_withFeeAndClaimRecipient() public {
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);

        vm.warp(block.timestamp + 365 days);

        uint240 expectedYield = pyusdx.accruedYieldOf(alice);
        assertGt(expectedYield, 0);

        uint240 expectedFee = uint240((uint256(expectedYield) * 500) / 10_000);
        uint240 expectedNetYield = expectedYield - expectedFee;

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 earnerManagerBalanceBefore = pyusdx.balanceOf(earnerManager);

        vm.expectEmit();
        emit IPYUSDX.Claimed(alice, bob, expectedYield);

        pyusdx.claimFor(alice);

        // Alice: yield minted then fee + net yield transferred out
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + expectedNetYield);
        assertEq(pyusdx.balanceOf(earnerManager), earnerManagerBalanceBefore + expectedFee);
    }

    function test_claimFor_withClaimRecipient_noFee() public {
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, bob);

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);

        vm.warp(block.timestamp + 365 days);

        uint240 expectedYield = pyusdx.accruedYieldOf(alice);
        assertGt(expectedYield, 0);

        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint256 earnerManagerBalanceBefore = pyusdx.balanceOf(earnerManager);

        pyusdx.claimFor(alice);

        // Alice: yield minted then full yield transferred to bob
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBefore);
        assertEq(pyusdx.balanceOf(bob), bobBalanceBefore + expectedYield);
        assertEq(pyusdx.balanceOf(earnerManager), earnerManagerBalanceBefore);
    }

    function test_claimFor_zeroYield() public {
        minterGateway.mint(alice, 1000e6);

        // Enable earning but don't set a rate (rate stays 0, no yield accrues)
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        uint240 claimed = pyusdx.claimFor(alice);

        assertEq(claimed, 0);
        assertEq(pyusdx.balanceOf(alice), balanceBefore);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    function test_claimFor_nonEarner() public {
        minterGateway.mint(alice, 1000e6);

        uint256 balanceBefore = pyusdx.balanceOf(alice);
        uint256 totalSupplyBefore = pyusdx.totalSupply();

        uint240 claimed = pyusdx.claimFor(alice);

        assertEq(claimed, 0);
        assertEq(pyusdx.balanceOf(alice), balanceBefore);
        assertEq(pyusdx.totalSupply(), totalSupplyBefore);
    }

    /* ============ Per-account index isolation ============ */

    function test_perAccountIndexIsolation() public {
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(bob, true, 0, address(0));

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);
        vm.prank(rateManager);
        pyusdx.setEarnerRate(bob, 1000);

        vm.warp(block.timestamp + 365 days);

        uint128 aliceIndex = pyusdx.currentAccountIndex(alice);
        uint128 bobIndex = pyusdx.currentAccountIndex(bob);

        assertTrue(aliceIndex != bobIndex, "Indices should differ with different rates");
        assertTrue(bobIndex > aliceIndex, "Higher rate should produce higher index");

        // Changing alice's rate should NOT affect bob's index
        uint128 bobIndexBefore = bobIndex;

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 2000);

        assertEq(pyusdx.currentAccountIndex(bob), bobIndexBefore, "Bob's index unchanged");
    }

    /* ============ setEarningDetails: yield claim on update ============ */

    function test_setEarningDetails_claimsYieldOnUpdate() public {
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 0, address(0));

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 500);

        vm.warp(block.timestamp + 365 days);

        uint240 expectedYield = pyusdx.accruedYieldOf(alice);
        assertGt(expectedYield, 0);

        uint256 balanceBefore = pyusdx.balanceOf(alice);

        // Updating feeRate triggers _claim internally (using old feeRate=0)
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, address(0));

        assertEq(pyusdx.balanceOf(alice), balanceBefore + expectedYield);
        assertEq(pyusdx.accruedYieldOf(alice), 0);

        (, , uint16 feeRate, ) = pyusdx.getEarningDetails(alice);
        assertEq(feeRate, 500);
    }

    /* ============ setEarningDetails: disable earning clears all fields ============ */

    function test_setEarningDetails_disableEarning_clearsAllFields() public {
        uint256 balance = 1000e6;
        minterGateway.mint(alice, balance);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, true, 500, bob);

        vm.prank(rateManager);
        pyusdx.setEarnerRate(alice, 1000);

        vm.warp(block.timestamp + 365 days);

        assertTrue(pyusdx.isEarning(alice));
        assertGt(pyusdx.earningPrincipalOf(alice), 0);
        assertGt(pyusdx.accruedYieldOf(alice), 0);

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(alice, false, 0, address(0));

        (bool isEarning, address manager, uint16 feeRate, address claimRecipient) = pyusdx.getEarningDetails(alice);
        assertFalse(isEarning);
        assertEq(manager, address(0));
        assertEq(feeRate, 0);
        assertEq(claimRecipient, address(0));
        assertEq(pyusdx.earningPrincipalOf(alice), 0);
        assertEq(pyusdx.currentAccountIndex(alice), uint128(PRECISION));
    }
}
