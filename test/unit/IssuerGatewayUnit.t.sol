// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IssuerGatewayBaseUnitTest } from "../utils/IssuerGatewayBaseUnitTest.sol";
import { IIssuerGateway } from "../../src/core/IIssuerGateway.sol";
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
                operator,
                executor,
                DEFAULT_MINT_DELAY,
                DEFAULT_MINT_TTL
            )
        );
    }

    function test_initialize_revertIfZeroOperator() public {
        IssuerGateway newImpl = new IssuerGateway(address(pyusdx));

        vm.expectRevert(IIssuerGateway.ZeroOperator.selector);
        UnsafeUpgrades.deployTransparentProxy(
            address(newImpl),
            admin,
            abi.encodeWithSelector(
                IssuerGateway.initialize.selector,
                admin,
                address(0), // zero operator
                executor,
                DEFAULT_MINT_DELAY,
                DEFAULT_MINT_TTL
            )
        );
    }

    function test_initialize_revertIfZeroExecutor() public {
        IssuerGateway newImpl = new IssuerGateway(address(pyusdx));

        vm.expectRevert(IIssuerGateway.ZeroExecutor.selector);
        UnsafeUpgrades.deployTransparentProxy(
            address(newImpl),
            admin,
            abi.encodeWithSelector(
                IssuerGateway.initialize.selector,
                admin,
                operator,
                address(0), // zero executor
                DEFAULT_MINT_DELAY,
                DEFAULT_MINT_TTL
            )
        );
    }

    function test_initialize_revertIfCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        issuerGateway.initialize(admin, operator, executor, DEFAULT_MINT_DELAY, DEFAULT_MINT_TTL);
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
                operator,
                executor,
                DEFAULT_MINT_DELAY,
                0 // zero TTL
            )
        );
    }

    function test_initialize() public view {
        assertTrue(issuerGateway.hasRole(issuerGateway.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(issuerGateway.hasRole(issuerGateway.OPERATOR_ROLE(), operator));
        assertTrue(issuerGateway.hasRole(issuerGateway.EXECUTOR_ROLE(), executor));
        assertEq(issuerGateway.mintDelay(), DEFAULT_MINT_DELAY);
        assertEq(issuerGateway.mintTTL(), DEFAULT_MINT_TTL);
    }

    /* ============ proposeMint ============ */

    function test_proposeMint_revertIfNotIssuer() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                issuerGateway.OPERATOR_ROLE()
            )
        );

        vm.prank(other);
        issuerGateway.proposeMint(100, recipient);
    }

    function test_proposeMint_revertIfZeroAmount() public {
        vm.expectRevert(IIssuerGateway.ZeroMintAmount.selector);

        vm.prank(operator);
        issuerGateway.proposeMint(0, recipient);
    }

    function test_proposeMint_revertIfZeroRecipient() public {
        vm.expectRevert(IIssuerGateway.ZeroMintRecipient.selector);

        vm.prank(operator);
        issuerGateway.proposeMint(100, address(0));
    }

    function test_proposeMint() public {
        uint40 activeAt = uint40(block.timestamp) + DEFAULT_MINT_DELAY;
        uint40 expiresAt = activeAt + DEFAULT_MINT_TTL;

        vm.expectEmit();
        emit IIssuerGateway.MintProposed(1, operator, 100, recipient, activeAt, expiresAt);

        vm.prank(operator);
        uint48 mintId = issuerGateway.proposeMint(100, recipient);

        assertEq(mintId, 1);
        assertEq(issuerGateway.mintNonce(), 1);

        (
            uint40 createdAt,
            uint40 storedActiveAt,
            uint40 storedExpiresAt,
            address storedOperator,
            address storedRecipient,
            uint256 storedAmount
        ) = issuerGateway.getMintProposal(mintId);

        assertEq(createdAt, block.timestamp);
        assertEq(storedActiveAt, createdAt + DEFAULT_MINT_DELAY);
        assertEq(storedExpiresAt, storedActiveAt + DEFAULT_MINT_TTL);
        assertEq(storedOperator, operator);
        assertEq(storedRecipient, recipient);
        assertEq(storedAmount, 100);
    }

    function test_proposeMint_multipleProposalsUniqueIds() public {
        vm.startPrank(operator);

        uint48 mintId1 = issuerGateway.proposeMint(100, recipient);
        uint48 mintId2 = issuerGateway.proposeMint(200, recipient);
        uint48 mintId3 = issuerGateway.proposeMint(300, recipient);

        vm.stopPrank();

        assertEq(mintId1, 1);
        assertEq(mintId2, 2);
        assertEq(mintId3, 3);
        assertEq(issuerGateway.mintNonce(), 3);

        // All proposals should be stored independently
        (, , , , , uint256 amount1) = issuerGateway.getMintProposal(1);
        (, , , , , uint256 amount2) = issuerGateway.getMintProposal(2);
        (, , , , , uint256 amount3) = issuerGateway.getMintProposal(3);

        assertEq(amount1, 100);
        assertEq(amount2, 200);
        assertEq(amount3, 300);
    }

    /* ============ mint ============ */

    function test_mint_revertIfNotMinter() public {
        uint48 mintId = _proposeMint(100, recipient);
        _warpToMintable(mintId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                issuerGateway.EXECUTOR_ROLE()
            )
        );

        vm.prank(other);
        issuerGateway.mint(mintId);
    }

    function test_mint_revertIfInvalidProposal() public {
        vm.expectRevert(IIssuerGateway.InvalidMintProposal.selector);

        vm.prank(executor);
        issuerGateway.mint(999);
    }

    function test_mint_revertIfPending() public {
        uint48 mintId = _proposeMint(100, recipient);
        uint40 activeAt = uint40(block.timestamp) + DEFAULT_MINT_DELAY;

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.PendingMintProposal.selector, activeAt));

        vm.prank(executor);
        issuerGateway.mint(mintId);
    }

    function test_mint_revertIfExpired() public {
        uint48 mintId = _proposeMint(100, recipient);
        uint40 expiresAt = _warpToExpired(mintId);

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.ExpiredMintProposal.selector, expiresAt));

        vm.prank(executor);
        issuerGateway.mint(mintId);
    }

    function test_mint_revertIfMinterOperatorRoleRevoked() public {
        bytes32 operatorRole = issuerGateway.OPERATOR_ROLE();
        uint48 mintId = _proposeMint(100, recipient);

        _warpToMintable(mintId);

        vm.prank(admin);
        issuerGateway.revokeRole(operatorRole, operator);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, operatorRole)
        );

        vm.prank(executor);
        issuerGateway.mint(mintId);
    }

    function test_mint_successAtTTLBoundary() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Warp to exact TTL boundary (activeAt + TTL)
        (, uint40 activeAt, uint40 expiresAt, , , ) = issuerGateway.getMintProposal(mintId);
        vm.warp(expiresAt);

        vm.prank(executor);
        issuerGateway.mint(mintId);

        assertEq(pyusdx.balanceOf(recipient), 100);
    }

    function test_mint() public {
        uint48 mintId = _proposeMint(100, recipient);
        _warpToMintable(mintId);

        vm.expectEmit();
        emit IIssuerGateway.MintExecuted(mintId, executor, 100, recipient);

        vm.prank(executor);
        issuerGateway.mint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , , , ) = issuerGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);

        assertEq(pyusdx.balanceOf(recipient), 100);
    }

    /* ============ burn ============ */

    function test_burn_revertIfNotIssuer() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                issuerGateway.OPERATOR_ROLE()
            )
        );

        vm.prank(other);
        issuerGateway.burn(100);
    }

    function test_burn_revertIfZeroAmount() public {
        vm.prank(operator);

        vm.expectRevert(IIssuerGateway.ZeroBurnAmount.selector);
        issuerGateway.burn(0);
    }

    function test_burn() public {
        // First mint some tokens to the operator
        uint48 mintId = _proposeMint(100, operator);

        _warpToMintable(mintId);

        vm.prank(executor);
        issuerGateway.mint(mintId);

        uint256 balanceBefore = pyusdx.balanceOf(operator);
        assertEq(balanceBefore, 100);

        vm.expectEmit();
        emit IIssuerGateway.BurnExecuted(operator, 50);

        vm.prank(operator);
        issuerGateway.burn(50);

        assertEq(pyusdx.balanceOf(operator), 50);
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

        (, uint40 activeAt, , , , ) = issuerGateway.getMintProposal(mintId);

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.ActiveMintProposal.selector, activeAt));

        vm.prank(operator);
        issuerGateway.cancelMint(mintId);
    }

    function test_cancelMint_revertIfActive_afterDelay() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Warp to after the delay has passed but before TTL expires
        (, uint40 activeAt, , , , ) = issuerGateway.getMintProposal(mintId);

        vm.warp(activeAt + 1 hours);

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.ActiveMintProposal.selector, activeAt));

        vm.prank(operator);
        issuerGateway.cancelMint(mintId);
    }

    function test_cancelMint() public {
        uint48 mintId = _proposeMint(100, recipient);

        vm.expectEmit();
        emit IIssuerGateway.MintCanceled(mintId, operator);

        vm.prank(operator);
        issuerGateway.cancelMint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , , , ) = issuerGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);
    }

    function test_cancelMint_successAfterRoleRevoked() public {
        uint48 mintId = _proposeMint(100, recipient);

        vm.startPrank(admin);

        // Revoke operator role using admin's DEFAULT_ADMIN_ROLE
        issuerGateway.revokeRole(issuerGateway.OPERATOR_ROLE(), operator);

        vm.stopPrank();

        // Verify operator no longer has the role
        assertFalse(issuerGateway.hasRole(issuerGateway.OPERATOR_ROLE(), operator));

        // Issuer can still cancel their own proposal (cancel doesn't require OPERATOR_ROLE)
        // This must happen while proposal is still pending (before activeAt)
        vm.prank(operator);
        issuerGateway.cancelMint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , , , ) = issuerGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);
    }

    /* ============ View Functions ============ */

    function test_getMintProposal_returnsZeroForNonExistent() public view {
        (
            uint40 createdAt,
            uint40 activeAt,
            uint40 expiresAt,
            address minter_,
            address recipient_,
            uint256 amount
        ) = issuerGateway.getMintProposal(999);

        assertEq(createdAt, 0);
        assertEq(activeAt, 0);
        assertEq(expiresAt, 0);
        assertEq(minter_, address(0));
        assertEq(recipient_, address(0));
        assertEq(amount, 0);
    }

    function test_getMintProposal() public {
        uint48 mintId = _proposeMint(100, recipient);

        (
            uint40 createdAt,
            uint40 activeAt,
            uint40 expiresAt,
            address storedOperator,
            address recipient_,
            uint256 amount
        ) = issuerGateway.getMintProposal(mintId);

        assertEq(createdAt, block.timestamp);
        assertEq(activeAt, createdAt + DEFAULT_MINT_DELAY);
        assertEq(expiresAt, activeAt + DEFAULT_MINT_TTL);
        assertEq(storedOperator, operator);
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

    /* ============ Snapshot Invariance ============ */

    function test_mint_usesSnapshottedActiveAt() public {
        uint48 mintId = _proposeMint(100, recipient);

        (, uint40 originalActiveAt, , , , ) = issuerGateway.getMintProposal(mintId);

        // Admin shortens delay to 1 hour
        vm.prank(admin);
        issuerGateway.setMintDelay(1 hours);

        // Warp to the new shorter delay — proposal should still be pending
        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.PendingMintProposal.selector, originalActiveAt));

        vm.prank(executor);
        issuerGateway.mint(mintId);
    }

    function test_mint_usesSnapshottedExpiresAt() public {
        uint48 mintId = _proposeMint(100, recipient);

        (, , uint40 originalExpiresAt, , , ) = issuerGateway.getMintProposal(mintId);

        // Warp past the original expiresAt
        vm.warp(originalExpiresAt + 1);

        // Admin extends TTL to 365 days — proposal should still be expired
        vm.prank(admin);
        issuerGateway.setMintTTL(365 days);

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.ExpiredMintProposal.selector, originalExpiresAt));

        vm.prank(executor);
        issuerGateway.mint(mintId);
    }

    function test_cancelMint_usesSnapshottedActiveAt() public {
        uint48 mintId = _proposeMint(100, recipient);

        (, uint40 originalActiveAt, , , , ) = issuerGateway.getMintProposal(mintId);

        // Admin shortens delay to 1 hour — computed activeAt would be earlier than snapshot
        vm.prank(admin);
        issuerGateway.setMintDelay(1 hours);

        // Warp between the new shorter computed activeAt and the original snapshot activeAt
        vm.warp(block.timestamp + 1 hours);

        // Proposal should still be cancellable because its snapshotted activeAt hasn't been reached
        vm.prank(operator);
        issuerGateway.cancelMint(mintId);

        // Verify proposal is deleted
        (uint40 createdAt, , , , , ) = issuerGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);
    }

    function test_snapshotInvariance_setMintDelayLower_doesNotAccelerate() public {
        uint48 mintId = _proposeMint(100, recipient);

        (, uint40 originalActiveAt, , , , ) = issuerGateway.getMintProposal(mintId);

        // Admin sets delay to 0
        vm.prank(admin);
        issuerGateway.setMintDelay(0);

        // Warp to just before the original activeAt
        vm.warp(originalActiveAt - 1);

        vm.expectRevert(abi.encodeWithSelector(IIssuerGateway.PendingMintProposal.selector, originalActiveAt));

        vm.prank(executor);
        issuerGateway.mint(mintId);
    }

    function test_snapshotInvariance_setMintDelayHigher_doesNotPostpone() public {
        uint48 mintId = _proposeMint(100, recipient);

        (, uint40 originalActiveAt, , , , ) = issuerGateway.getMintProposal(mintId);

        // Admin raises delay to 7 days
        vm.prank(admin);
        issuerGateway.setMintDelay(7 days);

        // Warp past the original snapshotted activeAt but before the recomputed one
        vm.warp(originalActiveAt);

        // Proposal should be executable because its snapshotted activeAt has been reached
        vm.prank(executor);
        issuerGateway.mint(mintId);

        assertEq(pyusdx.balanceOf(recipient), 100);
    }

    function test_snapshotInvariance_setMintTTLLower_doesNotShortenWindow() public {
        uint48 mintId = _proposeMint(100, recipient);

        (, uint40 activeAt, uint40 originalExpiresAt, , , ) = issuerGateway.getMintProposal(mintId);

        // Warp to active
        vm.warp(activeAt);

        // Admin shortens TTL to 1 second
        vm.prank(admin);
        issuerGateway.setMintTTL(1);

        // Warp to a time after the recomputed expiry but before the snapshot's expiresAt
        vm.warp(activeAt + 2);

        // Proposal should still be executable because its snapshotted expiresAt hasn't been reached
        vm.prank(executor);
        issuerGateway.mint(mintId);

        assertEq(pyusdx.balanceOf(recipient), 100);
    }
}
