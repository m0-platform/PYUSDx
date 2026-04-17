// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { PausableUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";
import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";
import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

contract YieldToOneIntegrationTests is IntegrationForkTest {
    YieldToOne public yieldToOne;

    uint256 public constant AMOUNT = 1000e6;

    function setUp() public override {
        super.setUp();

        // Deploy YieldToOne through factory
        IExtensionFactory.YieldToOneParams memory ytoParams = IExtensionFactory.YieldToOneParams({
            name: "YieldToOne",
            symbol: "YTO",
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        vm.prank(admin);
        (address yieldToOneProxy, ) = factory.deployYieldToOne(string("yto-integration"), ytoParams);
        yieldToOne = YieldToOne(yieldToOneProxy);

        // Enable earning for YieldToOne (claimRecipient = address(0) means yield stays on the contract)
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(yieldToOne), 500, 0, address(0));
    }

    /// @dev Mints PYUSDX, approves swap facility, and swaps in to wrap for user
    function _wrapFor(address user, uint256 amount) internal {
        _mintPYUSDX(user, amount);

        vm.prank(user);
        IERC20(address(pyusdx)).approve(address(swapFacility), amount);

        vm.prank(user);
        swapFacility.swapIn(address(yieldToOne), amount, user);
    }

    /* ============ claimYield ============ */

    function testIntegration_claimYield() public {
        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        uint256 recipientBalanceBefore = yieldToOne.balanceOf(yieldRecipient);
        uint256 totalSupplyBefore = yieldToOne.totalSupply();

        vm.prank(yieldRecipientManager);
        uint256 claimed = yieldToOne.claimYield();

        assertGt(claimed, 0);
        assertEq(yieldToOne.balanceOf(yieldRecipient), recipientBalanceBefore + claimed);
        assertEq(yieldToOne.totalSupply(), totalSupplyBefore + claimed);
        assertEq(yieldToOne.yield(), 0);
        assertEq(pyusdx.balanceOf(address(yieldToOne)), AMOUNT + claimed);
    }

    function testIntegration_claimYield_withFee() public {
        // Re-configure earning with a 10% fee (claimRecipient = address(0) means yield stays on contract)
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(yieldToOne), 500, 1000, address(0));

        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        // Fee goes to earnerManager at the PYUSDX level
        uint256 earnerManagerPyusdxBefore = pyusdx.balanceOf(earnerManager);

        (uint256 grossYield, , ) = pyusdx.accruedYieldAndFeeOf(address(yieldToOne));

        vm.prank(yieldRecipientManager);
        uint256 claimed = yieldToOne.claimYield();

        assertGt(claimed, 0);

        // earnerManager should have received PYUSDX fee
        uint256 feeReceived = pyusdx.balanceOf(earnerManager) - earnerManagerPyusdxBefore;
        assertGt(feeReceived, 0);

        // claimed + feeReceived should equal the gross yield
        assertEq(claimed + feeReceived, grossYield);

        // Yield recipient gets extension tokens (net of PYUSDX-level fee)
        assertEq(yieldToOne.balanceOf(yieldRecipient), claimed);
    }

    function testIntegration_claimYield_excessFromDirectTransfer() public {
        _wrapFor(alice, AMOUNT);

        // Send additional PYUSDX directly to extension (bypass swap)
        uint256 extraAmount = 500e6;
        _mintPYUSDX(bob, extraAmount);

        vm.prank(bob);
        IERC20(address(pyusdx)).transfer(address(yieldToOne), extraAmount);

        // yield() should reflect the excess
        assertEq(yieldToOne.yield(), extraAmount);

        vm.prank(yieldRecipientManager);
        uint256 claimed = yieldToOne.claimYield();

        // Should recover excess to recipient
        assertEq(claimed, extraAmount);
        assertEq(yieldToOne.yield(), 0);
    }

    function testIntegration_claimYield_excessFromClaimForBypass() public {
        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        // Store yield before claimFor
        uint256 yieldBefore = yieldToOne.yield();
        assertGt(yieldBefore, 0);

        // Call claimFor directly on PYUSDX — realizes yield but doesn't mint extension tokens
        pyusdx.claimFor(address(yieldToOne));

        // yield() should reflect realized but unminted yield — same value, shifted from accrued to excess
        uint256 yieldAfterClaim = yieldToOne.yield();
        assertEq(yieldAfterClaim, yieldBefore);
        assertGt(yieldAfterClaim, 0);

        vm.prank(yieldRecipientManager);
        uint256 claimed = yieldToOne.claimYield();

        assertEq(claimed, yieldAfterClaim);
        assertEq(yieldToOne.yield(), 0);
    }

    function testIntegration_setYieldRecipient() public {
        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        // Change recipient — this auto-claims yield for old recipient
        address newRecipient = makeAddr("newRecipient");

        vm.prank(yieldRecipientManager);
        yieldToOne.setYieldRecipient(newRecipient);

        // Old recipient should have received auto-claimed yield
        assertGt(yieldToOne.balanceOf(yieldRecipient), 0);

        // New recipient is set
        assertEq(yieldToOne.yieldRecipient(), newRecipient);

        // Warp again, claim, and assert new recipient gets subsequent yield
        vm.warp(block.timestamp + 365 days);

        uint256 newRecipientBefore = yieldToOne.balanceOf(newRecipient);

        vm.prank(yieldRecipientManager);
        uint256 claimed = yieldToOne.claimYield();

        assertEq(yieldToOne.balanceOf(newRecipient), newRecipientBefore + claimed);
    }

    /* ============ yield ============ */

    function testIntegration_yield_accruesOverTime() public {
        _wrapFor(alice, AMOUNT);

        assertEq(yieldToOne.yield(), 0);

        vm.warp(block.timestamp + 365 days);

        assertGt(yieldToOne.yield(), 0);
    }

    function testIntegration_yield_zeroWhenYieldRedirected() public {
        _wrapFor(alice, AMOUNT);

        // Redirect PYUSDX yield to alice (not to self)
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(yieldToOne), 500, 0, alice);

        vm.warp(block.timestamp + 365 days);

        // PYUSDX accrued yield exists but it's redirected away from self
        assertGt(pyusdx.accruedYieldOf(address(yieldToOne)), 0);
        assertEq(pyusdx.accruedYieldToSelfOf(address(yieldToOne)), 0);

        // YieldToOne.yield() should be 0 since accruedYieldToSelfOf is 0 and no excess
        assertEq(yieldToOne.yield(), 0);
    }

    /* ============ freeze ============ */

    function testIntegration_freeze_blocksWrap() public {
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(freezeManager);
        yieldToOne.freeze(alice);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);
    }

    function testIntegration_freeze_blocksUnwrap() public {
        _wrapFor(alice, AMOUNT);

        // Approve before freezing (freeze blocks approve too)
        vm.prank(alice);
        IERC20(address(yieldToOne)).approve(address(swapFacility), AMOUNT);

        vm.prank(freezeManager);
        yieldToOne.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        swapFacility.swapOut(address(yieldToOne), AMOUNT, alice);
    }

    function testIntegration_unfreeze_resumesOperations() public {
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(freezeManager);
        yieldToOne.freeze(alice);

        // Swap should fail while frozen
        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        // Unfreeze and swap should succeed
        vm.prank(freezeManager);
        yieldToOne.unfreeze(alice);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        assertEq(yieldToOne.balanceOf(alice), AMOUNT);
    }

    /* ============ pause ============ */

    function testIntegration_pause_blocksWrap() public {
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(pauser);
        yieldToOne.pause();

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);
    }

    function testIntegration_pause_claimYieldSucceeds() public {
        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        vm.prank(pauser);
        yieldToOne.pause();

        // claimYield is intentionally callable during pause so the admin can still
        // rotate the yield recipient mid-incident via setYieldRecipient. Minted tokens
        // are inert because transfer/wrap/unwrap all block while paused.
        vm.prank(yieldRecipientManager);
        uint256 claimed = yieldToOne.claimYield();
        assertGt(claimed, 0);
    }

    /* ============ complex scenarios ============ */

    function testIntegration_claimYield_afterPartialUnwrap() public {
        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        // Claim yield accrued on full balance
        vm.prank(yieldRecipientManager);
        uint256 yieldFromFullBalance = yieldToOne.claimYield();
        assertGt(yieldFromFullBalance, 0);

        // Unwrap half — alice approves extension tokens, then swaps out
        uint256 unwrapAmount = 500e6;

        vm.prank(alice);
        IERC20(address(yieldToOne)).approve(address(swapFacility), unwrapAmount);

        vm.prank(alice);
        swapFacility.swapOut(address(yieldToOne), unwrapAmount, alice);

        // Yield now accrues on ~500e6
        vm.warp(block.timestamp + 365 days);

        vm.prank(yieldRecipientManager);
        uint256 yieldFromHalfBalance = yieldToOne.claimYield();
        assertGt(yieldFromHalfBalance, 0);

        // Yield from half balance should be less than yield from full balance
        assertLt(yieldFromHalfBalance, yieldFromFullBalance);

        // All yield claimed
        assertEq(yieldToOne.yield(), 0);
    }

    function testIntegration_claimYield_multipleWrapsAccumulateYield() public {
        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 180 days);

        // Claim yield from first period (1000e6 for 180 days)
        vm.prank(yieldRecipientManager);
        uint256 yieldFirstHalf = yieldToOne.claimYield();
        assertGt(yieldFirstHalf, 0);

        // Second deposit doubles the earning base
        _wrapFor(bob, AMOUNT);

        vm.warp(block.timestamp + 180 days);

        // Claim yield from second period (2000e6 for 180 days)
        vm.prank(yieldRecipientManager);
        uint256 yieldSecondHalf = yieldToOne.claimYield();
        assertGt(yieldSecondHalf, 0);

        // Double the principal for same duration ≈ double the yield
        assertGt(yieldSecondHalf, yieldFirstHalf);

        // Both users still hold their tokens
        assertEq(yieldToOne.balanceOf(alice), AMOUNT);
        assertEq(yieldToOne.balanceOf(bob), AMOUNT);

        // Yield recipient holds the sum of both claims
        assertEq(yieldToOne.balanceOf(yieldRecipient), yieldFirstHalf + yieldSecondHalf);
    }

    function testIntegration_freeze_recipientBlocksWrapToRecipient() public {
        _mintPYUSDX(alice, AMOUNT);

        // Freeze the recipient, not the caller
        vm.prank(freezeManager);
        yieldToOne.freeze(bob);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        // _beforeWrap checks _revertIfFrozen on the recipient
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, bob);
    }

    function testIntegration_claimYield_afterExtensionRevoked() public {
        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        // Revoke the extension
        vm.prank(factoryManager);
        factory.setExtensionType(address(yieldToOne), IExtensionBeacon.ExtensionType.NONE);

        assertFalse(swapFacility.isApprovedExtension(address(yieldToOne)));

        // claimYield bypasses SwapFacility — should still succeed
        vm.prank(yieldRecipientManager);
        uint256 claimed = yieldToOne.claimYield();
        assertGt(claimed, 0);

        // New wraps are blocked
        _mintPYUSDX(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, address(yieldToOne)));

        vm.prank(bob);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, bob);
    }

    function testIntegration_claimYield_afterPyusdxClaimRecipientRedirected() public {
        _wrapFor(alice, AMOUNT);

        vm.warp(block.timestamp + 365 days);

        // Redirect claimRecipient to carol — internally calls _claimFor(yto) under old config first
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(yieldToOne), 500, 0, carol);

        // Pre-redirect yield was realized to YTO (old config was self), capture it
        uint256 expectedExcess = pyusdx.balanceOf(address(yieldToOne)) - yieldToOne.totalSupply();

        vm.prank(yieldRecipientManager);
        uint256 preRedirectYield = yieldToOne.claimYield();
        assertEq(preRedirectYield, expectedExcess);

        // New yield accrues under redirected config
        vm.warp(block.timestamp + 365 days);

        // YTO sees no yield — claimRecipient != self and no excess
        assertEq(yieldToOne.yield(), 0);

        // claimYield returns 0
        vm.prank(yieldRecipientManager);
        uint256 leaked = yieldToOne.claimYield();
        assertEq(leaked, 0);

        // Realize the redirected yield at PYUSDX level
        pyusdx.claimFor(address(yieldToOne));

        // Carol received the redirected yield, not YTO
        assertGt(pyusdx.balanceOf(carol), 0);
    }
}
