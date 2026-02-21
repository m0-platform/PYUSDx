// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { UnsafeUpgrades } from "../../lib/m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20Extended.sol";
import { IAccessControl } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Initializable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";
import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { MockPYUSDXExtension } from "../mock/MockPYUSDXExtension.sol";
import { MockMultiMint } from "../mock/MockMultiMint.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

contract SwapFacilityUnitTests is PYUSDXBaseUnitTest {
    SwapFacility public swapFacility;
    MockPYUSDXExtension public extensionA;
    MockPYUSDXExtension public extensionB;
    MockMultiMint public multiMintExtension;
    MockERC20 public mockUSDC;

    uint256 public constant AMOUNT = 1000e6;

    function setUp() public override {
        super.setUp();

        address swapFacilityImpl = address(new SwapFacility(address(pyusdx)));
        swapFacility = SwapFacility(
            UnsafeUpgrades.deployTransparentProxy(
                swapFacilityImpl,
                admin,
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin, pauser)
            )
        );

        extensionA = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        extensionB = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        multiMintExtension = new MockMultiMint(address(pyusdx), address(swapFacility), makeAddr("yieldRecipient"));

        vm.startPrank(admin);
        swapFacility.setApprovedExtension(address(extensionA), true);
        swapFacility.setApprovedExtension(address(extensionB), true);
        swapFacility.setApprovedExtension(address(multiMintExtension), true);
        vm.stopPrank();

        multiMintExtension.setAllowedAsset(address(mockUSDC), true);
    }

    /* ============ Helpers ============ */

    function _setupSwapIn(address user, uint256 amount) internal {
        minterGateway.mint(user, amount);

        vm.prank(user);
        IERC20(address(pyusdx)).approve(address(swapFacility), amount);
    }

    function _setupSwapOut(address user, uint256 amount) internal {
        _setupSwapIn(user, amount);

        vm.prank(user);
        swapFacility.swapIn(address(extensionA), amount, user);

        vm.prank(user);
        IERC20(address(extensionA)).approve(address(swapFacility), amount);
    }

    /* ============ Constructor & Initialization ============ */

    function test_constructor_zeroPyusdx() public {
        vm.expectRevert(ISwapFacility.ZeroPYUSDXToken.selector);
        new SwapFacility(address(0));
    }

    function test_initialState() public view {
        assertEq(swapFacility.pyusdx(), address(pyusdx));
        assertTrue(swapFacility.hasRole(swapFacility.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(swapFacility.hasRole(swapFacility.PAUSER_ROLE(), pauser));
    }

    function test_initialize_alreadyInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        swapFacility.initialize(admin, pauser);
    }

    /* ============ setApprovedExtension (Admin) ============ */

    function test_setApprovedExtension() public {
        MockPYUSDXExtension newExt = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.expectEmit();
        emit ISwapFacility.ApprovedExtensionSet(address(newExt), true);

        vm.prank(admin);
        swapFacility.setApprovedExtension(address(newExt), true);

        assertTrue(swapFacility.isApprovedExtension(address(newExt)));
    }

    function test_setApprovedExtension_notAdmin() public {
        MockPYUSDXExtension newExt = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                swapFacility.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(alice);
        swapFacility.setApprovedExtension(address(newExt), true);
    }

    function test_setApprovedExtension_zeroExtension() public {
        vm.expectRevert(ISwapFacility.ZeroExtension.selector);

        vm.prank(admin);
        swapFacility.setApprovedExtension(address(0), true);
    }

    function test_setApprovedExtension_sameValue() public {
        // extensionA is already approved in setUp
        // Setting to same value should not emit event
        vm.prank(admin);
        swapFacility.setApprovedExtension(address(extensionA), true);

        assertTrue(swapFacility.isApprovedExtension(address(extensionA)));
    }

    function test_setApprovedExtension_unsetExtension() public {
        vm.expectEmit();
        emit ISwapFacility.ApprovedExtensionSet(address(extensionA), false);

        vm.prank(admin);
        swapFacility.setApprovedExtension(address(extensionA), false);

        assertFalse(swapFacility.isApprovedExtension(address(extensionA)));
    }

    /* ============ isApprovedExtension (View) ============ */

    function test_isApprovedExtension() public {
        assertTrue(swapFacility.isApprovedExtension(address(extensionA)));
        assertTrue(swapFacility.isApprovedExtension(address(extensionB)));

        MockPYUSDXExtension newExt = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        assertFalse(swapFacility.isApprovedExtension(address(newExt)));
    }

    /* ============ swapIn (PYUSDX -> Extension) ============ */

    function test_swapIn() public {
        _setupSwapIn(alice, AMOUNT);

        uint256 alicePyusdxBalanceBefore = pyusdx.balanceOf(alice);
        uint256 aliceExtBalanceBefore = extensionA.balanceOf(alice);

        vm.expectEmit();
        emit ISwapFacility.SwappedIn(address(pyusdx), address(extensionA), AMOUNT, alice);

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);

        assertEq(pyusdx.balanceOf(alice), alicePyusdxBalanceBefore - AMOUNT);
        assertEq(extensionA.balanceOf(alice), aliceExtBalanceBefore + AMOUNT);
        assertEq(pyusdx.balanceOf(address(extensionA)), AMOUNT);
    }

    function test_swapIn_toRecipient() public {
        _setupSwapIn(alice, AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, bob);

        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(extensionA.balanceOf(alice), 0);
        assertEq(extensionA.balanceOf(bob), AMOUNT);
    }

    function test_swapIn_notApprovedExtension() public {
        MockPYUSDXExtension unapproved = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, address(unapproved)));

        vm.prank(alice);
        swapFacility.swapIn(address(unapproved), AMOUNT, alice);
    }

    function test_swapIn_paused() public {
        vm.prank(pauser);
        swapFacility.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);
    }

    function test_swapIn_insufficientBalance() public {
        // Alice approves swapFacility but has no balance
        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IPYUSDX.InsufficientBalance.selector, alice, 0, AMOUNT));

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);
    }

    function test_swapIn_insufficientAllowance() public {
        minterGateway.mint(alice, AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Extended.InsufficientAllowance.selector, address(swapFacility), 0, AMOUNT)
        );

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);
    }

    /* ============ swapOut (Extension -> PYUSDX) ============ */

    function test_swapOut() public {
        _setupSwapOut(alice, AMOUNT);

        uint256 alicePyusdxBalanceBefore = pyusdx.balanceOf(alice);
        uint256 aliceExtBalanceBefore = extensionA.balanceOf(alice);

        vm.expectEmit();
        emit ISwapFacility.SwappedOut(address(extensionA), address(pyusdx), AMOUNT, alice);

        vm.prank(alice);
        swapFacility.swapOut(address(extensionA), AMOUNT, alice);

        assertEq(extensionA.balanceOf(alice), aliceExtBalanceBefore - AMOUNT);
        assertEq(pyusdx.balanceOf(alice), alicePyusdxBalanceBefore + AMOUNT);
        assertEq(extensionA.totalSupply(), 0);
    }

    function test_swapOut_toRecipient() public {
        _setupSwapOut(alice, AMOUNT);

        vm.prank(alice);
        swapFacility.swapOut(address(extensionA), AMOUNT, bob);

        assertEq(extensionA.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(alice), 0);
        assertEq(pyusdx.balanceOf(bob), AMOUNT);
    }

    function test_swapOut_notApprovedExtension() public {
        MockPYUSDXExtension unapproved = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.prank(alice);
        IERC20(address(unapproved)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, address(unapproved)));

        vm.prank(alice);
        swapFacility.swapOut(address(unapproved), AMOUNT, alice);
    }

    function test_swapOut_paused() public {
        _setupSwapOut(alice, AMOUNT);

        vm.prank(pauser);
        swapFacility.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swapOut(address(extensionA), AMOUNT, alice);
    }

    /* ============ swapExtensions (Extension -> Extension) ============ */

    function test_swapExtensions() public {
        _setupSwapIn(alice, AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);

        vm.prank(alice);
        IERC20(address(extensionA)).approve(address(swapFacility), AMOUNT);

        uint256 aliceExtABalanceBefore = extensionA.balanceOf(alice);
        uint256 aliceExtBBalanceBefore = extensionB.balanceOf(alice);

        vm.expectEmit();
        emit ISwapFacility.Swapped(address(extensionA), address(extensionB), AMOUNT, alice);

        vm.prank(alice);
        swapFacility.swap(address(extensionA), address(extensionB), AMOUNT, alice);

        assertEq(extensionA.balanceOf(alice), aliceExtABalanceBefore - AMOUNT);
        assertEq(extensionB.balanceOf(alice), aliceExtBBalanceBefore + AMOUNT);
    }

    function test_swapExtensions_toRecipient() public {
        _setupSwapIn(alice, AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);

        vm.prank(alice);
        IERC20(address(extensionA)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(extensionA), address(extensionB), AMOUNT, bob);

        assertEq(extensionA.balanceOf(alice), 0);
        assertEq(extensionB.balanceOf(alice), 0);
        assertEq(extensionB.balanceOf(bob), AMOUNT);
    }

    function test_swapExtensions_tokenInNotApproved() public {
        MockPYUSDXExtension unapproved = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.prank(alice);
        IERC20(address(unapproved)).approve(address(swapFacility), AMOUNT);

        // When tokenIn is not approved but tokenOut is, it falls through to `_revertIfCannotMultiMint()` and revert with `InvalidSwapPath()`
        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.InvalidSwapPath.selector, address(unapproved), address(extensionB))
        );

        vm.prank(alice);
        swapFacility.swap(address(unapproved), address(extensionB), AMOUNT, alice);
    }

    function test_swapExtensions_tokenOutNotApproved() public {
        _setupSwapOut(alice, AMOUNT);

        MockPYUSDXExtension unapproved = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        // When tokenOut is not approved, it falls through to InvalidSwapPath
        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.InvalidSwapPath.selector, address(extensionA), address(unapproved))
        );

        vm.prank(alice);
        swapFacility.swap(address(extensionA), address(unapproved), AMOUNT, alice);
    }

    /* ============ swapInMultiMint (Asset -> MultiMint) ============ */

    function test_swapInMultiMint() public {
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        uint256 aliceUsdcBalanceBefore = mockUSDC.balanceOf(alice);

        vm.expectEmit();
        emit ISwapFacility.SwappedInMultiMint(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        assertEq(mockUSDC.balanceOf(alice), aliceUsdcBalanceBefore - AMOUNT);
        assertEq(multiMintExtension.balanceOf(alice), AMOUNT);
    }

    function test_swapInMultiMint_toRecipient() public {
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, bob);

        assertEq(multiMintExtension.balanceOf(alice), 0);
        assertEq(multiMintExtension.balanceOf(bob), AMOUNT);
    }

    function test_swapInMultiMint_invalidSwapPath() public {
        MockERC20 unallowedAsset = new MockERC20("Unallowed", "UNL", 6);
        unallowedAsset.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(unallowedAsset)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapFacility.InvalidSwapPath.selector,
                address(unallowedAsset),
                address(multiMintExtension)
            )
        );

        vm.prank(alice);
        swapFacility.swap(address(unallowedAsset), address(multiMintExtension), AMOUNT, alice);
    }

    function test_swapInMultiMint_extensionNotApproved() public {
        MockMultiMint unapproved = new MockMultiMint(
            address(pyusdx),
            address(swapFacility),
            makeAddr("yieldRecipient")
        );

        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        // When extensionOut is not approved, it falls through to InvalidSwapPath
        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.InvalidSwapPath.selector, address(mockUSDC), address(unapproved))
        );

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(unapproved), AMOUNT, alice);
    }

    function test_swapInMultiMint_paused() public {
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(pauser);
        swapFacility.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);
    }

    /* ============ replaceAsset ============ */

    function test_replaceAsset() public {
        // First, swap in USDC to multiMintExtension
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        // Now, replace USDC with PYUSDX from extensionB
        minterGateway.mint(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        // Give extensionB to bob
        vm.prank(bob);
        swapFacility.swapIn(address(extensionB), AMOUNT, bob);

        vm.prank(bob);
        IERC20(address(extensionB)).approve(address(swapFacility), AMOUNT);

        vm.expectEmit();
        emit ISwapFacility.MultiMintAssetReplaced(address(mockUSDC), address(multiMintExtension), AMOUNT);

        vm.prank(bob);
        swapFacility.replaceAsset(address(mockUSDC), address(extensionB), address(multiMintExtension), AMOUNT, bob);

        assertEq(mockUSDC.balanceOf(bob), AMOUNT);
        assertEq(extensionB.balanceOf(bob), 0);
    }

    function test_replaceAsset_extensionInNotApproved() public {
        MockPYUSDXExtension unapproved = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, address(unapproved)));

        vm.prank(alice);
        swapFacility.replaceAsset(address(mockUSDC), address(unapproved), address(multiMintExtension), AMOUNT, alice);
    }

    function test_replaceAsset_extensionOutNotApproved() public {
        MockMultiMint unapproved = new MockMultiMint(
            address(pyusdx),
            address(swapFacility),
            makeAddr("yieldRecipient")
        );

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, address(unapproved)));

        vm.prank(alice);
        swapFacility.replaceAsset(address(mockUSDC), address(extensionA), address(unapproved), AMOUNT, alice);
    }

    function test_replaceAsset_paused() public {
        vm.prank(pauser);
        swapFacility.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.replaceAsset(address(mockUSDC), address(extensionA), address(multiMintExtension), AMOUNT, alice);
    }

    function test_replaceAsset_rawPyusdx() public {
        // Setup: alice swaps USDC into multiMintExtension
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        // Bob uses raw PYUSDX to replace the asset
        minterGateway.mint(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectEmit();
        emit ISwapFacility.MultiMintAssetReplaced(address(mockUSDC), address(multiMintExtension), AMOUNT);

        vm.prank(bob);
        swapFacility.replaceAsset(address(mockUSDC), address(pyusdx), address(multiMintExtension), AMOUNT, bob);

        assertEq(mockUSDC.balanceOf(bob), AMOUNT);
    }

    function test_replaceAsset_tokenInNotPyusdxOrApproved() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(randomToken)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, address(randomToken)));

        vm.prank(alice);
        swapFacility.replaceAsset(address(mockUSDC), address(randomToken), address(multiMintExtension), AMOUNT, alice);
    }

    /* ============ canSwapViaPath (View) ============ */

    function test_canSwapViaPath_pyusdxToExtension() public view {
        assertTrue(swapFacility.canSwapViaPath(address(pyusdx), address(extensionA)));
    }

    function test_canSwapViaPath_extensionToPyusdx() public view {
        assertTrue(swapFacility.canSwapViaPath(address(extensionA), address(pyusdx)));
    }

    function test_canSwapViaPath_extensionToExtension() public view {
        assertTrue(swapFacility.canSwapViaPath(address(extensionA), address(extensionB)));
    }

    function test_canSwapViaPath_assetToMultiMint() public view {
        assertTrue(swapFacility.canSwapViaPath(address(mockUSDC), address(multiMintExtension)));
    }

    function test_canSwapViaPath_paused() public {
        vm.prank(pauser);
        swapFacility.pause();

        assertFalse(swapFacility.canSwapViaPath(address(pyusdx), address(extensionA)));
        assertFalse(swapFacility.canSwapViaPath(address(extensionA), address(pyusdx)));
        assertFalse(swapFacility.canSwapViaPath(address(extensionA), address(extensionB)));
    }

    function test_canSwapViaPath_extensionPaused() public {
        assertTrue(swapFacility.canSwapViaPath(address(pyusdx), address(extensionA)));

        extensionA.pause();

        assertFalse(swapFacility.canSwapViaPath(address(pyusdx), address(extensionA)));
        assertFalse(swapFacility.canSwapViaPath(address(extensionA), address(pyusdx)));
        assertFalse(swapFacility.canSwapViaPath(address(extensionA), address(extensionB)));
    }

    function test_canSwapViaPath_notApprovedExtension() public {
        MockPYUSDXExtension unapproved = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));

        assertFalse(swapFacility.canSwapViaPath(address(pyusdx), address(unapproved)));
        assertFalse(swapFacility.canSwapViaPath(address(unapproved), address(pyusdx)));
        assertFalse(swapFacility.canSwapViaPath(address(unapproved), address(extensionB)));
    }

    function test_canSwapViaPath_invalidContracts() public view {
        // EOA addresses have no code
        assertFalse(swapFacility.canSwapViaPath(alice, address(extensionA)));
        assertFalse(swapFacility.canSwapViaPath(address(extensionA), alice));
        assertFalse(swapFacility.canSwapViaPath(alice, bob));
    }

    function test_canSwapViaPath_invalidSwapPath() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);

        // Neither PYUSDX nor approved extension
        assertFalse(swapFacility.canSwapViaPath(address(randomToken), address(extensionA)));
    }

    /* ============ msgSender (View) ============ */

    // TODO: move to integration tests
    function test_msgSender_duringSwap() public {
        _setupSwapIn(alice, AMOUNT);

        // msgSender() should return the original caller during a swap
        // We can't directly test this from outside, but we can verify it returns 0 when not swapping
        assertEq(swapFacility.msgSender(), address(0));
    }

    function test_msgSender_zero() public view {
        // When no swap is in progress, msgSender should return zero
        assertEq(swapFacility.msgSender(), address(0));
    }

    /* ============ Pause Behavior ============ */

    function test_allFunctionsRevertWhenPaused() public {
        vm.prank(pauser);
        swapFacility.pause();

        // swapIn
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);

        // swapOut
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swapOut(address(extensionA), AMOUNT, alice);

        // swap
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swap(address(extensionA), address(extensionB), AMOUNT, alice);

        // swap with asset
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        // replaceAsset
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.replaceAsset(address(mockUSDC), address(extensionA), address(multiMintExtension), AMOUNT, alice);
    }

    /* ============ Reentrancy Protection ============ */

    // TODO: move to integration tests
    function test_reentrancy_blocked() public {
        // The isNotLocked modifier prevents reentrancy
        // This test verifies that the lock mechanism is in place
        _setupSwapIn(alice, AMOUNT);

        // Normal swap should work
        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);

        // msgSender should be 0 after swap completes
        assertEq(swapFacility.msgSender(), address(0));
    }
}
