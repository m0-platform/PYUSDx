// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { UnsafeUpgrades } from "../../lib/m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20Extended.sol";

import { MinterGateway } from "../../src/MinterGateway.sol";
import { MultiMint } from "../../src/MultiMint.sol";
import { PYUSDX } from "../../src/PYUSDX.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { YieldToOne } from "../../src/YieldToOne.sol";
import { BaseForkTest } from "../utils/BaseForkTest.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";

contract SwapFacilityIntegrationTests is BaseForkTest {
    MinterGateway public minterGateway;
    PYUSDXHarness public pyusdx;

    SwapFacility public swapFacility;
    YieldToOne public yieldToOne;
    MultiMint public multiMintExtension;

    uint256 public constant AMOUNT = 1000e6;
    uint32 public constant MINT_DELAY = 1; // 1 second for testing
    uint32 public constant MINT_TTL = 3600; // 1 hour

    function setUp() public override {
        super.setUp();

        // Predict MinterGateway proxy address
        // PYUSDX implementation: nonce N
        // PYUSDX proxy: nonce N+1
        // MinterGateway implementation: nonce N+2
        // MinterGateway proxy: nonce N+3 (this is what we predict)
        uint64 nonceBeforePYUSDX = vm.getNonce(address(this));
        address predictedMinterGateway = vm.computeCreateAddress(address(this), nonceBeforePYUSDX + 3);

        // Deploy PYUSDX with predicted MinterGateway proxy address (immutable baked in)
        pyusdx = PYUSDXHarness(
            UnsafeUpgrades.deployTransparentProxy(
                address(new PYUSDXHarness(predictedMinterGateway)),
                admin,
                abi.encodeWithSelector(
                    PYUSDX.initialize.selector,
                    "PayPal USD Yield",
                    "PYUSDX",
                    admin,
                    pauser,
                    freezeManager,
                    forcedTransferManager,
                    earnerManager,
                    rateManager
                )
            )
        );

        // Deploy MinterGateway with actual PYUSDX address
        minterGateway = MinterGateway(
            UnsafeUpgrades.deployTransparentProxy(
                address(new MinterGateway(address(pyusdx))),
                admin,
                abi.encodeWithSelector(MinterGateway.initialize.selector, admin, minter, MINT_DELAY, MINT_TTL)
            )
        );

        // Verify prediction was correct
        assertEq(address(minterGateway), predictedMinterGateway, "MinterGateway address prediction failed");

        swapFacility = SwapFacility(
            UnsafeUpgrades.deployTransparentProxy(
                address(new SwapFacility(address(pyusdx))),
                admin,
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin, pauser)
            )
        );

        yieldToOne = YieldToOne(
            UnsafeUpgrades.deployTransparentProxy(
                address(new YieldToOne(address(pyusdx), address(swapFacility))),
                admin,
                abi.encodeWithSelector(
                    YieldToOne.initialize.selector,
                    "YieldToOne",
                    "YTO",
                    yieldRecipient,
                    admin,
                    freezeManager,
                    admin,
                    pauser
                )
            )
        );

        vm.prank(earnerManager);
        pyusdx.setEarningDetails(address(yieldToOne), true, 0, yieldRecipient);

        // Deploy MultiMint
        multiMintExtension = MultiMint(
            UnsafeUpgrades.deployTransparentProxy(
                address(new MultiMint(address(pyusdx), address(swapFacility))),
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
                    admin
                )
            )
        );

        vm.startPrank(admin);

        swapFacility.setApprovedExtension(address(yieldToOne), true);
        swapFacility.setApprovedExtension(address(multiMintExtension), true);

        vm.stopPrank();

        // Allow USDC in MultiMint by setting asset cap
        vm.prank(assetCapManager);
        multiMintExtension.setAssetCap(address(USDC), type(uint256).max);
    }

    /// @dev Helper to mint PYUSDX through the time-delay mechanism
    function _mintPYUSDX(address recipient, uint256 amount) internal {
        vm.prank(minter);
        uint48 mintId = minterGateway.proposeMint(amount, recipient);

        vm.warp(block.timestamp + MINT_DELAY);

        minterGateway.mint(mintId);
    }

    /* ============ Swap Tests ============ */

    function testIntegration_swap_USDC() public {
        // Deal USDC from whale
        _dealUSDC(alice, AMOUNT);

        uint256 initialBalance = USDC.balanceOf(alice);
        assertEq(initialBalance, AMOUNT);

        // Approve and swap
        vm.prank(alice);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(USDC), address(multiMintExtension), AMOUNT, alice);

        // Verify swap
        assertEq(USDC.balanceOf(alice), 0);
        assertEq(multiMintExtension.balanceOf(alice), AMOUNT);
    }

    function testIntegration_swap_differentRecipient() public {
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swap(address(pyusdx), address(yieldToOne), AMOUNT, bob);

        assertEq(yieldToOne.balanceOf(bob), AMOUNT);
        assertEq(pyusdx.balanceOf(alice), 0);
    }

    function testIntegration_swapIn() public {
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        assertEq(yieldToOne.balanceOf(alice), AMOUNT);
        assertEq(pyusdx.balanceOf(alice), 0);
    }

    function testIntegration_swapOut() public {
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);
        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        vm.prank(alice);
        IERC20(address(yieldToOne)).approve(address(swapFacility), AMOUNT);
        vm.prank(alice);
        swapFacility.swapOut(address(yieldToOne), AMOUNT, alice);

        assertEq(pyusdx.balanceOf(alice), AMOUNT);
        assertEq(yieldToOne.balanceOf(alice), 0);
    }

    /* ============ replaceAsset Tests ============ */

    function testIntegration_replaceAsset_rawPYUSDX() public {
        _dealUSDC(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.swap(address(USDC), address(multiMintExtension), AMOUNT, bob);

        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.replaceAsset(address(USDC), address(pyusdx), address(multiMintExtension), AMOUNT, alice);

        assertEq(USDC.balanceOf(alice), AMOUNT);
    }

    function testIntegration_replaceAsset_extension() public {
        // Setup: bob swaps USDC into multiMintExtension
        _dealUSDC(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.swap(address(USDC), address(multiMintExtension), AMOUNT, bob);

        // Alice gets YieldToOne extension tokens
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        // Alice uses YieldToOne to replace USDC asset
        vm.prank(alice);
        IERC20(address(yieldToOne)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.replaceAsset(address(USDC), address(yieldToOne), address(multiMintExtension), AMOUNT, alice);

        assertEq(USDC.balanceOf(alice), AMOUNT);
    }

    /* ============ Permit Tests: swapWithPermit ============ */

    function testIntegration_swapWithPermit_pyusdxToExtension() public {
        _mintPYUSDX(alice, AMOUNT);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            address(pyusdx),
            address(swapFacility),
            alice,
            aliceKey,
            AMOUNT,
            pyusdx.nonces(alice),
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.swapWithPermit(address(pyusdx), address(yieldToOne), AMOUNT, alice, block.timestamp, v, r, s);

        assertEq(yieldToOne.balanceOf(alice), AMOUNT);
        assertEq(pyusdx.balanceOf(alice), 0);
    }

    function testIntegration_swapWithPermit_extensionToPyusdx() public {
        // Setup: alice already has extension tokens
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        // Swap back using permit
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            address(yieldToOne),
            address(swapFacility),
            alice,
            aliceKey,
            AMOUNT,
            yieldToOne.nonces(alice),
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.swapWithPermit(address(yieldToOne), address(pyusdx), AMOUNT, alice, block.timestamp, v, r, s);

        assertEq(pyusdx.balanceOf(alice), AMOUNT);
        assertEq(yieldToOne.balanceOf(alice), 0);
    }

    function testIntegration_swapWithPermit_bytesSignature() public {
        _mintPYUSDX(alice, AMOUNT);

        bytes memory signature = _getPermitSignatureBytes(
            address(pyusdx),
            address(swapFacility),
            alice,
            aliceKey,
            AMOUNT,
            pyusdx.nonces(alice),
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.swapWithPermit(address(pyusdx), address(yieldToOne), AMOUNT, alice, block.timestamp, signature);

        assertEq(yieldToOne.balanceOf(alice), AMOUNT);
    }

    function testIntegration_swapWithPermit_extensionToExtension() public {
        // Setup: alice has yieldToOne tokens
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            address(yieldToOne),
            address(swapFacility),
            alice,
            aliceKey,
            AMOUNT,
            yieldToOne.nonces(alice),
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.swapWithPermit(
            address(yieldToOne),
            address(multiMintExtension),
            AMOUNT,
            alice,
            block.timestamp,
            v,
            r,
            s
        );

        assertEq(multiMintExtension.balanceOf(alice), AMOUNT);
        assertEq(yieldToOne.balanceOf(alice), 0);
    }

    function testIntegration_swapWithPermit_expiredDeadline() public {
        _mintPYUSDX(alice, AMOUNT);

        uint256 expiredDeadline = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            address(pyusdx),
            address(swapFacility),
            alice,
            aliceKey,
            AMOUNT,
            pyusdx.nonces(alice),
            expiredDeadline
        );

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Extended.InsufficientAllowance.selector, address(swapFacility), 0, AMOUNT)
        );

        vm.prank(alice);
        swapFacility.swapWithPermit(address(pyusdx), address(yieldToOne), AMOUNT, alice, expiredDeadline, v, r, s);
    }

    function testIntegration_swapWithPermit_wrongSigner() public {
        _mintPYUSDX(alice, AMOUNT);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            address(pyusdx),
            address(swapFacility),
            alice,
            bobKey, // Wrong signer
            AMOUNT,
            pyusdx.nonces(alice),
            block.timestamp
        );

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Extended.InsufficientAllowance.selector, address(swapFacility), 0, AMOUNT)
        );
        vm.prank(alice);
        swapFacility.swapWithPermit(address(pyusdx), address(yieldToOne), AMOUNT, alice, block.timestamp, v, r, s);
    }

    /* ============ Permit Tests: replaceAssetWithPermit ============ */

    function testIntegration_replaceAssetWithPermit_rawPYUSDX() public {
        // Setup: bob swaps USDC into multiMintExtension
        _dealUSDC(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.swap(address(USDC), address(multiMintExtension), AMOUNT, bob);

        // Alice replaces with raw PYUSDX using permit
        _mintPYUSDX(alice, AMOUNT);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            address(pyusdx),
            address(swapFacility),
            alice,
            aliceKey,
            AMOUNT,
            pyusdx.nonces(alice),
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.replaceAssetWithPermit(
            address(USDC),
            address(pyusdx),
            address(multiMintExtension),
            AMOUNT,
            alice,
            block.timestamp,
            v,
            r,
            s
        );

        assertEq(USDC.balanceOf(alice), AMOUNT);
    }

    function testIntegration_replaceAssetWithPermit_extension() public {
        // Setup: bob swaps USDC into multiMintExtension
        _dealUSDC(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.swap(address(USDC), address(multiMintExtension), AMOUNT, bob);

        // Alice gets extension tokens
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            address(yieldToOne),
            address(swapFacility),
            alice,
            aliceKey,
            AMOUNT,
            yieldToOne.nonces(alice),
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.replaceAssetWithPermit(
            address(USDC),
            address(yieldToOne),
            address(multiMintExtension),
            AMOUNT,
            alice,
            block.timestamp,
            v,
            r,
            s
        );

        assertEq(USDC.balanceOf(alice), AMOUNT);
    }

    function testIntegration_replaceAssetWithPermit_extension_bytesSignature() public {
        // Setup: bob swaps USDC into multiMintExtension
        _dealUSDC(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(USDC)).approve(address(swapFacility), AMOUNT);

        vm.prank(bob);
        swapFacility.swap(address(USDC), address(multiMintExtension), AMOUNT, bob);

        // Alice gets extension tokens
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        bytes memory signature = _getPermitSignatureBytes(
            address(yieldToOne),
            address(swapFacility),
            alice,
            aliceKey,
            AMOUNT,
            yieldToOne.nonces(alice),
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.replaceAssetWithPermit(
            address(USDC),
            address(yieldToOne),
            address(multiMintExtension),
            AMOUNT,
            alice,
            block.timestamp,
            signature
        );

        assertEq(USDC.balanceOf(alice), AMOUNT);
    }
}
