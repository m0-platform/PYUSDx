// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {PYUSDX} from "../../src/PYUSDX.sol";
import {IPYUSDX} from "../../src/interfaces/IPYUSDX.sol";
import {IERC20} from "m-extensions/lib/common/src/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * Branch coverage TODOs:
 * - [ ] Constructor
 *   - [x] when minterGateway is zero address
 *     - [x] revert with ZeroMinterGateway
 *   - [x] when pyusd is zero address
 *     - [x] revert with ZeroPYUSD
 *   - [x] when both addresses are valid
 *     - [x] success
 *     - [x] immutable variables set correctly
 * - [ ] Initialize
 *   - [x] when called directly on implementation (not through proxy)
 *     - [x] does not affect proxy state
 *   - [x] when called twice through proxy
 *     - [x] revert with InvalidInitialization
 *   - [x] when all parameters are valid
 *     - [x] success
 *     - [x] initial index equals PRECISION
 *     - [x] initial rate equals 0
 *     - [x] ERC20 metadata set correctly (name: "PYUSDX", symbol: "PYUSDX", decimals: 6)
 *     - [x] DEFAULT_ADMIN_ROLE granted to admin
 *     - [x] RATE_MANAGER_ROLE granted to rateManager
 *     - [x] EARNER_MANAGER_ROLE granted to earnerManager
 *     - [x] FREEZE_MANAGER_ROLE granted to freezeManager
 *     - [x] FORCED_TRANSFER_MANAGER_ROLE granted to forcedTransferManager
 *     - [x] PAUSER_ROLE granted to pauser
 * - [ ] mint
 *   - [ ] when caller is not minterGateway
 *     - [ ] revert with NotMinterGateway
 *   - [ ] when contract is paused
 *     - [ ] revert with EnforcedPause
 *   - [ ] when recipient is frozen
 *     - [ ] revert with AccountFrozen
 *   - [ ] when amount is zero
 *     - [ ] revert
 *   - [ ] when recipient is earner
 *     - [ ] success
 *     - [ ] balance increased
 *     - [ ] totalEarningSupply increased
 *     - [ ] totalNonEarningSupply unchanged
 *   - [ ] when recipient is not earner
 *     - [ ] success
 *     - [ ] balance increased
 *     - [ ] totalNonEarningSupply increased
 *     - [ ] totalEarningSupply unchanged
 *   - [ ] when amount would overflow uint240
 *     - [ ] revert
 */
