// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IssuerGatewayBaseUnitTest } from "../utils/IssuerGatewayBaseUnitTest.sol";
import { IIssuerGateway } from "../../src/core/IIssuerGateway.sol";
import { IRateLimiter } from "../../src/abstract/interfaces/IRateLimiter.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IssuerGateway } from "../../src/core/IssuerGateway.sol";

contract IssuerGatewayUnitTest is IssuerGatewayBaseUnitTest {
    /* ============ Constructor ============ */

    function test_constructor_revertIfZeroPYUSDX() public {
        vm.expectRevert(IIssuerGateway.ZeroPYUSDX.selector);
        new IssuerGateway(address(0));
    }

    function test_constructor() public view {
        assertEq(issuerGateway.pyusdx(), address(pyusdx));
    }

    /* ============ Initialize ============ */

    function test_initialize_revertIfZeroAdmin() public {
        IssuerGateway newImpl = new IssuerGateway(address(pyusdx));

        vm.expectRevert(IIssuerGateway.ZeroAdmin.selector);
        UnsafeUpgrades.deployTransparentProxy(
            address(newImpl),
            admin,
            abi.encodeWithSelector(
                IssuerGateway.initialize.selector,
                address(0), // zero admin
                minter,
                rateLimitManager,
                DEFAULT_MINT_DELAY,
                DEFAULT_MINT_TTL
            )
        );
    }

    function test_initialize_revertIfZeroIssuer() public {
        IssuerGateway newImpl = new IssuerGateway(address(pyusdx));

        vm.expectRevert(IIssuerGateway.ZeroIssuer.selector);
        UnsafeUpgrades.deployTransparentProxy(
            address(newImpl),
            admin,
            abi.encodeWithSelector(
                IssuerGateway.initialize.selector,
                admin,
                address(0), // zero issuer
                rateLimitManager,
                DEFAULT_MINT_DELAY,
                DEFAULT_MINT_TTL
            )
        );
    }

    function test_initialize_revertIfCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        issuerGateway.initialize(admin, minter, rateLimitManager, DEFAULT_MINT_DELAY, DEFAULT_MINT_TTL);
    }

    function test_initialize_revertIfZeroMintTTL() public {
        IssuerGateway newImpl = new IssuerGateway(address(pyusdx));

        vm.expectRevert(IIssuerGateway.ZeroMintTTL.selector);
        UnsafeUpgrades.deployTransparentProxy(
            address(newImpl),
            admin,
            abi.encodeWithSelector(
                IssuerGateway.initialize.selector,
                admin,
                minter,
                rateLimitManager,
                DEFAULT_MINT_DELAY,
                0 // zero TTL
            )
        );
    }

    function test_initialize() public view {
        assertTrue(issuerGateway.hasRole(issuerGateway.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(issuerGateway.hasRole(issuerGateway.ISSUER_ROLE(), minter));
        assertTrue(issuerGateway.hasRole(issuerGateway.RATE_LIMIT_MANAGER_ROLE(), rateLimitManager));
        assertEq(issuerGateway.mintDelay(), DEFAULT_MINT_DELAY);
        assertEq(issuerGateway.mintTTL(), DEFAULT_MINT_TTL);
    }

    /* ============ proposeMint ============ */

    function test_proposeMint_revertIfNotMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                issuerGateway.ISSUER_ROLE()
            )
        );

        vm.prank(other);
        issuerGateway.proposeMint(100, recipient);
    }

    function test_proposeMint_revertIfZeroAmount() public {
        vm.expectRevert(IIssuerGateway.ZeroMintAmount.selector);

        vm.prank(minter);
        issuerGateway.proposeMint(0, recipient);
    }

    function test_proposeMint_revertIfZeroRecipient() public {
        vm.expectRevert(IIssuerGateway.ZeroMintRecipient.selector);

        vm.prank(minter);
        issuerGateway.proposeMint(100, address(0));
    }

    function test_proposeMint() public {
        uint40 activeAt = uint40(block.timestamp) + DEFAULT_MINT_DELAY;
        uint40 expiresAt = activeAt + DEFAULT_MINT_TTL;

        vm.expectEmit();
        emit IIssuerGateway.MintProposed(1, minter, 100, recipient, activeAt, expiresAt);

        vm.prank(minter);
        uint48 mintId = issuerGateway.proposeMint(100, recipient);

        assertEq(mintId, 1);
        assertEq(issuerGateway.mintNonce(), 1);

        (uint40 createdAt, address storedMinter, address storedRecipient, uint256 storedAmount) = issuerGateway
            .getMintProposal(mintId);

        assertEq(createdAt, block.timestamp);
        assertEq(storedMinter, minter);
        assertEq(storedRecipient, recipient);
        assertEq(storedAmount, 100);
    }

    function test_proposeMint_multipleProposalsUniqueIds() public {
        vm.startPrank(minter);

        uint48 mintId1 = issuerGateway.proposeMint(100, recipient);
        uint48 mintId2 = issuerGateway.proposeMint(200, recipient);
        uint48 mintId3 = issuerGateway.proposeMint(300, recipient);

        vm.stopPrank();

        assertEq(mintId1, 1);
        assertEq(mintId2, 2);
        assertEq(mintId3, 3);
        assertEq(issuerGateway.mintNonce(), 3);

        // All proposals should be stored independently
        (, , , uint256 amount1) = issuerGateway.getMintProposal(1);
        (, , , uint256 amount2) = issuerGateway.getMintProposal(2);
        (, , , uint256 amount3) = issuerGateway.getMintProposal(3);

        assertEq(amount1, 100);
        assertEq(amount2, 200);
        assertEq(amount3, 300);
    }

    /* ============ mint ============ */

    function test_mint_revertIfInvalidProposal() public {
        vm.expectRevert(IIssuerGateway.InvalidMintProposal.selector);
        issuerGateway.mint(999);
    }

    function test_mint_revertIfPending() public {
        uint48 mintId = _proposeMint(100, recipient);
        uint40 activeAt = uint40(block.timestamp) + DEFAULT_MINT_DELAY;

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.PendingMintProposal.selector, activeAt));
        issuerGateway.mint(mintId);
    }

    function test_mint_revertIfExpired() public {
        uint48 mintId = _proposeMint(100, recipient);
        uint40 expiresAt = _warpToExpired(mintId);

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.ExpiredMintProposal.selector, expiresAt));
        issuerGateway.mint(mintId);
    }

    function test_mint_successAtTTLBoundary() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Warp to exact TTL boundary (activeAt + TTL)
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);
        vm.warp(createdAt + DEFAULT_MINT_DELAY + DEFAULT_MINT_TTL);

        issuerGateway.mint(mintId);
        assertEq(pyusdx.balanceOf(recipient), 100);
    }

    function test_mint() public {
        uint48 mintId = _proposeMint(100, recipient);
        _warpToMintable(mintId);

        vm.expectEmit();
        emit IIssuerGateway.MintExecuted(mintId, caller, 100, recipient);

        vm.prank(caller);
        issuerGateway.mint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);

        assertEq(pyusdx.balanceOf(recipient), 100);
    }

    /* ============ burn ============ */

    function test_burn_revertIfNotMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                issuerGateway.ISSUER_ROLE()
            )
        );

        vm.prank(other);
        issuerGateway.burn(100);
    }

    function test_burn_revertIfZeroAmount() public {
        vm.prank(minter);
        vm.expectRevert(IIssuerGateway.ZeroBurnAmount.selector);
        issuerGateway.burn(0);
    }

    function test_burn() public {
        // First mint some tokens to the minter
        uint48 mintId = _proposeMint(100, minter);
        _warpToMintable(mintId);
        issuerGateway.mint(mintId);

        uint256 balanceBefore = pyusdx.balanceOf(minter);
        assertEq(balanceBefore, 100);

        vm.expectEmit();
        emit IIssuerGateway.BurnExecuted(minter, 50);

        vm.prank(minter);
        issuerGateway.burn(50);

        assertEq(pyusdx.balanceOf(minter), 50);
    }

    /* ============ cancelMint ============ */

    function test_cancelMint_revertIfInvalidProposal() public {
        vm.expectRevert(IIssuerGateway.InvalidMintProposal.selector);
        issuerGateway.cancelMint(999);
    }

    function test_cancelMint_revertIfNotCreator() public {
        uint48 mintId = _proposeMint(100, recipient);

        vm.expectRevert(IIssuerGateway.NotMintProposalCreator.selector);

        vm.prank(other);
        issuerGateway.cancelMint(mintId);
    }

    function test_cancelMint_revertIfActive() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Warp to when the proposal becomes active (at activeAt boundary)
        _warpToMintable(mintId);

        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);
        uint40 activeAt = createdAt + DEFAULT_MINT_DELAY;

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.ActiveMintProposal.selector, activeAt));

        vm.prank(minter);
        issuerGateway.cancelMint(mintId);
    }

    function test_cancelMint_revertIfActive_afterDelay() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Warp to after the delay has passed but before TTL expires
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);

        uint40 activeAt = createdAt + DEFAULT_MINT_DELAY;
        vm.warp(activeAt + 1 hours);

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.ActiveMintProposal.selector, activeAt));

        vm.prank(minter);
        issuerGateway.cancelMint(mintId);
    }

    function test_cancelMint() public {
        uint48 mintId = _proposeMint(100, recipient);

        vm.expectEmit();
        emit IIssuerGateway.MintCanceled(mintId, minter);

        vm.prank(minter);
        issuerGateway.cancelMint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);
    }

    function test_cancelMint_successAfterRoleRevoked() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Revoke minter role using admin's DEFAULT_ADMIN_ROLE
        // Note: Using vm.prank with admin who has DEFAULT_ADMIN_ROLE
        vm.startPrank(admin);
        issuerGateway.revokeRole(issuerGateway.ISSUER_ROLE(), minter);
        vm.stopPrank();

        // Verify minter no longer has the role
        assertFalse(issuerGateway.hasRole(issuerGateway.ISSUER_ROLE(), minter));
        // Minter can still cancel their own proposal (cancel doesn't require MINTER_ROLE)
        // This must happen while proposal is still pending (before activeAt)
        vm.prank(minter);
        issuerGateway.cancelMint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);
    }

    /* ============ View Functions ============ */

    function test_getMintProposal_returnsZeroForNonExistent() public view {
        (uint40 createdAt, address minter_, address recipient_, uint256 amount) = issuerGateway.getMintProposal(999);

        assertEq(createdAt, 0);
        assertEq(minter_, address(0));
        assertEq(recipient_, address(0));
        assertEq(amount, 0);
    }

    function test_getMintProposal() public {
        uint48 mintId = _proposeMint(100, recipient);

        (uint40 createdAt, address minter_, address recipient_, uint256 amount) = issuerGateway.getMintProposal(mintId);

        assertEq(createdAt, block.timestamp);
        assertEq(minter_, minter);
        assertEq(recipient_, recipient);
        assertEq(amount, 100);
    }

    function test_mintDelay() public view {
        assertEq(issuerGateway.mintDelay(), DEFAULT_MINT_DELAY);
    }

    function test_mintTTL() public view {
        assertEq(issuerGateway.mintTTL(), DEFAULT_MINT_TTL);
    }

    /* ============ Admin Functions ============ */

    function test_setMintDelay_revertIfNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                issuerGateway.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(other);
        issuerGateway.setMintDelay(2 days);
    }

    function test_setMintDelay() public {
        vm.expectEmit();
        emit IIssuerGateway.MintDelaySet(2 days);

        vm.prank(admin);
        issuerGateway.setMintDelay(2 days);

        assertEq(issuerGateway.mintDelay(), 2 days);
    }

    function test_setMintTTL_revertIfNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                issuerGateway.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(other);
        issuerGateway.setMintTTL(14 days);
    }

    function test_setMintTTL_revertIfZero() public {
        vm.expectRevert(IIssuerGateway.ZeroMintTTL.selector);

        vm.prank(admin);
        issuerGateway.setMintTTL(0);
    }

    function test_setMintTTL() public {
        vm.expectEmit();
        emit IIssuerGateway.MintTTLSet(14 days);

        vm.prank(admin);
        issuerGateway.setMintTTL(14 days);

        assertEq(issuerGateway.mintTTL(), 14 days);
    }

    /* ============ Rate Limiting ============ */

    function test_setRateLimit_revertIfNotManager() public {
        vm.expectRevert();
        issuerGateway.setRateLimit(minter, 100e6, 10e6, true);
    }

    function test_setRateLimit() public {
        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, 100e6, 10e6, true);

        (uint256 capacity, uint256 refillPerSecond) = issuerGateway.getRateLimitConfig(minter);

        assertEq(capacity, 100e6);
        assertEq(refillPerSecond, 10e6);
        assertEq(issuerGateway.getRemainingAmount(minter), 100e6);
    }

    function test_mint_consumesRateLimit() public {
        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, 100e6, 0, true);

        uint48 mintId = _proposeMint(30e6, recipient);
        _warpToMintable(mintId);
        issuerGateway.mint(mintId);

        assertEq(issuerGateway.getRemainingAmount(minter), 70e6);
    }

    function test_mint_revertIfRateLimitExceeded() public {
        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, 100e6, 0, true);

        // First mint: 60e6
        uint48 mintId1 = _proposeMint(60e6, recipient);
        _warpToMintable(mintId1);
        issuerGateway.mint(mintId1);

        assertEq(issuerGateway.getRemainingAmount(minter), 40e6);

        // Second mint: 50e6 should exceed the remaining 40e6
        uint48 mintId2 = _proposeMint(50e6, recipient);
        _warpToMintable(mintId2);

        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, 50e6, 40e6));
        issuerGateway.mint(mintId2);
    }

    function test_mint_rateLimitRefillsBetweenMints() public {
        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, 100e6, 10e6, true); // 10e6 per second

        // Propose both mints upfront so they share the same mint window
        uint48 mintId1 = _proposeMint(80e6, recipient);
        uint48 mintId2 = _proposeMint(70e6, recipient);

        _warpToMintable(mintId1);

        // First mint: consume 80e6
        issuerGateway.mint(mintId1);
        assertEq(issuerGateway.getRemainingAmount(minter), 20e6);

        // Warp 5 seconds → refill = 5 * 10e6 = 50e6 → remaining = 70e6
        vm.warp(block.timestamp + 5);
        assertEq(issuerGateway.getRemainingAmount(minter), 70e6);

        // Second mint: 70e6 should succeed exactly
        issuerGateway.mint(mintId2);
        assertEq(issuerGateway.getRemainingAmount(minter), 0);
    }

    function test_mint_noRateLimitForUnconfiguredIssuer() public {
        // No rate limit set for minter - should mint without restrictions
        uint48 mintId = _proposeMint(type(uint128).max, recipient);
        _warpToMintable(mintId);
        issuerGateway.mint(mintId);

        assertEq(pyusdx.balanceOf(recipient), type(uint128).max);
    }

    function test_burn_notRateLimited() public {
        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, 100e6, 0, true);

        // Mint some tokens to the minter
        uint48 mintId = _proposeMint(100e6, minter);
        _warpToMintable(mintId);
        issuerGateway.mint(mintId);

        assertEq(issuerGateway.getRemainingAmount(minter), 0);

        // Burn should succeed even though rate limit is fully consumed
        vm.prank(minter);
        issuerGateway.burn(50e6);

        assertEq(pyusdx.balanceOf(minter), 50e6);
    }

    function test_proposeMint_notRateLimited() public {
        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, 100e6, 0, true);

        // Consume entire rate limit
        uint48 mintId1 = _proposeMint(100e6, recipient);
        _warpToMintable(mintId1);
        issuerGateway.mint(mintId1);

        assertEq(issuerGateway.getRemainingAmount(minter), 0);

        // proposeMint should still succeed (rate limit only checked on mint execution)
        vm.prank(minter);
        uint48 mintId2 = issuerGateway.proposeMint(50e6, recipient);
        assertGt(mintId2, 0);
    }

    function test_mint_rateLimitExactBoundary() public {
        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, 100e6, 0, true);

        // Mint exactly the capacity
        uint48 mintId = _proposeMint(100e6, recipient);
        _warpToMintable(mintId);
        issuerGateway.mint(mintId);

        assertEq(issuerGateway.getRemainingAmount(minter), 0);

        // Next mint of even 1 wei should fail
        uint48 mintId2 = _proposeMint(1, recipient);
        _warpToMintable(mintId2);

        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, 1, 0));
        issuerGateway.mint(mintId2);
    }

    function test_mint_rateLimitMultipleConsecutiveMints() public {
        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, 100e6, 0, true);

        // First mint
        uint48 mintId1 = _proposeMint(30e6, recipient);
        _warpToMintable(mintId1);
        issuerGateway.mint(mintId1);
        assertEq(issuerGateway.getRemainingAmount(minter), 70e6);

        // Second mint
        uint48 mintId2 = _proposeMint(20e6, recipient);
        _warpToMintable(mintId2);
        issuerGateway.mint(mintId2);
        assertEq(issuerGateway.getRemainingAmount(minter), 50e6);

        // Third mint
        uint48 mintId3 = _proposeMint(50e6, recipient);
        _warpToMintable(mintId3);
        issuerGateway.mint(mintId3);
        assertEq(issuerGateway.getRemainingAmount(minter), 0);
    }

    /* ============ Rate Limiting Fuzz ============ */

    function testFuzz_mint_rateLimitConsumption(uint256 capacity, uint256 mintAmount) public {
        capacity = bound(capacity, 1, type(uint128).max);
        mintAmount = bound(mintAmount, 1, capacity);

        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, capacity, 0, true);

        uint48 mintId = _proposeMint(mintAmount, recipient);
        _warpToMintable(mintId);
        issuerGateway.mint(mintId);

        assertEq(issuerGateway.getRemainingAmount(minter), capacity - mintAmount);
        assertEq(pyusdx.balanceOf(recipient), mintAmount);
    }

    function testFuzz_mint_rateLimitExceeded(uint256 capacity, uint256 mintAmount) public {
        capacity = bound(capacity, 1, type(uint128).max - 1);
        mintAmount = bound(mintAmount, capacity + 1, type(uint128).max);

        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, capacity, 0, true);

        uint48 mintId = _proposeMint(mintAmount, recipient);
        _warpToMintable(mintId);

        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, mintAmount, capacity));
        issuerGateway.mint(mintId);
    }

    function testFuzz_mint_rateLimitWithRefill(
        uint256 capacity,
        uint256 firstMint,
        uint256 refillPerSecond,
        uint256 elapsedSeconds
    ) public {
        capacity = bound(capacity, 2, type(uint128).max);
        firstMint = bound(firstMint, 1, capacity);
        refillPerSecond = bound(refillPerSecond, 1, capacity);
        elapsedSeconds = bound(elapsedSeconds, 1, 365 days);

        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, capacity, refillPerSecond, true);

        // First mint
        uint48 mintId1 = _proposeMint(firstMint, recipient);
        _warpToMintable(mintId1);
        issuerGateway.mint(mintId1);

        uint256 remainingAfterMint = capacity - firstMint;

        // Time passes for refill
        vm.warp(block.timestamp + elapsedSeconds);

        uint256 refillAmount = elapsedSeconds * refillPerSecond;
        uint256 expectedRemaining;
        if (refillAmount > type(uint256).max - remainingAfterMint) {
            expectedRemaining = capacity; // overflow case, caps at capacity
        } else {
            expectedRemaining = remainingAfterMint + refillAmount;
            if (expectedRemaining > capacity) expectedRemaining = capacity;
        }

        assertEq(issuerGateway.getRemainingAmount(minter), expectedRemaining);
    }

    function testFuzz_setRateLimit(uint256 capacity, uint256 refillPerSecond) public {
        capacity = bound(capacity, 1, type(uint256).max);
        refillPerSecond = bound(refillPerSecond, 0, type(uint256).max);

        vm.prank(rateLimitManager);
        issuerGateway.setRateLimit(minter, capacity, refillPerSecond, true);

        (uint256 storedCapacity, uint256 storedRefill) = issuerGateway.getRateLimitConfig(minter);

        assertEq(storedCapacity, capacity);
        assertEq(storedRefill, refillPerSecond);
        assertEq(issuerGateway.getRemainingAmount(minter), capacity);
    }

    function testFuzz_proposeMint(uint256 amount, address recipient_) public {
        vm.assume(recipient_ != address(0));
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(minter);
        uint48 mintId = issuerGateway.proposeMint(amount, recipient_);

        assertEq(mintId, 1);

        (uint40 createdAt, address storedMinter, address storedRecipient, uint256 storedAmount) = issuerGateway
            .getMintProposal(mintId);

        assertEq(createdAt, block.timestamp);
        assertEq(storedMinter, minter);
        assertEq(storedRecipient, recipient_);
        assertEq(storedAmount, amount);
    }

    function testFuzz_mint_timing(uint256 warpOffset) public {
        uint48 mintId = _proposeMint(100, recipient);
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);

        uint40 activeAt = createdAt + DEFAULT_MINT_DELAY;
        uint40 expiresAt = activeAt + DEFAULT_MINT_TTL;

        // Bound to valid mint window [activeAt, expiresAt]
        warpOffset = bound(warpOffset, activeAt, expiresAt);
        vm.warp(warpOffset);

        issuerGateway.mint(mintId);
        assertEq(pyusdx.balanceOf(recipient), 100);
    }

    function testFuzz_cancelMint_onlyDuringPending(uint256 warpOffset) public {
        uint48 mintId = _proposeMint(100, recipient);
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);

        uint40 activeAt = createdAt + DEFAULT_MINT_DELAY;

        // Cancel only works before activeAt
        warpOffset = bound(warpOffset, block.timestamp, activeAt - 1);
        vm.warp(warpOffset);

        vm.prank(minter);
        issuerGateway.cancelMint(mintId);

        (uint40 storedCreatedAt, , , ) = issuerGateway.getMintProposal(mintId);
        assertEq(storedCreatedAt, 0);
    }
}
