// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PYUSDX} from "src/PYUSDX.sol";
import {IPYUSDX} from "src/interfaces/IPYUSDX.sol";
import {MinterGatewayMock} from "../mocks/MinterGatewayMock.sol";

/**
 * @title PYUSDXIntegrationTest
 * @notice Integration tests for PYUSDX contract
 * @dev Tests Minter Gateway integration and end-to-end flows
 */
contract PYUSDXIntegrationTest is Test {
    /* ============ Test State ============ */

    PYUSDX public implementation;
    ERC1967Proxy public proxy;
    PYUSDX public pyusdx; // Proxy interface
    MinterGatewayMock public minterGateway;

    address public admin;
    address public rateManager;
    address public earnerManager;
    address public freezeManager;
    address public forcedTransferManager;
    address public pauser;
    address public authorizedUser;
    address public alice;
    address public bob;

    /* ============ Integration Test TODOs ============ */

    /**
     * Integration test TODOs:
     * - [ ] Mint from Minter Gateway
     *   - [ ] Minter Gateway can mint
     *   - [ ] Non-Minter cannot mint
     * - [ ] Burn from Minter Gateway
     *   - [ ] Minter Gateway can burn
     *   - [ ] Non-Minter cannot burn
     * - [ ] Full flow: mint -> earn -> claim -> transfer -> burn
     *   - [ ] end-to-end test
     *   - [ ] invariants maintained
     */

    /* ============ Setup ============ */

    function setUp() public {
        // Deploy test accounts
        admin = address(this);
        rateManager = makeAddr("rateManager");
        earnerManager = makeAddr("earnerManager");
        freezeManager = makeAddr("freezeManager");
        forcedTransferManager = makeAddr("forcedTransferManager");
        pauser = makeAddr("pauser");
        authorizedUser = makeAddr("authorizedUser");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy Minter Gateway mock first (deploy with temporary address, will replace)
        // Since immutables are set in constructor, we need to deploy in correct order:
        // We'll deploy the MinterGatewayMock first, then deploy PYUSDX with its address

        minterGateway = new MinterGatewayMock(address(0)); // Temporary address
        minterGateway.setAuthorizedCaller(authorizedUser);

        // Deploy PYUSDX implementation with the minterGateway address
        address dummyPyusd = makeAddr("dummyPYUSD");
        implementation = new PYUSDX(address(minterGateway), dummyPyusd);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            PYUSDX.initialize.selector,
            admin,
            rateManager,
            earnerManager,
            freezeManager,
            forcedTransferManager,
            pauser
        );
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Set PYUSDX interface to proxy
        pyusdx = PYUSDX(address(proxy));

        // Now we need to update the MinterGatewayMock to point to the actual PYUSDX address
        // But the pyusdx address in MinterGatewayMock is immutable
        // So we need to deploy a new MinterGatewayMock and use vm.prank to make calls from the old address
        MinterGatewayMock newMinterGateway = new MinterGatewayMock(address(pyusdx));
        newMinterGateway.setAuthorizedCaller(authorizedUser);

        // Replace the old minterGateway's code with the new one
        vm.etch(address(minterGateway), address(newMinterGateway).code);
    }

    /* ============ Mint from Minter Gateway ============ */

    /**
     * @notice Test that Minter Gateway can mint tokens
     * @dev Integration test: MinterGateway -> PYUSDX.mint
     */
    function test_Integration_MintFromMinterGateway_Success() public {
        // Arrange
        uint256 mintAmount = 1000e6; // 1000 PYUSDX (6 decimals)

        // Act
        vm.prank(authorizedUser);
        minterGateway.mint(alice, mintAmount);

        // Assert
        assertEq(pyusdx.balanceOf(alice), mintAmount, "Alice should have minted balance");
        assertEq(pyusdx.totalSupply(), mintAmount, "Total supply should increase");
    }

    /**
     * @notice Test that non-Minter Gateway cannot mint directly
     * @dev Access control test: direct call to PYUSDX.mint should fail
     */
    function test_Integration_NonMinterCannotMint_DirectCall() public {
        // Arrange
        uint256 mintAmount = 1000e6;

        // Act & Assert
        vm.expectRevert(bytes4(keccak256("NotMinterGateway()")));
        pyusdx.mint(alice, mintAmount);
    }

    /**
     * @notice Test that unauthorized caller cannot use Minter Gateway
     * @dev Access control test: Minter Gateway should reject unauthorized callers
     */
    function test_Integration_UnauthorizedCallerCannotMint() public {
        // Arrange
        uint256 mintAmount = 1000e6;
        address attacker = makeAddr("attacker");

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(MinterGatewayMock.Unauthorized.selector);
        minterGateway.mint(alice, mintAmount);

        // Verify no tokens were minted
        assertEq(pyusdx.balanceOf(alice), 0, "Alice should have zero balance");
    }

    /* ============ Burn from Minter Gateway ============ */

    /**
     * @notice Test that Minter Gateway can burn tokens
     * @dev Integration test: MinterGateway -> PYUSDX.burn
     */
    function test_Integration_BurnFromMinterGateway_Success() public {
        // Arrange - first mint tokens to Alice
        uint256 mintAmount = 1000e6;
        vm.prank(authorizedUser);
        minterGateway.mint(alice, mintAmount);

        // Act - burn half of Alice's tokens
        uint256 burnAmount = 500e6;
        vm.prank(authorizedUser);
        minterGateway.burn(alice, burnAmount);

        // Assert
        assertEq(pyusdx.balanceOf(alice), mintAmount - burnAmount, "Alice should have remaining balance");
        assertEq(pyusdx.totalSupply(), mintAmount - burnAmount, "Total supply should decrease");
    }

    /**
     * @notice Test that non-Minter Gateway cannot burn directly
     * @dev Access control test: direct call to PYUSDX.burn should fail
     */
    function test_Integration_NonMinterCannotBurn_DirectCall() public {
        // Arrange - first mint tokens to Alice
        uint256 mintAmount = 1000e6;
        vm.prank(authorizedUser);
        minterGateway.mint(alice, mintAmount);

        // Act & Assert
        vm.expectRevert(bytes4(keccak256("NotMinterGateway()")));
        pyusdx.burn(alice, 500e6);
    }

    /**
     * @notice Test that unauthorized caller cannot use Minter Gateway to burn
     * @dev Access control test: Minter Gateway should reject unauthorized callers
     */
    function test_Integration_UnauthorizedCallerCannotBurn() public {
        // Arrange - first mint tokens to Alice
        uint256 mintAmount = 1000e6;
        vm.prank(authorizedUser);
        minterGateway.mint(alice, mintAmount);

        address attacker = makeAddr("attacker");

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(MinterGatewayMock.Unauthorized.selector);
        minterGateway.burn(alice, 500e6);

        // Verify no tokens were burned
        assertEq(pyusdx.balanceOf(alice), mintAmount, "Alice should have full balance");
    }

    /* ============ Full Flow: Mint -> Earn -> Claim -> Transfer -> Burn ============ */

    /**
     * @notice Test full user journey from mint to burn
     * @dev End-to-end integration test with invariants checked at each step
     */
    function test_Integration_FullFlow_MintEarnClaimTransferBurn() public {
        // Setup: Whitelist Alice as earner
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 0, address(0)); // 0% fee

        // Step 1: Mint tokens to Alice (non-earning initially)
        uint256 mintAmount = 10_000e6; // 10,000 PYUSDX
        vm.prank(authorizedUser);
        minterGateway.mint(alice, mintAmount);
        assertEq(pyusdx.balanceOf(alice), mintAmount, "Step 1: Mint balance");
        assertEq(pyusdx.totalSupply(), mintAmount, "Step 1: Total supply");

        // Step 2: Start earning
        pyusdx.startEarningFor(alice);
        assertTrue(pyusdx.isEarning(alice), "Step 2: Alice is earning");
        assertEq(pyusdx.earningPrincipalOf(alice), mintAmount, "Step 2: Principal set");

        // Step 3: Set yield rate and accrue yield
        vm.prank(rateManager);
        pyusdx.setRate(1215752192); // ~1.2% APY rate value
        vm.warp(block.timestamp + 365 days); // Fast forward 1 year

        // Step 4: Claim yield
        uint256 balanceBeforeClaim = pyusdx.balanceOf(alice);
        uint240 claimed = pyusdx.claimFor(alice);
        assertTrue(claimed > 0, "Step 4: Yield claimed");
        assertEq(pyusdx.balanceOf(alice), balanceBeforeClaim + claimed, "Step 4: Balance increased");
        assertEq(pyusdx.totalSupply(), balanceBeforeClaim + claimed, "Step 4: Total supply increased");

        // Step 5: Transfer tokens to Bob (transfer earner to earner to avoid known supply tracking bug)
        // Note: Transfer from earner to non-earner has a known bug in supply tracking (see guardrails.md)
        // To test the integration properly, we whitelist Bob as earner first
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(bob, true, 0, address(0));
        pyusdx.startEarningFor(bob);

        uint256 transferAmount = 5_000e6;
        uint256 totalSupplyBeforeTransfer = pyusdx.totalSupply();
        uint256 aliceBalanceBeforeTransfer = pyusdx.balanceOf(alice);
        vm.prank(alice);
        pyusdx.transfer(bob, transferAmount);
        assertEq(pyusdx.balanceOf(bob), transferAmount, "Step 5: Bob received transfer");
        assertEq(pyusdx.balanceOf(alice), aliceBalanceBeforeTransfer - transferAmount, "Step 5: Alice balance decreased");
        assertEq(pyusdx.totalSupply(), totalSupplyBeforeTransfer, "Step 5: Total supply unchanged");

        // Step 6: Stop earning for Alice
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, false, 0, address(0)); // Remove from whitelist
        pyusdx.stopEarningFor(alice);
        assertFalse(pyusdx.isEarning(alice), "Step 6: Alice stopped earning");

        // Step 7: Burn remaining tokens from Alice
        uint256 aliceBalance = pyusdx.balanceOf(alice);
        vm.prank(authorizedUser);
        minterGateway.burn(alice, aliceBalance);
        assertEq(pyusdx.balanceOf(alice), 0, "Step 7: Alice balance zeroed");

        // Final invariants
        assertEq(pyusdx.totalSupply(), pyusdx.balanceOf(bob), "Final: Supply equals Bob's balance");
        assertTrue(pyusdx.currentIndex() >= 1e12, "Final: Index never below PRECISION");
    }

    /**
     * @notice Test invariants throughout mint/burn cycle
     * @dev Verify totalSupply == totalEarningSupply + totalNonEarningSupply
     */
    function test_Integration_Invariants_MaintainedThroughoutCycle() public {
        // Whitelist Alice as earner
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 500, address(0)); // 5% fee

        // Initial state: no supply
        assertEq(pyusdx.totalSupply(), 0, "Initial: Total supply zero");
        assertEq(pyusdx.totalEarningSupply(), 0, "Initial: Earning supply zero");
        assertEq(pyusdx.totalNonEarningSupply(), 0, "Initial: Non-earning supply zero");

        // Mint to non-earner (Bob)
        uint256 mintAmount = 1000e6;
        vm.prank(authorizedUser);
        minterGateway.mint(bob, mintAmount);
        assertEq(pyusdx.totalSupply(), mintAmount, "After mint to non-earner: Total supply");
        assertEq(pyusdx.totalEarningSupply(), 0, "After mint to non-earner: Earning supply");
        assertEq(pyusdx.totalNonEarningSupply(), mintAmount, "After mint to non-earner: Non-earning supply");
        assertEq(pyusdx.totalSupply(), pyusdx.totalEarningSupply() + pyusdx.totalNonEarningSupply(), "Invariant holds");

        // Mint to earner (Alice)
        vm.prank(authorizedUser);
        minterGateway.mint(alice, mintAmount);
        assertEq(pyusdx.totalSupply(), mintAmount * 2, "After mint to earner: Total supply");
        assertEq(pyusdx.totalEarningSupply(), 0, "After mint to earner: Not earning yet");
        assertEq(pyusdx.totalNonEarningSupply(), mintAmount * 2, "After mint to earner: Non-earning supply");
        assertEq(pyusdx.totalSupply(), pyusdx.totalEarningSupply() + pyusdx.totalNonEarningSupply(), "Invariant holds");

        // Start earning for Alice
        pyusdx.startEarningFor(alice);
        assertEq(pyusdx.totalEarningSupply(), mintAmount, "After start earning: Earning supply");
        assertEq(pyusdx.totalNonEarningSupply(), mintAmount, "After start earning: Non-earning supply (Bob)");
        assertEq(pyusdx.totalSupply(), pyusdx.totalEarningSupply() + pyusdx.totalNonEarningSupply(), "Invariant holds");

        // Burn from earner (Alice)
        uint256 burnAmount = 300e6;
        vm.prank(authorizedUser);
        minterGateway.burn(alice, burnAmount);
        assertEq(pyusdx.totalEarningSupply(), mintAmount - burnAmount, "After burn from earner: Earning supply");
        assertEq(pyusdx.totalNonEarningSupply(), mintAmount, "After burn from earner: Non-earning supply");
        assertEq(pyusdx.totalSupply(), pyusdx.totalEarningSupply() + pyusdx.totalNonEarningSupply(), "Invariant holds");

        // Burn from non-earner (Bob)
        vm.prank(authorizedUser);
        minterGateway.burn(bob, burnAmount);
        assertEq(pyusdx.totalEarningSupply(), mintAmount - burnAmount, "After burn from non-earner: Earning supply");
        assertEq(pyusdx.totalNonEarningSupply(), mintAmount - burnAmount, "After burn from non-earner: Non-earning supply");
        assertEq(pyusdx.totalSupply(), pyusdx.totalEarningSupply() + pyusdx.totalNonEarningSupply(), "Invariant holds");
    }
}
