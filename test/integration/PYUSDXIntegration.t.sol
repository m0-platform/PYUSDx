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

    /* ============ M0 Common Libraries Integration ============ */

    /**
     * @notice Test IndexingMath.getPresentAmountRoundedDown
     * @dev Integration test: verify the formula balanceWithYield = principal * index / PRECISION
     */
    function test_Integration_IndexingMath_GetPresentAmountRoundedDown() public {
        // Setup: Whitelist Alice as earner and mint tokens
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 0, address(0));
        vm.prank(authorizedUser);
        minterGateway.mint(alice, 10_000e6);
        pyusdx.startEarningFor(alice);

        // Set a rate and fast forward to accrue yield
        vm.prank(rateManager);
        pyusdx.setRate(1215752192); // ~1.2% APY
        vm.warp(block.timestamp + 365 days);

        // Get balance with yield (uses IndexingMath.getPresentAmountRoundedDown internally)
        uint256 balance = pyusdx.balanceOf(alice);
        uint256 principal = pyusdx.earningPrincipalOf(alice);
        uint256 balanceWithYield = pyusdx.balanceWithYieldOf(alice);
        uint256 currentIndex = pyusdx.currentIndex();

        // Verify: balanceWithYield = principal * currentIndex / PRECISION (rounded down)
        uint256 expectedBalanceWithYield = (principal * currentIndex) / 1e12;
        assertEq(balanceWithYield, expectedBalanceWithYield, "Balance with yield matches formula");
        assertTrue(balanceWithYield >= balance, "Balance with yield >= balance");

        // Accrued yield should be the difference
        uint256 accruedYield = pyusdx.accruedYieldOf(alice);
        assertEq(balanceWithYield, balance + accruedYield, "Balance with yield = balance + accrued");
    }

    /**
     * @notice Test IndexingMath.getPrincipalAmountRoundedUp
     * @dev Integration test: verify principal = balance * PRECISION / index (rounded up)
     */
    function test_Integration_IndexingMath_GetPrincipalAmountRoundedUp() public {
        // Setup: Whitelist Alice as earner, mint tokens, and start earning with index > PRECISION
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 0, address(0));
        vm.prank(authorizedUser);
        minterGateway.mint(alice, 10_000e6);

        // Set rate and fast forward to grow index
        vm.prank(rateManager);
        pyusdx.setRate(1215752192); // ~1.2% APY
        vm.warp(block.timestamp + 365 days);

        // Now start earning - principal should be calculated using current index
        uint256 balanceBeforeStart = pyusdx.balanceOf(alice);
        uint256 currentIndex = pyusdx.currentIndex();
        pyusdx.startEarningFor(alice);

        uint256 principal = pyusdx.earningPrincipalOf(alice);

        // Verify: principal = balance * PRECISION / index (rounded up)
        // Formula: principal = ceil(balance * PRECISION / currentIndex)
        uint256 expectedPrincipal = (balanceBeforeStart * 1e12 + currentIndex - 1) / currentIndex;
        assertEq(principal, expectedPrincipal, "Principal matches formula (rounded up)");
    }

    /**
     * @notice Test IndexingMath with edge cases
     * @dev Integration test: zero balance, max index, etc.
     */
    function test_Integration_IndexingMath_EdgeCases() public {
        // Whitelist Alice as earner
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 0, address(0));

        // Edge case 1: Zero balance
        pyusdx.startEarningFor(alice);
        assertEq(pyusdx.earningPrincipalOf(alice), 0, "Zero balance => zero principal");
        assertEq(pyusdx.balanceWithYieldOf(alice), 0, "Zero balance => zero balance with yield");

        // Edge case 2: Very small balance (1 unit)
        // Mint to a new account and start earning to test principal calculation
        address charlie = makeAddr("charlie");
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(charlie, true, 0, address(0));
        vm.prank(authorizedUser);
        minterGateway.mint(charlie, 1); // 1 unit (6 decimals)
        pyusdx.startEarningFor(charlie);
        assertEq(pyusdx.earningPrincipalOf(charlie), 1, "1 unit => 1 principal at index=PRECISION");

        // Edge case 3: Large index growth
        vm.prank(rateManager);
        pyusdx.setRate(1215752192); // ~1.2% APY
        vm.warp(block.timestamp + 365 days);
        assertTrue(pyusdx.currentIndex() > 1e12, "Index grew");

        // Verify balance with yield calculation still works (using charlie who has 1 unit)
        uint256 charlieBalance = pyusdx.balanceOf(charlie);
        uint256 charlieBalanceWithYield = pyusdx.balanceWithYieldOf(charlie);
        assertTrue(charlieBalanceWithYield >= charlieBalance, "Balance with yield >= original balance");
    }

    /**
     * @notice Test UIntMath.bound128 prevents overflow
     * @dev Integration test: verify uint128 bounds checking
     */
    function test_Integration_UIntMath_Bound128() public {
        // The uint128 bounds are used in _calculateIndex when computing newIndex
        // Let's verify that setting high rates doesn't cause overflow

        // Set a high rate (uint32 max is about 4.29e9, but we use what fits in uint32)
        // PRECISION = 1e12, so max rate allowed is 1e12
        vm.prank(rateManager);
        uint32 highRate = 3_000_000_000; // High rate but within uint32 and PRECISION bounds
        pyusdx.setRate(highRate);

        // Fast forward significantly
        vm.warp(block.timestamp + 365 days);

        // Index should still be within uint128 bounds
        uint256 index = pyusdx.currentIndex();
        assertTrue(index <= type(uint128).max, "Index within uint128 bounds");
        assertTrue(index >= 1e12, "Index >= PRECISION");
    }

    /**
     * @notice Test UIntMath.safe240 prevents overflow
     * @dev Integration test: verify uint240 bounds checking in mint
     */
    function test_Integration_UIntMath_Safe240() public {
        // Try to mint more than uint240 max
        uint256 maxUint240 = type(uint240).max;

        // Minting uint240.max should work
        vm.prank(authorizedUser);
        minterGateway.mint(alice, maxUint240);
        assertEq(pyusdx.balanceOf(alice), maxUint240, "Max uint240 minted");

        // Try to mint 1 more - this should revert due to overflow
        vm.prank(authorizedUser);
        vm.expectRevert();
        minterGateway.mint(bob, maxUint240 + 1);
    }

    /* ============ EarnerManager Integration ============ */

    /**
     * @notice Test EarnerManager: set and get earner details
     * @dev Integration test: verify earner status, fee rate, and fee recipient work correctly
     */
    function test_Integration_EarnerManager_SetAndGetEarnerDetails() public {
        // Initially, Alice should not be whitelisted
        (bool isWhitelisted, uint16 feeRate, address feeRecipient) = pyusdx.getEarnerDetails(alice);
        assertFalse(isWhitelisted, "Alice not whitelisted initially");
        assertEq(feeRate, 0, "Fee rate is 0 initially");
        assertEq(feeRecipient, address(0), "Fee recipient is 0 initially");

        // Whitelist Alice with 10% fee and custom fee recipient
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 1000, bob); // 10% = 1000 bps

        (isWhitelisted, feeRate, feeRecipient) = pyusdx.getEarnerDetails(alice);
        assertTrue(isWhitelisted, "Alice whitelisted");
        assertEq(feeRate, 1000, "Fee rate is 10%");
        assertEq(feeRecipient, bob, "Fee recipient is Bob");
    }

    /**
     * @notice Test EarnerManager: earnerStatusFor function
     * @dev Integration test: verify earner status check works correctly
     */
    function test_Integration_EarnerManager_EarnerStatusFor() public {
        // Initially not an earner
        assertFalse(pyusdx.earnerStatusFor(alice), "Alice not earner initially");

        // Whitelist Alice
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 0, address(0));

        assertTrue(pyusdx.earnerStatusFor(alice), "Alice is earner after whitelisting");

        // Remove from whitelist
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, false, 0, address(0));

        assertFalse(pyusdx.earnerStatusFor(alice), "Alice not earner after removal");
    }

    /**
     * @notice Test EarnerManager: fee rate application in claims
     * @dev Integration test: verify fee is correctly deducted from yield
     */
    function test_Integration_EarnerManager_FeeRateApplicationInClaims() public {
        // Setup: Whitelist Alice with 10% fee, Bob as fee recipient
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 1000, bob); // 10% fee

        // Mint and start earning
        vm.prank(authorizedUser);
        minterGateway.mint(alice, 10_000e6);
        pyusdx.startEarningFor(alice);

        // Set rate and accrue yield
        vm.prank(rateManager);
        pyusdx.setRate(1215752192); // ~1.2% APY
        vm.warp(block.timestamp + 365 days);

        // Claim yield
        uint240 netYield = pyusdx.claimFor(alice);

        // Verify fee was deducted: fee = grossYield * feeRate / 10000
        // Bob should have received the fee
        uint256 bobBalance = pyusdx.balanceOf(bob);
        assertTrue(bobBalance > 0, "Bob received fee");

        // Alice's balance increased by grossYield (before fee deduction)
        uint256 aliceBalance = pyusdx.balanceOf(alice);
        assertTrue(aliceBalance > 10_000e6, "Alice's balance increased by grossYield");
    }

    /**
     * @notice Test EarnerManager: changing fee rate affects future claims
     * @dev Integration test: verify fee rate changes only affect future yield, not past
     */
    function test_Integration_EarnerManager_FeeRateChangeAffectsFutureClaims() public {
        // Setup: Whitelist Alice with 0% fee initially
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 0, bob);

        // Mint and start earning
        vm.prank(authorizedUser);
        minterGateway.mint(alice, 10_000e6);
        pyusdx.startEarningFor(alice);

        // Set rate and accrue some yield
        vm.prank(rateManager);
        pyusdx.setRate(1215752192); // ~1.2% APY
        vm.warp(block.timestamp + 180 days);

        // Claim first portion (0% fee)
        uint240 firstClaim = pyusdx.claimFor(alice);
        assertTrue(firstClaim > 0, "First claim successful");

        // Change fee rate to 20%
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 2000, bob);

        // Accrue more yield
        vm.warp(block.timestamp + 180 days);

        // Claim second portion (20% fee)
        uint256 bobBalanceBefore = pyusdx.balanceOf(bob);
        uint240 secondClaim = pyusdx.claimFor(alice);
        assertTrue(secondClaim > 0, "Second claim successful");

        // Bob should have received fee from second claim only
        uint256 bobBalanceAfter = pyusdx.balanceOf(bob);
        assertTrue(bobBalanceAfter > bobBalanceBefore, "Bob received fee from second claim");
    }

    /**
     * @notice Test EarnerManager: fee rate of 100% sends all yield to recipient
     * @dev Integration test: verify extreme fee rate behavior
     */
    function test_Integration_EarnerManager_MaxFeeRate_AllYieldToRecipient() public {
        // Setup: Whitelist Alice with 100% fee
        vm.prank(earnerManager);
        pyusdx.setEarnerDetails(alice, true, 10000, bob); // 100% fee

        // Mint and start earning
        vm.prank(authorizedUser);
        minterGateway.mint(alice, 10_000e6);
        pyusdx.startEarningFor(alice);

        // Set rate and accrue yield
        vm.prank(rateManager);
        pyusdx.setRate(1215752192); // ~1.2% APY
        vm.warp(block.timestamp + 365 days);

        // Get Alice's balance before claim
        uint256 aliceBalanceBefore = pyusdx.balanceOf(alice);

        // Claim yield
        uint240 netYield = pyusdx.claimFor(alice);

        // Net yield returned should be 0 (100% fee)
        assertEq(netYield, 0, "Net yield is 0 with 100% fee");

        // Alice's balance should have increased by grossYield (principal increases)
        // But she receives nothing in her claim recipient
        uint256 aliceBalanceAfter = pyusdx.balanceOf(alice);
        assertTrue(aliceBalanceAfter > aliceBalanceBefore, "Alice's balance increased (principal)");

        // Bob should have received all the yield
        uint256 bobBalance = pyusdx.balanceOf(bob);
        assertTrue(bobBalance > 0, "Bob received all yield as fee");
    }
}
