// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20Extended.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";

import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

contract SwapFacilityIntegrationTests is IntegrationForkTest {
    YieldToOne public yieldToOne;
    MultiMint public multiMintExtension;

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
        (address yieldToOneProxy, ) = factory.deployYieldToOne(string("yto-swap-integration"), ytoParams);
        yieldToOne = YieldToOne(yieldToOneProxy);

        // Enable earning for YieldToOne
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(address(yieldToOne), 500, 0, yieldRecipient);

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
        (address multiMintProxy, ) = factory.deployMultiMint(string("mm-swap-integration"), mmParams);
        multiMintExtension = MultiMint(multiMintProxy);

        // Whitelist USDC globally on the MultiMint beacon, then allow it in MultiMint by setting asset cap
        vm.prank(beaconManager);
        multiMintBeacon.setAssetWhitelist(address(USDC), true);

        vm.prank(assetCapManager);
        multiMintExtension.setAssetCap(address(USDC), type(uint256).max);
    }

    /* ============ Factory Tests ============ */

    function testIntegration_factory_state() public view {
        assertEq(factory.pyusdx(), address(pyusdx));
        assertEq(factory.swapFacility(), address(swapFacility));
        assertTrue(factory.isApprovedExtension(address(yieldToOne)));
        assertTrue(factory.isApprovedExtension(address(multiMintExtension)));
        assertEq(
            uint8(factory.getExtensionType(address(yieldToOne))),
            uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE)
        );
        assertEq(
            uint8(factory.getExtensionType(address(multiMintExtension))),
            uint8(IExtensionFactory.ExtensionType.MULTI_MINT)
        );
    }

    function testIntegration_factory_extensionType() public view {
        assertEq(
            uint8(factory.getExtensionType(address(yieldToOne))),
            uint8(IExtensionFactory.ExtensionType.YIELD_TO_ONE)
        );
        assertEq(
            uint8(factory.getExtensionType(address(multiMintExtension))),
            uint8(IExtensionFactory.ExtensionType.MULTI_MINT)
        );
    }

    function testIntegration_factory_setExtensionStatus() public {
        // Verify initial state
        assertTrue(factory.isApprovedExtension(address(yieldToOne)));

        // Deactivate
        vm.expectEmit();
        emit IExtensionFactory.ExtensionTypeSet(address(yieldToOne), IExtensionFactory.ExtensionType.NONE);

        vm.prank(factoryManager);
        factory.setExtensionType(address(yieldToOne), IExtensionFactory.ExtensionType.NONE);

        assertFalse(factory.isApprovedExtension(address(yieldToOne)));
        assertFalse(swapFacility.isApprovedExtension(address(yieldToOne)));

        // Reactivate
        vm.expectEmit();
        emit IExtensionFactory.ExtensionTypeSet(address(yieldToOne), IExtensionFactory.ExtensionType.YIELD_TO_ONE);

        vm.prank(factoryManager);
        factory.setExtensionType(address(yieldToOne), IExtensionFactory.ExtensionType.YIELD_TO_ONE);

        assertTrue(factory.isApprovedExtension(address(yieldToOne)));
    }

    function testIntegration_factory_setExtensionStatus_idempotent() public {
        // Should not emit event when setting to same value
        vm.prank(factoryManager);
        factory.setExtensionType(address(yieldToOne), IExtensionFactory.ExtensionType.YIELD_TO_ONE); // Already true

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
        factory.setExtensionType(address(yieldToOne), IExtensionFactory.ExtensionType.NONE);
    }

    function testIntegration_factory_setExtensionStatus_notRegistered() public {
        // Setting NONE on unregistered address is idempotent (no-op, no revert)
        vm.prank(factoryManager);
        factory.setExtensionType(alice, IExtensionFactory.ExtensionType.NONE);

        // Setting non-NONE on an invalid address reverts (EOA has no code, call to IExtension interface fails)
        vm.expectRevert();

        vm.prank(factoryManager);
        factory.setExtensionType(alice, IExtensionFactory.ExtensionType.YIELD_TO_ONE);
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
                pauser,
                yieldRecipientManager,
                versionManager
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
        factory.setExtensionType(address(yieldToOne), IExtensionFactory.ExtensionType.NONE);

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
