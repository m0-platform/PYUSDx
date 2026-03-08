// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { MinterGatewayBaseUnitTest } from "../utils/MinterGatewayBaseUnitTest.sol";
import { IMinterGateway } from "../../src/interfaces/IMinterGateway.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { MinterGateway } from "../../src/MinterGateway.sol";

contract MinterGatewayUnitTest is MinterGatewayBaseUnitTest {
    /* ============ Constructor ============ */

    function test_constructor_revertIfZeroPYUSDX() public {
        vm.expectRevert(IMinterGateway.ZeroPYUSDXToken.selector);
        new MinterGateway(address(0));
    }

    function test_constructor() public view {
        assertEq(minterGateway.pyusdx(), address(pyusdx));
    }

    /* ============ Initialize ============ */

    function test_initialize_revertIfZeroAdmin() public {
        MinterGateway newImpl = new MinterGateway(address(pyusdx));

        vm.expectRevert(IMinterGateway.ZeroAdminAddress.selector);
        UnsafeUpgrades.deployTransparentProxy(
            address(newImpl),
            admin,
            abi.encodeWithSelector(
                MinterGateway.initialize.selector,
                address(0), // zero admin
                minter,
                DEFAULT_MINT_DELAY,
                DEFAULT_MINT_TTL
            )
        );
    }

    function test_initialize_revertIfZeroMinter() public {
        MinterGateway newImpl = new MinterGateway(address(pyusdx));

        vm.expectRevert(IMinterGateway.ZeroMinterAddress.selector);
        UnsafeUpgrades.deployTransparentProxy(
            address(newImpl),
            admin,
            abi.encodeWithSelector(
                MinterGateway.initialize.selector,
                admin,
                address(0), // zero minter
                DEFAULT_MINT_DELAY,
                DEFAULT_MINT_TTL
            )
        );
    }

    function test_initialize_revertIfCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        minterGateway.initialize(admin, minter, DEFAULT_MINT_DELAY, DEFAULT_MINT_TTL);
    }

    function test_initialize_revertIfZeroMintTTL() public {
        MinterGateway newImpl = new MinterGateway(address(pyusdx));

        vm.expectRevert(IMinterGateway.ZeroMintTTL.selector);
        UnsafeUpgrades.deployTransparentProxy(
            address(newImpl),
            admin,
            abi.encodeWithSelector(
                MinterGateway.initialize.selector,
                admin,
                minter,
                DEFAULT_MINT_DELAY,
                0 // zero TTL
            )
        );
    }

    function test_initialize() public view {
        assertTrue(minterGateway.hasRole(minterGateway.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(minterGateway.hasRole(minterGateway.MINTER_ROLE(), minter));
        assertEq(minterGateway.mintDelay(), DEFAULT_MINT_DELAY);
        assertEq(minterGateway.mintTTL(), DEFAULT_MINT_TTL);
    }

    /* ============ proposeMint ============ */

    function test_proposeMint_revertIfNotMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                minterGateway.MINTER_ROLE()
            )
        );

        vm.prank(other);
        minterGateway.proposeMint(100, recipient);
    }

    function test_proposeMint_revertIfZeroAmount() public {
        vm.expectRevert(IMinterGateway.ZeroMintAmount.selector);

        vm.prank(minter);
        minterGateway.proposeMint(0, recipient);
    }

    function test_proposeMint_revertIfZeroRecipient() public {
        vm.expectRevert(IMinterGateway.ZeroMintRecipient.selector);

        vm.prank(minter);
        minterGateway.proposeMint(100, address(0));
    }

    function test_proposeMint() public {
        uint40 activeAt = uint40(block.timestamp) + DEFAULT_MINT_DELAY;
        uint40 expiresAt = activeAt + DEFAULT_MINT_TTL;

        vm.expectEmit();
        emit IMinterGateway.MintProposed(1, minter, 100, recipient, activeAt, expiresAt);

        vm.prank(minter);
        uint48 mintId = minterGateway.proposeMint(100, recipient);

        assertEq(mintId, 1);
        assertEq(minterGateway.mintNonce(), 1);

        (uint40 createdAt, address storedMinter, address storedRecipient, uint256 storedAmount) = minterGateway
            .getMintProposal(mintId);

        assertEq(createdAt, block.timestamp);
        assertEq(storedMinter, minter);
        assertEq(storedRecipient, recipient);
        assertEq(storedAmount, 100);
    }

    function test_proposeMint_multipleProposalsUniqueIds() public {
        vm.startPrank(minter);

        uint48 mintId1 = minterGateway.proposeMint(100, recipient);
        uint48 mintId2 = minterGateway.proposeMint(200, recipient);
        uint48 mintId3 = minterGateway.proposeMint(300, recipient);

        vm.stopPrank();

        assertEq(mintId1, 1);
        assertEq(mintId2, 2);
        assertEq(mintId3, 3);
        assertEq(minterGateway.mintNonce(), 3);

        // All proposals should be stored independently
        (, , , uint256 amount1) = minterGateway.getMintProposal(1);
        (, , , uint256 amount2) = minterGateway.getMintProposal(2);
        (, , , uint256 amount3) = minterGateway.getMintProposal(3);

        assertEq(amount1, 100);
        assertEq(amount2, 200);
        assertEq(amount3, 300);
    }

    /* ============ mint ============ */

    function test_mint_revertIfInvalidProposal() public {
        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        minterGateway.mint(999);
    }

    function test_mint_revertIfPending() public {
        uint48 mintId = _proposeMint(100, recipient);
        uint40 activeAt = uint40(block.timestamp) + DEFAULT_MINT_DELAY;

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.PendingMintProposal.selector, activeAt));
        minterGateway.mint(mintId);
    }

    function test_mint_revertIfExpired() public {
        uint48 mintId = _proposeMint(100, recipient);
        uint40 expiresAt = _warpToExpired(mintId);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.ExpiredMintProposal.selector, expiresAt));
        minterGateway.mint(mintId);
    }

    function test_mint_successAtTTLBoundary() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Warp to exact TTL boundary (activeAt + TTL)
        (uint40 createdAt, , , ) = minterGateway.getMintProposal(mintId);
        vm.warp(createdAt + DEFAULT_MINT_DELAY + DEFAULT_MINT_TTL);

        minterGateway.mint(mintId);
        assertEq(pyusdx.balanceOf(recipient), 100);
    }

    function test_mint() public {
        uint48 mintId = _proposeMint(100, recipient);
        _warpToMintable(mintId);

        vm.expectEmit();
        emit IMinterGateway.MintExecuted(mintId, caller, 100, recipient);

        vm.prank(caller);
        minterGateway.mint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , ) = minterGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);

        assertEq(pyusdx.balanceOf(recipient), 100);
    }

    /* ============ burn ============ */

    function test_burn_revertIfNotMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                minterGateway.MINTER_ROLE()
            )
        );

        vm.prank(other);
        minterGateway.burn(100);
    }

    function test_burn_revertIfZeroAmount() public {
        vm.prank(minter);
        vm.expectRevert(IMinterGateway.ZeroBurnAmount.selector);
        minterGateway.burn(0);
    }

    function test_burn() public {
        // First mint some tokens to the minter
        uint48 mintId = _proposeMint(100, minter);
        _warpToMintable(mintId);
        minterGateway.mint(mintId);

        uint256 balanceBefore = pyusdx.balanceOf(minter);
        assertEq(balanceBefore, 100);

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(minter, 50);

        vm.prank(minter);
        minterGateway.burn(50);

        assertEq(pyusdx.balanceOf(minter), 50);
    }

    /* ============ cancelMint ============ */

    function test_cancelMint_revertIfInvalidProposal() public {
        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        minterGateway.cancelMint(999);
    }

    function test_cancelMint_revertIfNotCreator() public {
        uint48 mintId = _proposeMint(100, recipient);

        vm.expectRevert(IMinterGateway.NotMintProposalCreator.selector);

        vm.prank(other);
        minterGateway.cancelMint(mintId);
    }

    function test_cancelMint_revertIfActive() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Warp to when the proposal becomes active (at activeAt boundary)
        _warpToMintable(mintId);

        (uint40 createdAt, , , ) = minterGateway.getMintProposal(mintId);
        uint40 activeAt = createdAt + DEFAULT_MINT_DELAY;

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.ActiveMintProposal.selector, activeAt));

        vm.prank(minter);
        minterGateway.cancelMint(mintId);
    }

    function test_cancelMint_revertIfActive_afterDelay() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Warp to after the delay has passed but before TTL expires
        (uint40 createdAt, , , ) = minterGateway.getMintProposal(mintId);

        uint40 activeAt = createdAt + DEFAULT_MINT_DELAY;
        vm.warp(activeAt + 1 hours);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.ActiveMintProposal.selector, activeAt));

        vm.prank(minter);
        minterGateway.cancelMint(mintId);
    }

    function test_cancelMint() public {
        uint48 mintId = _proposeMint(100, recipient);

        vm.expectEmit();
        emit IMinterGateway.MintCanceled(mintId, minter);

        vm.prank(minter);
        minterGateway.cancelMint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , ) = minterGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);
    }

    function test_cancelMint_successAfterRoleRevoked() public {
        uint48 mintId = _proposeMint(100, recipient);

        // Revoke minter role using admin's DEFAULT_ADMIN_ROLE
        // Note: Using vm.prank with admin who has DEFAULT_ADMIN_ROLE
        vm.startPrank(admin);
        minterGateway.revokeRole(minterGateway.MINTER_ROLE(), minter);
        vm.stopPrank();

        // Verify minter no longer has the role
        assertFalse(minterGateway.hasRole(minterGateway.MINTER_ROLE(), minter));

        // Minter can still cancel their own proposal (cancel doesn't require MINTER_ROLE)
        // This must happen while proposal is still pending (before activeAt)
        vm.prank(minter);
        minterGateway.cancelMint(mintId);

        // Check proposal deleted
        (uint40 createdAt, , , ) = minterGateway.getMintProposal(mintId);
        assertEq(createdAt, 0);
    }

    /* ============ View Functions ============ */

    function test_getMintProposal_returnsZeroForNonExistent() public view {
        (uint40 createdAt, address minter_, address recipient_, uint256 amount) = minterGateway.getMintProposal(999);

        assertEq(createdAt, 0);
        assertEq(minter_, address(0));
        assertEq(recipient_, address(0));
        assertEq(amount, 0);
    }

    function test_getMintProposal() public {
        uint48 mintId = _proposeMint(100, recipient);

        (uint40 createdAt, address minter_, address recipient_, uint256 amount) = minterGateway.getMintProposal(mintId);

        assertEq(createdAt, block.timestamp);
        assertEq(minter_, minter);
        assertEq(recipient_, recipient);
        assertEq(amount, 100);
    }

    function test_mintDelay() public view {
        assertEq(minterGateway.mintDelay(), DEFAULT_MINT_DELAY);
    }

    function test_mintTTL() public view {
        assertEq(minterGateway.mintTTL(), DEFAULT_MINT_TTL);
    }

    /* ============ Admin Functions ============ */

    function test_setMintDelay_revertIfNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                minterGateway.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(other);
        minterGateway.setMintDelay(2 days);
    }

    function test_setMintDelay() public {
        vm.expectEmit();
        emit IMinterGateway.MintDelaySet(2 days);

        vm.prank(admin);
        minterGateway.setMintDelay(2 days);

        assertEq(minterGateway.mintDelay(), 2 days);
    }

    function test_setMintTTL_revertIfNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                minterGateway.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(other);
        minterGateway.setMintTTL(14 days);
    }

    function test_setMintTTL_revertIfZero() public {
        vm.expectRevert(IMinterGateway.ZeroMintTTL.selector);

        vm.prank(admin);
        minterGateway.setMintTTL(0);
    }

    function test_setMintTTL() public {
        vm.expectEmit();
        emit IMinterGateway.MintTTLSet(14 days);

        vm.prank(admin);
        minterGateway.setMintTTL(14 days);

        assertEq(minterGateway.mintTTL(), 14 days);
    }
}
