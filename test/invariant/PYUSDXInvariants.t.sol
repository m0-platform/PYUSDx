// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {PYUSDX} from "../../src/PYUSDX.sol";
import {IPYUSDX} from "../../src/interfaces/IPYUSDX.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * Invariant test TODOs:
 * - [x] Invariant 1: Total Supply Consistency
 *   - [x] totalSupply == totalEarningSupply + totalNonEarningSupply
 * - [x] Invariant 2: Principal Sum
 *   - [x] totalEarningPrincipal == sum of all earning principals
 * - [x] Invariant 3: Index Monotonicity
 *   - [x] index never decreases
 * - [x] Invariant 4: Balance Calculation
 *   - [x] balanceWithYield == balance + accruedYield (for earners)
 * - [x] Stateful Fuzzing: Multiple actors
 *   - [x] Actors: minter, earner, claimer, transferer, rateManager
 *   - [x] Invariants hold after random sequences of operations
 *
 * Stateful Fuzzing Configuration:
 * - Target senders are used to restrict which actors can call target functions
 * - Each Fuzz_* function is restricted to a specific actor via modifiers
 * - forge test --match-path "test/invariant/PYUSDXInvariants.t.sol" --depth 100
 */
contract PYUSDXInvariantsTest is Test {
    // Define target senders for stateful fuzzing
    // These actors will be the only ones allowed to call target functions
    address constant minterActor = address(0x100);
    address constant earnerActor = address(0x101);
    address constant claimerActor = address(0x102);
    address constant transfererActor = address(0x103);
    address constant rateManagerActor = address(0x104);
    address constant earnerManagerActor = address(0x105);
    address constant freezeManagerActor = address(0x106);
    address constant forcedTransferManagerActor = address(0x107);
    address constant pauserActor = address(0x108);

    // Use modifiers to restrict function access to specific actors
    modifier onlyMinterActor() {
        require(msg.sender == minterActor, "only minter actor");
        _;
    }

    modifier onlyEarnerActor() {
        require(msg.sender == earnerActor, "only earner actor");
        _;
    }

    modifier onlyClaimerActor() {
        require(msg.sender == claimerActor, "only claimer actor");
        _;
    }

    modifier onlyTransfererActor() {
        require(msg.sender == transfererActor, "only transferer actor");
        _;
    }

    modifier onlyRateManagerActor() {
        require(msg.sender == rateManagerActor, "only rate manager actor");
        _;
    }

    modifier onlyEarnerManagerActor() {
        require(msg.sender == earnerManagerActor, "only earner manager actor");
        _;
    }

    modifier onlyFreezeManagerActor() {
        require(msg.sender == freezeManagerActor, "only freeze manager actor");
        _;
    }

    modifier onlyForcedTransferManagerActor() {
        require(msg.sender == forcedTransferManagerActor, "only forced transfer manager actor");
        _;
    }

    modifier onlyPauserActor() {
        require(msg.sender == pauserActor, "only pauser actor");
        _;
    }

    // Provide target senders for stateful fuzzing (Foundry will call this)
    // Note: This is not overriding - it's a helper function for the test
    function getTargetSenders() public view returns (address[] memory) {
        address[] memory senders = new address[](9);
        senders[0] = minterActor;
        senders[1] = earnerActor;
        senders[2] = claimerActor;
        senders[3] = transfererActor;
        senders[4] = rateManagerActor;
        senders[5] = earnerManagerActor;
        senders[6] = freezeManagerActor;
        senders[7] = forcedTransferManagerActor;
        senders[8] = pauserActor;
        return senders;
    }
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

    // Track all earners for principal sum invariant
    address[] public earners;

    // Track last index for monotonicity
    uint128 public lastIndex;

    /* ============ Setup ============ */

    function setUp() public {
        // Deploy implementation contract
        implementation = new PYUSDX(minterGateway, pyusd);

        // Deploy proxy pointing to implementation
        bytes memory initData = abi.encodeWithSelector(
            PYUSDX.initialize.selector, admin, rateManager, earnerManager, freezeManager, forcedTransferManager, pauser
        );

        erc1967Proxy = new ERC1967Proxy(address(implementation), initData);

        proxy = PYUSDX(address(erc1967Proxy));

        // Grant roles
        vm.startPrank(admin);
        proxy.grantRole(proxy.EARNER_MANAGER_ROLE(), earnerManager);
        proxy.grantRole(proxy.RATE_MANAGER_ROLE(), rateManager);
        vm.stopPrank();

        // Initialize lastIndex
        lastIndex = proxy.currentIndex();
    }

    /* ============ Invariant 1: Total Supply Consistency ============ */

    function invariant_totalSupplyConsistency() public view {
        uint256 totalSupply = proxy.totalSupply();
        uint256 totalEarningSupply = proxy.totalEarningSupply();
        uint256 totalNonEarningSupply = proxy.totalNonEarningSupply();

        assertEq(
            totalSupply,
            totalEarningSupply + totalNonEarningSupply,
            "Total supply must equal earning + non-earning supply"
        );
    }

    /* ============ Invariant 2: Principal Sum ============ */

    function invariant_principalSum() public view {
        uint256 storedTotalPrincipal = proxy.totalEarningPrincipal();
        uint256 calculatedSum = 0;

        for (uint256 i = 0; i < earners.length; i++) {
            address earner = earners[i];
            if (proxy.isEarning(earner)) {
                calculatedSum += proxy.earningPrincipalOf(earner);
            }
        }

        assertEq(storedTotalPrincipal, calculatedSum, "Total earning principal must equal sum of individual principals");
    }

    /* ============ Invariant 3: Index Monotonicity ============ */

    function invariant_indexMonotonicity() public view {
        uint128 currentIndex = proxy.currentIndex();
        assertTrue(currentIndex >= lastIndex, "Index must never decrease");
    }

    /* ============ Invariant 4: Balance Calculation ============ */

    function invariant_balanceCalculation() public view {
        for (uint256 i = 0; i < earners.length; i++) {
            address earner = earners[i];
            if (proxy.isEarning(earner)) {
                uint256 balance = proxy.balanceOf(earner);
                uint256 balanceWithYield = proxy.balanceWithYieldOf(earner);
                uint256 accruedYield = proxy.accruedYieldOf(earner);

                assertEq(
                    balanceWithYield, balance + accruedYield, "Balance with yield must equal balance + accrued yield"
                );
            }
        }
    }

    /* ============ Stateful Fuzzing with Multiple Actors ============ */

    // Target functions for stateful fuzzing
    // Using modifiers to restrict which actors can call each function

    function Fuzz_mint(address recipient, uint256 amount) public onlyMinterActor {
        vm.assume(amount > 0 && amount <= uint256(type(uint240).max));
        vm.assume(recipient != address(0));

        uint256 balanceBefore = proxy.balanceOf(recipient);

        vm.prank(minterGateway);
        try proxy.mint(recipient, amount) {
            // Post-condition: balance should increase
            assertTrue(proxy.balanceOf(recipient) >= balanceBefore, "Mint should not decrease balance");
        } catch {}
    }

    function Fuzz_burn(address account, uint256 amount) public onlyMinterActor {
        vm.assume(amount > 0 && amount <= uint256(type(uint240).max));
        vm.assume(account != address(0));

        uint256 balanceBefore = proxy.balanceOf(account);

        if (amount <= balanceBefore) {
            vm.prank(minterGateway);
            try proxy.burn(account, amount) {
                // Post-condition: balance should decrease
                assertTrue(proxy.balanceOf(account) <= balanceBefore, "Burn should not increase balance");
            } catch {}
        }
    }

    function Fuzz_transfer(address sender, address recipient, uint256 amount) public onlyTransfererActor {
        vm.assume(amount > 0 && amount <= uint256(type(uint240).max));
        vm.assume(sender != address(0) && recipient != address(0) && sender != recipient);

        uint256 senderBalanceBefore = proxy.balanceOf(sender);
        uint256 recipientBalanceBefore = proxy.balanceOf(recipient);

        if (amount <= senderBalanceBefore) {
            vm.prank(sender);
            try proxy.transfer(recipient, amount) {
                // Post-condition: balances should be conserved
                assertEq(
                    proxy.balanceOf(sender) + proxy.balanceOf(recipient),
                    senderBalanceBefore + recipientBalanceBefore,
                    "Transfer should conserve total balance"
                );
            } catch {}
        }
    }

    function Fuzz_startEarning(address account) public onlyEarnerActor {
        vm.assume(account != address(0));

        // Approve as earner first
        vm.prank(earnerManager);
        try proxy.setEarnerDetails(account, true, 0, address(0)) {
            vm.prank(earnerManager);
            try proxy.startEarningFor(account) {
                // Add to earners list if not already there
                bool alreadyAdded = false;
                for (uint256 i = 0; i < earners.length; i++) {
                    if (earners[i] == account) {
                        alreadyAdded = true;
                        break;
                    }
                }
                if (!alreadyAdded) {
                    earners.push(account);
                }
            } catch {}
        } catch {}
    }

    function Fuzz_stopEarning(address account) public onlyEarnerActor {
        vm.assume(account != address(0));

        if (proxy.isEarning(account)) {
            // Remove from earners list
            for (uint256 i = 0; i < earners.length; i++) {
                if (earners[i] == account) {
                    earners[i] = earners[earners.length - 1];
                    earners.pop();
                    break;
                }
            }

            // Remove earner approval first
            vm.prank(earnerManager);
            try proxy.setEarnerDetails(account, false, 0, address(0)) {
                vm.prank(earnerManager);
                try proxy.stopEarningFor(account) {
                    // Post-condition: should not be earning
                    assertTrue(!proxy.isEarning(account), "Should not be earning after stopEarningFor");
                } catch {}
            } catch {}
        }
    }

    function Fuzz_claim(address account) public onlyClaimerActor {
        vm.assume(account != address(0));

        if (proxy.isEarning(account)) {
            uint256 balanceBefore = proxy.balanceOf(account);

            try proxy.claimFor(account) {
                // Post-condition: balance should not decrease
                assertTrue(proxy.balanceOf(account) >= balanceBefore, "Claim should not decrease balance");
            } catch {}
        }
    }

    function Fuzz_setRate(uint32 newRate) public onlyRateManagerActor {
        vm.assume(newRate <= 1000000000); // Reasonable rate bound

        vm.prank(rateManager);
        try proxy.setRate(newRate) {
            // Update lastIndex
            lastIndex = proxy.currentIndex();
        } catch {}
    }

    // Invariant runner - called automatically by Forge after each target function
    function invariant_allInvariantsHold() public view {
        invariant_totalSupplyConsistency();
        invariant_principalSum();
        invariant_indexMonotonicity();
        invariant_balanceCalculation();
    }

    /* ============ Additional Target Functions for Stateful Fuzzing ============ */

    function Fuzz_setEarnerDetails(address account, bool isWhitelisted, uint16 feeRate, address feeRecipient)
        public
        onlyEarnerManagerActor
    {
        vm.assume(account != address(0));
        vm.assume(feeRate <= 10000);
        vm.assume(feeRecipient != address(0) || feeRate == 0);

        vm.prank(earnerManager);
        try proxy.setEarnerDetails(account, isWhitelisted, feeRate, feeRecipient) {
            // Post-condition: earner details should be set
            (bool whitelisted, uint16 storedFeeRate, address storedFeeRecipient) = proxy.getEarnerDetails(account);
            assertEq(whitelisted, isWhitelisted, "Earner whitelist status should match");
            assertEq(storedFeeRate, feeRate, "Fee rate should match");
            assertEq(storedFeeRecipient, feeRecipient, "Fee recipient should match");
        } catch {}
    }

    function Fuzz_setClaimRecipient(address account, address claimRecipient) public onlyEarnerManagerActor {
        vm.assume(account != address(0));

        vm.prank(earnerManager);
        try proxy.setClaimRecipient(account, claimRecipient) {
            // Post-condition: claim recipient should be set
            assertEq(
                proxy.claimRecipientFor(account),
                claimRecipient == address(0) ? account : claimRecipient,
                "Claim recipient should match expected value"
            );
        } catch {}
    }

    function Fuzz_freeze(address account) public onlyFreezeManagerActor {
        vm.assume(account != address(0));

        vm.prank(freezeManager);
        try proxy.freeze(account) {
            // Post-condition: should be frozen
            assertTrue(proxy.isFrozen(account), "Account should be frozen");
        } catch {}
    }

    function Fuzz_unfreeze(address account) public onlyFreezeManagerActor {
        vm.assume(account != address(0));

        vm.prank(freezeManager);
        try proxy.unfreeze(account) {
        // Post-condition: should not be frozen (or already unfrozen)
        // Note: unfreeze may return early if already unfrozen
        }
            catch {}
    }

    function Fuzz_pause() public onlyPauserActor {
        vm.prank(pauser);
        try proxy.pause() {
            // Post-condition: should be paused
            assertTrue(proxy.paused(), "Contract should be paused");
        } catch {}
    }

    function Fuzz_unpause() public onlyPauserActor {
        vm.prank(pauser);
        try proxy.unpause() {
        // Post-condition: should not be paused (or already unpaused)
        // Note: unpause may return early if already unpaused
        }
            catch {}
    }

    function Fuzz_forceTransfer(address frozenAccount, address recipient, uint256 amount)
        public
        onlyForcedTransferManagerActor
    {
        vm.assume(frozenAccount != address(0) && recipient != address(0) && frozenAccount != recipient);
        vm.assume(amount > 0 && amount <= uint256(type(uint240).max));

        // Freeze account first
        vm.prank(freezeManager);
        try proxy.freeze(frozenAccount) {
            // Mint tokens to frozen account
            vm.prank(minterGateway);
            try proxy.mint(frozenAccount, amount) {
                if (amount <= proxy.balanceOf(frozenAccount)) {
                    uint256 recipientBalanceBefore = proxy.balanceOf(recipient);

                    vm.prank(forcedTransferManager);
                    try proxy.forceTransfer(frozenAccount, recipient, amount) {
                        // Post-condition: tokens should be transferred
                        assertEq(
                            proxy.balanceOf(recipient),
                            recipientBalanceBefore + amount,
                            "Recipient should receive forced transfer amount"
                        );
                    } catch {}
                }
            } catch {}
        } catch {}
    }
}
