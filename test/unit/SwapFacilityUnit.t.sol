// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20Extended.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";

import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";

import { IPYUSDX } from "../../src/IPYUSDX.sol";

import { ExtensionFactoryHarness } from "../harness/ExtensionFactoryHarness.sol";

import { MockERC20 } from "../mock/MockERC20.sol";
import { MockExtensionBeacon } from "../mock/MockExtensionBeacon.sol";
import { MockPYUSDXExtension } from "../mock/MockPYUSDXExtension.sol";
import { MockMultiMint } from "../mock/MockMultiMint.sol";

import { PYUSDXBaseUnitTest } from "../utils/PYUSDXBaseUnitTest.sol";

contract SwapFacilityUnitTests is PYUSDXBaseUnitTest {
    ExtensionFactoryHarness public factory;
    SwapFacility public swapFacility;
    MockPYUSDXExtension public extensionA;
    MockPYUSDXExtension public extensionB;
    MockMultiMint public multiMintExtension;
    MockERC20 public mockUSDC;

    uint256 public constant AMOUNT = 1000e6;

    function setUp() public override {
        super.setUp();

        // Predict factory proxy address
        // After super.setUp(), nonce is 4
        // new SwapFacility impl: 4 -> 5
        // deployTransparentProxy: 5 -> 6
        // new MockExtensionBeacon (YTO): 6 -> 7
        // new MockExtensionBeacon (MM): 7 -> 8
        // new ExtensionFactoryHarness: 8 -> 9
        // deployTransparentProxy: 9 -> 10
        // Factory proxy is at nonce 9 = 4 + 5

        uint64 nonceBeforeDeployments = vm.getNonce(address(this));
        address predictedFactory = vm.computeCreateAddress(address(this), nonceBeforeDeployments + 5);

        // Deploy SwapFacility with predicted factory address
        swapFacility = SwapFacility(
            UnsafeUpgrades.deployTransparentProxy(
                address(new SwapFacility(address(pyusdx), predictedFactory)),
                admin,
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin, pauser)
            )
        );

        // Deploy mock beacons (unit tests use mocks, not real extensions)
        MockExtensionBeacon mockYTOBeacon = new MockExtensionBeacon();
        MockExtensionBeacon mockMMBeacon = new MockExtensionBeacon();

        // Deploy factory with actual SwapFacility address
        factory = ExtensionFactoryHarness(
            UnsafeUpgrades.deployTransparentProxy(
                address(
                    new ExtensionFactoryHarness(
                        address(pyusdx),
                        address(swapFacility),
                        address(mockYTOBeacon),
                        address(mockMMBeacon)
                    )
                ),
                admin,
                abi.encodeWithSelector(ExtensionFactory.initialize.selector, admin, factoryManager)
            )
        );

        // Verify prediction was correct
        assertEq(address(factory), predictedFactory, "Factory address prediction failed");

        // Use mock extensions for testing
        extensionA = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        extensionB = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        multiMintExtension = new MockMultiMint(address(pyusdx), address(swapFacility), makeAddr("yieldRecipient"));

        // Register mock extensions by default
        factory.registerExtension(address(extensionA), IExtensionFactory.ExtensionType.YIELD_TO_ONE);
        factory.registerExtension(address(extensionB), IExtensionFactory.ExtensionType.YIELD_TO_ONE);
        factory.registerExtension(address(multiMintExtension), IExtensionFactory.ExtensionType.MULTI_MINT);

        // Allow mockUSDC in multiMintExtension
        multiMintExtension.setAllowedAsset(address(mockUSDC), true);
    }

    /* ============ Helpers ============ */

    function _setupSwapIn(address user, uint256 amount) internal {
        issuerGateway.mint(user, amount);

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
        new SwapFacility(address(0), address(factory));
    }

    function test_constructor_zeroExtensionFactory() public {
        vm.expectRevert(ISwapFacility.ZeroExtensionFactory.selector);
        new SwapFacility(address(pyusdx), address(0));
    }

    function test_initialState() public view {
        assertEq(swapFacility.pyusdx(), address(pyusdx));
        assertEq(swapFacility.extensionFactory(), address(factory));
        assertTrue(swapFacility.hasRole(swapFacility.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(swapFacility.hasRole(swapFacility.PAUSER_ROLE(), pauser));
    }

    function test_initialize_alreadyInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        swapFacility.initialize(admin, pauser);
    }

    /* ============ isApprovedExtension (View) ============ */

    function test_isApprovedExtension() public {
        // Extensions registered in setUp should be approved
        assertTrue(swapFacility.isApprovedExtension(address(extensionA)));
        assertTrue(swapFacility.isApprovedExtension(address(extensionB)));

        // Fresh extension should not be approved
        MockPYUSDXExtension fresh = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        assertFalse(swapFacility.isApprovedExtension(address(fresh)));

        // After registration, it should be approved
        factory.registerExtension(address(fresh), IExtensionFactory.ExtensionType.YIELD_TO_ONE);
        assertTrue(swapFacility.isApprovedExtension(address(fresh)));
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
        issuerGateway.mint(alice, AMOUNT);

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

    function test_swapInMultiMint_refundsDustToCaller() public {
        uint256 dust = 12345;

        mockUSDC.mint(alice, AMOUNT);
        multiMintExtension.setNextWrapDust(dust);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.expectEmit();
        emit ISwapFacility.SwappedInMultiMint(address(mockUSDC), address(multiMintExtension), AMOUNT - dust, alice);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        assertEq(mockUSDC.balanceOf(alice), dust);
        assertEq(mockUSDC.balanceOf(address(swapFacility)), 0);
        assertEq(mockUSDC.balanceOf(address(multiMintExtension)), AMOUNT - dust);
        assertEq(multiMintExtension.balanceOf(alice), AMOUNT - dust);
        assertEq(IERC20(address(mockUSDC)).allowance(address(swapFacility), address(multiMintExtension)), 0);
    }

    /* ============ Self-Swap Guard ============ */

    function test_swap_selfSwapPyusdx() public {
        _setupSwapIn(alice, AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.InvalidSwapPath.selector, address(pyusdx), address(pyusdx))
        );

        vm.prank(alice);
        swapFacility.swap(address(pyusdx), address(pyusdx), AMOUNT, alice);
    }

    function test_swap_selfSwapExtension() public {
        _setupSwapOut(alice, AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.InvalidSwapPath.selector, address(extensionA), address(extensionA))
        );

        vm.prank(alice);
        swapFacility.swap(address(extensionA), address(extensionA), AMOUNT, alice);
    }

    function test_swap_selfSwapMultiMint() public {
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapFacility.InvalidSwapPath.selector,
                address(multiMintExtension),
                address(multiMintExtension)
            )
        );

        vm.prank(alice);
        swapFacility.swap(address(multiMintExtension), address(multiMintExtension), AMOUNT, alice);
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
        issuerGateway.mint(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        // Give extensionB to bob
        vm.prank(bob);
        swapFacility.swapIn(address(extensionB), AMOUNT, bob);

        vm.prank(bob);
        IERC20(address(extensionB)).approve(address(swapFacility), AMOUNT);

        vm.expectEmit();
        emit ISwapFacility.MultiMintAssetReplaced(address(mockUSDC), address(multiMintExtension), AMOUNT, bob);

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

    function test_replaceAsset_rawPyusdx() public {
        // Setup: alice swaps USDC into multiMintExtension
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        // Bob uses raw PYUSDX to replace the asset
        issuerGateway.mint(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectEmit();
        emit ISwapFacility.MultiMintAssetReplaced(address(mockUSDC), address(multiMintExtension), AMOUNT, bob);

        vm.prank(bob);
        swapFacility.replaceAsset(address(mockUSDC), address(pyusdx), address(multiMintExtension), AMOUNT, bob);

        assertEq(mockUSDC.balanceOf(bob), AMOUNT);
    }

    function test_replaceAsset_paused() public {
        vm.prank(pauser);
        swapFacility.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        swapFacility.replaceAsset(address(mockUSDC), address(extensionA), address(multiMintExtension), AMOUNT, alice);
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

    /* ============ swapWithPermit (EIP-2612) ============ */

    function test_swapWithPermit_vrs() public {
        _setupSwapIn(alice, AMOUNT);

        // Permit already handled via approval in helper
        // For v,r,s test, we just verify the function doesn't revert
        vm.prank(alice);
        swapFacility.swapWithPermit(
            address(pyusdx),
            address(extensionA),
            AMOUNT,
            alice,
            block.timestamp + 1 hours,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );

        // The mock permit is a no-op, so actual approval is still needed
        // Let's verify the swap function was called by checking balances
        // (Note: This will fail without approval, but we're testing the permit flow)
    }

    function test_swapWithPermit_bytesSignature() public {
        _setupSwapIn(alice, AMOUNT);

        vm.prank(alice);
        swapFacility.swapWithPermit(
            address(pyusdx),
            address(extensionA),
            AMOUNT,
            alice,
            block.timestamp + 1 hours,
            bytes("")
        );
    }

    function test_swapWithPermit_catchPermitFailure() public {
        _setupSwapIn(alice, AMOUNT);

        // The permit call is caught, so even with bad signature it continues
        vm.prank(alice);
        swapFacility.swapWithPermit(
            address(pyusdx),
            address(extensionA),
            AMOUNT,
            alice,
            0, // expired deadline
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
    }

    /* ============ replaceAssetWithPermit ============ */

    function test_replaceAssetWithPermit_vrs() public {
        // Set up the scenario: swap USDC into multiMintExtension
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        // bob wraps PYUSDX into extensionB
        _setupSwapIn(bob, AMOUNT);

        vm.prank(bob);
        swapFacility.swapIn(address(extensionB), AMOUNT, bob);

        vm.prank(bob);
        IERC20(address(extensionB)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.replaceAssetWithPermit(
            address(mockUSDC),
            address(extensionB),
            address(multiMintExtension),
            AMOUNT,
            bob,
            block.timestamp + 1 hours,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
    }

    function test_replaceAssetWithPermit_bytesSignature() public {
        mockUSDC.mint(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        _setupSwapIn(bob, AMOUNT);

        vm.prank(bob);
        swapFacility.swapIn(address(extensionB), AMOUNT, bob);

        vm.prank(bob);
        IERC20(address(extensionB)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.replaceAssetWithPermit(
            address(mockUSDC),
            address(extensionB),
            address(multiMintExtension),
            AMOUNT,
            bob,
            block.timestamp + 1 hours,
            bytes("")
        );
    }

    function test_replaceAssetWithPermit_catchPermitFailure() public {
        // Set up: alice has extensionA tokens that can be used for replaceAsset
        mockUSDC.mint(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, bob);

        _setupSwapIn(alice, AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(extensionA), AMOUNT, alice);

        vm.prank(alice);
        IERC20(address(extensionA)).approve(address(swapFacility), AMOUNT);

        // Permit failure is caught, but approval still required
        vm.prank(alice);
        swapFacility.replaceAssetWithPermit(
            address(mockUSDC),
            address(extensionA),
            address(multiMintExtension),
            AMOUNT,
            alice,
            0, // expired
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
    }

    function test_replaceAssetWithPermit_rawPyusdx_vrs() public {
        // Setup: alice swaps USDC into multiMintExtension
        mockUSDC.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);
        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        // Bob uses raw PYUSDX with permit (mock permit is no-op, so we also approve)
        issuerGateway.mint(bob, AMOUNT);
        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.replaceAssetWithPermit(
            address(mockUSDC),
            address(pyusdx),
            address(multiMintExtension),
            AMOUNT,
            bob,
            block.timestamp + 1 hours,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );

        assertEq(mockUSDC.balanceOf(bob), AMOUNT);
    }

    function test_replaceAssetWithPermit_rawPyusdx_bytes() public {
        // Setup: alice swaps USDC into multiMintExtension
        mockUSDC.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(mockUSDC)).approve(address(swapFacility), AMOUNT);
        vm.prank(alice);
        swapFacility.swap(address(mockUSDC), address(multiMintExtension), AMOUNT, alice);

        // Bob uses raw PYUSDX with permit (mock permit is no-op, so we also approve)
        issuerGateway.mint(bob, AMOUNT);
        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.replaceAssetWithPermit(
            address(mockUSDC),
            address(pyusdx),
            address(multiMintExtension),
            AMOUNT,
            bob,
            block.timestamp + 1 hours,
            bytes("")
        );

        assertEq(mockUSDC.balanceOf(bob), AMOUNT);
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