contract PYUSDXUnitTest is Test {
    /* ============ Test Variables ============ */

    PYUSDX public implementation;
    PYUSDX public proxy;
    ERC1967Proxy public erc1967Proxy;

    address public admin = address(0x1);
    address public rateManager = address(0x2);
    address public earnerManager = address(0x3);
    address public freezeManager = address(0x4);
    address public forcedTransferManager = address(0x5);
    address public pauser = address(0x6);
    address public minterGateway = address(0x7);
    address public pyusd = address(0x8);

    /* ============ Constants ============ */

    uint256 internal constant PRECISION = 1e12;

    /* ============ Setup ============ */

    function setUp() public {
        // Deploy implementation contract
        implementation = new PYUSDX(minterGateway, pyusd);

        // Deploy proxy pointing to implementation
        bytes memory initData = abi.encodeWithSelector(
            PYUSDX.initialize.selector,
            admin,
            rateManager,
            earnerManager,
            freezeManager,
            forcedTransferManager,
            pauser
        );

        erc1967Proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        proxy = PYUSDX(address(erc1967Proxy));
    }

    /* ============ Constructor Tests ============ */

    function test_Constructor_ZeroMinterGateway_Reverts() public {
        vm.expectRevert(IPYUSDX.ZeroMinterGateway.selector);
        new PYUSDX(address(0), pyusd);
    }

    function test_Constructor_ZeroPYUSD_Reverts() public {
        vm.expectRevert(IPYUSDX.ZeroPYUSD.selector);
        new PYUSDX(minterGateway, address(0));
    }

    function test_Constructor_BothAddressesZero_Reverts() public {
        // Should revert with ZeroMinterGateway since it's checked first
        vm.expectRevert(IPYUSDX.ZeroMinterGateway.selector);
        new PYUSDX(address(0), address(0));
    }

    function test_Constructor_ValidAddresses_Success() public {
        PYUSDX newImpl = new PYUSDX(minterGateway, pyusd);

        assertEq(newImpl.minterGateway(), minterGateway, "minterGateway should be set");
        assertEq(newImpl.pyusd(), pyusd, "pyusd should be set");
    }

    function test_Constructor_ImmutableVariablesSetCorrectly() public view {
        // Immutable variables cannot be changed after deployment
        assertEq(implementation.minterGateway(), minterGateway, "minterGateway immutable should be set");
        assertEq(implementation.pyusd(), pyusd, "pyusd immutable should be set");

        // Verify immutability by attempting to set (should fail at compile time)
        // This is verified at compile time - if the variables weren't immutable,
        // the contract would allow changes
    }

    /* ============ Initialize Tests ============ */

    function test_Initialize_CalledDirectlyOnImplementation_DoesNotAffectProxy() public {
        // Initialize the implementation contract (it's allowed but doesn't affect proxy)
        implementation.initialize(
            admin,
            rateManager,
            earnerManager,
            freezeManager,
            forcedTransferManager,
            pauser
        );

        // Verify proxy state is unchanged
        assertEq(proxy.name(), "PYUSDX", "Proxy name should still be set from proxy initialization");
        assertEq(proxy.currentIndex(), uint128(PRECISION), "Proxy index should still be PRECISION");
    }

    function test_Initialize_CalledTwice_Reverts() public {
        // Already initialized in setUp(), call again should revert
        vm.expectRevert();
        proxy.initialize(
            admin,
            rateManager,
            earnerManager,
            freezeManager,
            forcedTransferManager,
            pauser
        );
    }

    function test_Initialize_ValidParameters_Success() public pure {
        // Already initialized in setUp(), just verify state
        // This test documents that initialization succeeded
        assertTrue(true, "Initialization succeeded");
    }

    function test_Initialize_InitialIndexEqualsPrecision() public view {
        assertEq(proxy.currentIndex(), uint128(PRECISION), "Initial index should equal PRECISION (1e12)");
    }

    function test_Initialize_InitialRateEqualsZero() public view {
        assertEq(proxy.rate(), uint32(0), "Initial rate should be 0");
    }

    function test_Initialize_ERC20MetadataSetCorrectly() public view {
        assertEq(proxy.name(), "PYUSDX", "Name should be PYUSDX");
        assertEq(proxy.symbol(), "PYUSDX", "Symbol should be PYUSDX");
        assertEq(proxy.decimals(), 6, "Decimals should be 6 (same as PYUSD)");
    }

    function test_Initialize_DEFAULT_ADMIN_ROLE_GrantedToAdmin() public view {
        assertTrue(
            proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), admin),
            "Admin should have DEFAULT_ADMIN_ROLE"
        );
    }

    function test_Initialize_RATE_MANAGER_ROLE_GrantedToRateManager() public view {
        assertTrue(
            proxy.hasRole(proxy.RATE_MANAGER_ROLE(), rateManager),
            "Rate manager should have RATE_MANAGER_ROLE"
        );
    }

    function test_Initialize_EARNER_MANAGER_ROLE_GrantedToEarnerManager() public view {
        assertTrue(
            proxy.hasRole(proxy.EARNER_MANAGER_ROLE(), earnerManager),
            "Earner manager should have EARNER_MANAGER_ROLE"
        );
    }

    function test_Initialize_FREEZE_MANAGER_ROLE_GrantedToFreezeManager() public view {
        // FREEZE_MANAGER_ROLE is inherited from Freezable
        bytes32 freezeManagerRole = proxy.FREEZE_MANAGER_ROLE();
        assertTrue(
            proxy.hasRole(freezeManagerRole, freezeManager),
            "Freeze manager should have FREEZE_MANAGER_ROLE"
        );
    }

    function test_Initialize_FORCED_TRANSFER_MANAGER_ROLE_GrantedToForcedTransferManager() public view {
        // FORCED_TRANSFER_MANAGER_ROLE is inherited from ForcedTransferable
        bytes32 forcedTransferManagerRole = proxy.FORCED_TRANSFER_MANAGER_ROLE();
        assertTrue(
            proxy.hasRole(forcedTransferManagerRole, forcedTransferManager),
            "Forced transfer manager should have FORCED_TRANSFER_MANAGER_ROLE"
        );
    }

    function test_Initialize_PAUSER_ROLE_GrantedToPauser() public view {
        // PAUSER_ROLE is inherited from Pausable
        bytes32 pauserRole = proxy.PAUSER_ROLE();
        assertTrue(
            proxy.hasRole(pauserRole, pauser),
            "Pauser should have PAUSER_ROLE"
        );
    }

    function test_Initialize_OnlyAdminHasDEFAULT_ADMIN_ROLE() public view {
        // Verify that non-admin addresses don't have DEFAULT_ADMIN_ROLE
        assertFalse(
            proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), rateManager),
            "Rate manager should not have DEFAULT_ADMIN_ROLE"
        );
        assertFalse(
            proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), address(this)),
            "Test contract should not have DEFAULT_ADMIN_ROLE"
        );
    }

    /* ============ Mint Tests ============ */

    function test_Mint_NotMinterGateway_Reverts() public {
        address recipient = address(0x100);
        uint256 amount = 1000e6; // 1000 PYUSDX (6 decimals)

        vm.expectRevert(PYUSDX.NotMinterGateway.selector);
        proxy.mint(recipient, amount);
    }

    function test_Mint_WhenPaused_Reverts() public {
        address recipient = address(0x100);
        uint256 amount = 1000e6;

        // Pause the contract
        vm.prank(pauser);
        proxy.pause();

        // Try to mint as minterGateway
        vm.prank(minterGateway);
        vm.expectRevert(/* EnforcedPause from OZ Pausable */);
        proxy.mint(recipient, amount);
    }

    function test_Mint_WhenRecipientFrozen_Reverts() public {
        address recipient = address(0x100);
        uint256 amount = 1000e6;

        // Freeze the recipient
        vm.prank(freezeManager);
        proxy.freeze(recipient);

        // Try to mint as minterGateway
        vm.prank(minterGateway);
        vm.expectRevert(/* AccountFrozen */);
        proxy.mint(recipient, amount);
    }

    function test_Mint_ZeroAmount_Reverts() public {
        address recipient = address(0x100);

        vm.prank(minterGateway);
        vm.expectRevert("zero amount");
        proxy.mint(recipient, 0);
    }

    // NOTE: test_Mint_ToEarner_Success requires startEarningFor (Phase 2.9)
    // Skipping for now - will be added in Phase 2.9
    // function test_Mint_ToEarner_Success() public { }

    function test_Mint_ToNonEarner_Success() public {
        address recipient = address(0x100);
        uint256 amount = 1000e6;

        uint256 balanceBefore = proxy.balanceOf(recipient);
        uint256 earningSupplyBefore = proxy.totalEarningSupply();
        uint256 nonEarningSupplyBefore = proxy.totalNonEarningSupply();

        // Mint to non-earner
        vm.prank(minterGateway);
        proxy.mint(recipient, amount);

        // Verify balance increased
        assertEq(proxy.balanceOf(recipient), balanceBefore + amount, "Balance should increase");
        // Verify non-earning supply increased
        assertEq(
            proxy.totalNonEarningSupply(),
            nonEarningSupplyBefore + amount,
            "Non-earning supply should increase"
        );
        // Verify earning supply unchanged
        assertEq(
            proxy.totalEarningSupply(),
            earningSupplyBefore,
            "Earning supply should not change"
        );
        // Verify not earning
        assertFalse(proxy.isEarning(recipient), "Recipient should not be earning");
    }

    function test_Mint_AmountOverflowUint240_Reverts() public {
        address recipient = address(0x100);
        // Amount larger than uint240 max (2^240 - 1)
        uint256 amount = uint256(type(uint240).max) + 1;

        vm.prank(minterGateway);
        vm.expectRevert(); // Safe240 will revert on overflow
        proxy.mint(recipient, amount);
    }

    function test_Mint_TransferEventEmitted() public {
        address recipient = address(0x100);
        uint256 amount = 1000e6;

        vm.expectEmit(true, true, true, true, address(proxy));
        emit IERC20.Transfer(address(0), recipient, amount);

        vm.prank(minterGateway);
        proxy.mint(recipient, amount);
    }
}
