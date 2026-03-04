// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { UnsafeUpgrades } from "../../lib/m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20Extended.sol";

import { IPYUSDXExtensionFactory } from "../../src/deploy/interfaces/IPYUSDXExtensionFactory.sol";
import { MinterGateway } from "../../src/MinterGateway.sol";
import { MultiMint } from "../../src/MultiMint.sol";
import { PYUSDXExtensionFactory } from "../../src/deploy/PYUSDXExtensionFactory.sol";
import { PYUSDX } from "../../src/PYUSDX.sol";
import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { IAccessControl } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { YieldToOne } from "../../src/YieldToOne.sol";
import { BaseForkTest } from "../utils/BaseForkTest.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";

contract SwapFacilityIntegrationTests is BaseForkTest {
    MinterGateway public minterGateway;
    PYUSDXHarness public pyusdx;

    PYUSDXExtensionFactory public factory;
    SwapFacility public swapFacility;
    YieldToOne public yieldToOne;
    MultiMint public multiMintExtension;

    uint256 public constant AMOUNT = 1000e6;
    uint32 public constant MINT_DELAY = 1; // 1 second for testing
    uint32 public constant MINT_TTL = 3600; // 1 hour

    function setUp() public override {
        super.setUp();

        // Step 1: Predict MinterGateway proxy address
        // PYUSDX implementation: nonce N
        // PYUSDX proxy: nonce N+1
        // MinterGateway implementation: nonce N+2
        // MinterGateway proxy: nonce N+3 (this is what we predict)
        uint64 nonceBeforePYUSDX = vm.getNonce(address(this));
        address predictedMinterGateway = vm.computeCreateAddress(address(this), nonceBeforePYUSDX + 3);

        // Step 2: Deploy PYUSDX with predicted MinterGateway proxy address (immutable baked in)
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

        // Step 3: Deploy MinterGateway with actual PYUSDX address
        minterGateway = MinterGateway(
            UnsafeUpgrades.deployTransparentProxy(
                address(new MinterGateway(address(pyusdx))),
                admin,
                abi.encodeWithSelector(MinterGateway.initialize.selector, admin, minter, MINT_DELAY, MINT_TTL)
            )
        );

        // Verify prediction was correct
        assertEq(address(minterGateway), predictedMinterGateway, "MinterGateway address prediction failed");

        // Step 4: Predict factory address
        // new SwapFacility impl: N+1
        // deployTransparentProxy: N+2
        // new Factory impl: N+3
        // deployTransparentProxy: N+4 (factory proxy)
        address predictedFactory = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);

        // Step 5: Deploy SwapFacility with predicted factory address
        swapFacility = SwapFacility(
            UnsafeUpgrades.deployTransparentProxy(
                address(new SwapFacility(address(pyusdx), predictedFactory)),
                admin,
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin, pauser)
            )
        );

        // Step 6: Deploy factory with actual SwapFacility address
        factory = PYUSDXExtensionFactory(
            UnsafeUpgrades.deployTransparentProxy(
                address(new PYUSDXExtensionFactory(address(pyusdx), address(swapFacility))),
                admin,
                abi.encodeWithSelector(PYUSDXExtensionFactory.initialize.selector, admin, factoryManager)
            )
        );

        // Verify factory prediction was correct
        assertEq(address(factory), predictedFactory);

        // Step 7: Deploy YieldToOne through factory
        vm.prank(admin);
        (address yieldToOneProxy, , ) = factory.deployYieldToOne(
            "YieldToOne",
            "YTO",
            yieldRecipient,
            admin,
            freezeManager,
            admin,
            pauser
        );
        yieldToOne = YieldToOne(yieldToOneProxy);

        // Step 8: Enable earning for YieldToOne
        vm.prank(earnerManager);
        pyusdx.setEarningDetails(address(yieldToOne), true, 0, yieldRecipient);

        // Step 9: Deploy MultiMint through factory
        vm.prank(admin);
        (address multiMintProxy, , ) = factory.deployMultiMint(
            "MultiMint",
            "MM",
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            admin
        );
        multiMintExtension = MultiMint(multiMintProxy);

        // Step 10: Allow USDC in MultiMint by setting asset cap
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

    /* ============ Factory Tests ============ */

    function testIntegration_factory_state() public view {
        assertEq(factory.pyusdx(), address(pyusdx));
        assertEq(factory.swapFacility(), address(swapFacility));
        assertTrue(factory.isApprovedExtension(address(yieldToOne)));
        assertTrue(factory.isApprovedExtension(address(multiMintExtension)));
        assertEq(
            uint8(factory.getExtensionType(address(yieldToOne))),
            uint8(IPYUSDXExtensionFactory.ExtensionType.YIELD_TO_ONE)
        );
        assertEq(
            uint8(factory.getExtensionType(address(multiMintExtension))),
            uint8(IPYUSDXExtensionFactory.ExtensionType.MULTI_MINT)
        );
    }

    function testIntegration_factory_extensionType() public view {
        assertEq(
            uint8(factory.getExtensionType(address(yieldToOne))),
            uint8(IPYUSDXExtensionFactory.ExtensionType.YIELD_TO_ONE)
        );
        assertEq(
            uint8(factory.getExtensionType(address(multiMintExtension))),
            uint8(IPYUSDXExtensionFactory.ExtensionType.MULTI_MINT)
        );
    }

    function testIntegration_factory_setExtensionStatus() public {
        // Verify initial state
        assertTrue(factory.isApprovedExtension(address(yieldToOne)));

        // Deactivate
        vm.expectEmit();
        emit IPYUSDXExtensionFactory.ExtensionStatusSet(address(yieldToOne), false);

        vm.prank(factoryManager);
        factory.setExtensionStatus(address(yieldToOne), false);

        assertFalse(factory.isApprovedExtension(address(yieldToOne)));
        assertFalse(swapFacility.isApprovedExtension(address(yieldToOne)));

        // Reactivate
        vm.expectEmit();
        emit IPYUSDXExtensionFactory.ExtensionStatusSet(address(yieldToOne), true);

        vm.prank(factoryManager);
        factory.setExtensionStatus(address(yieldToOne), true);

        assertTrue(factory.isApprovedExtension(address(yieldToOne)));
    }

    function testIntegration_factory_setExtensionStatus_idempotent() public {
        // Should not emit event when setting to same value
        vm.prank(factoryManager);
        factory.setExtensionStatus(address(yieldToOne), true); // Already true

        assertTrue(factory.isApprovedExtension(address(yieldToOne)));
    }

    function testIntegration_factory_setExtensionStatus_notManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                factory.FACTORY_MANAGER_ROLE()
            )
        );

        vm.prank(alice);
        factory.setExtensionStatus(address(yieldToOne), false);
    }

    function testIntegration_factory_setExtensionStatus_notRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(IPYUSDXExtensionFactory.ExtensionNotRegistered.selector, alice));

        vm.prank(factoryManager);
        factory.setExtensionStatus(alice, false);
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

    function testIntegration_swap_notApprovedExtension() public {
        // Deploy an extension outside the factory
        address unapprovedYTO = UnsafeUpgrades.deployTransparentProxy(
            address(new YieldToOne(address(pyusdx), address(swapFacility))),
            admin,
            abi.encodeWithSelector(
                YieldToOne.initialize.selector,
                "Unapproved",
                "UNAPR",
                yieldRecipient,
                admin,
                freezeManager,
                admin,
                pauser
            )
        );

        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, unapprovedYTO));

        vm.prank(alice);
        swapFacility.swapIn(unapprovedYTO, AMOUNT, alice);
    }

    function testIntegration_swap_revocationEndToEnd() public {
        // Setup: swap in to yieldToOne
        _mintPYUSDX(alice, AMOUNT);

        vm.prank(alice);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.prank(alice);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, alice);

        assertEq(yieldToOne.balanceOf(alice), AMOUNT);

        // Revoke extension
        vm.prank(factoryManager);
        factory.setExtensionStatus(address(yieldToOne), false);

        // Verify swapFacility rejects the extension
        assertFalse(swapFacility.isApprovedExtension(address(yieldToOne)));

        // Attempting to swap in should fail
        _mintPYUSDX(bob, AMOUNT);

        vm.prank(bob);
        IERC20(address(pyusdx)).approve(address(swapFacility), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, address(yieldToOne)));

        vm.prank(bob);
        swapFacility.swapIn(address(yieldToOne), AMOUNT, bob);
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
}
