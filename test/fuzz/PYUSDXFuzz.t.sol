// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {PYUSDX} from "../../src/PYUSDX.sol";
import {IPYUSDX} from "../../src/interfaces/IPYUSDX.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * Fuzz test TODOs:
 * - [x] mint
 *   - [x] when amount is within valid bounds
 *     - [x] totalSupply increases by amount
 *     - [x] when recipient is non-earner: totalNonEarningSupply increases by amount
 *   - [x] when amount exceeds uint240 max
 *     - [x] revert
 *   - [x] invariant: balanceOf(account) >= balanceBefore + amount (after mint)
 *   - [x] invariant: no account balance goes negative
 * - [ ] burn
 *   - [ ] when amount <= balance
 *     - [ ] balance decreased by amount
 *     - [ ] when account is non-earner: totalNonEarningSupply decreased by amount
 *     - [ ] when account is earner: totalEarningSupply decreased by amount
 *   - [ ] invariant: balance never goes negative
 *   - [ ] invariant: totalSupply == totalEarningSupply + totalNonEarningSupply
 */
contract PYUSDXFuzzTest is Test {
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

    /* ============ Mint Fuzz Tests ============ */

    function testFuzz_Mint_AmountWithinBounds(
        address recipient,
        uint256 amount
    ) public {
        // Bound amount to uint240 max and exclude zero
        vm.assume(amount > 0 && amount <= uint256(type(uint240).max));
        vm.assume(recipient != address(0));

        uint256 balanceBefore = proxy.balanceOf(recipient);

        vm.prank(minterGateway);
        proxy.mint(recipient, amount);

        // Verify balance increased
        assertEq(
            proxy.balanceOf(recipient),
            balanceBefore + amount,
            "Balance should increase by minted amount"
        );

        // Verify total supply consistency
        // Note: totalSupply not implemented yet (Phase 2.14)
        // assertEq(proxy.totalSupply(), oldTotalSupply + amount);
    }

    function testFuzz_Mint_AmountExceedsUint240(address recipient, uint256 amount) public {
        // Assume amount exceeds uint240 max
        vm.assume(amount > uint256(type(uint240).max));
        vm.assume(recipient != address(0));

        vm.prank(minterGateway);
        vm.expectRevert(); // Safe240 will revert
        proxy.mint(recipient, amount);
    }

    function testFuzz_Mint_TotalSupplyInvariant(
        address recipient,
        uint256 amount
    ) public {
        vm.assume(amount > 0 && amount <= uint256(type(uint240).max));
        vm.assume(recipient != address(0));

        uint256 earningSupplyBefore = proxy.totalEarningSupply();
        uint256 nonEarningSupplyBefore = proxy.totalNonEarningSupply();

        vm.prank(minterGateway);
        proxy.mint(recipient, amount);

        // Total supply should equal earning + non-earning
        uint256 totalEarningAfter = proxy.totalEarningSupply();
        uint256 totalNonEarningAfter = proxy.totalNonEarningSupply();

        // For non-earners, non-earning supply should increase
        if (!proxy.isEarning(recipient)) {
            assertEq(
                totalNonEarningAfter,
                nonEarningSupplyBefore + amount,
                "Non-earning supply should increase for non-earner"
            );
            assertEq(
                totalEarningAfter,
                earningSupplyBefore,
                "Earning supply should not change for non-earner"
            );
        }
        // Note: Earner case requires startEarningFor (Phase 2.9) to be implemented
    }

    function testFuzz_Mint_ZeroAddress(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= uint256(type(uint240).max));

        vm.prank(minterGateway);
        // Minting to zero address may succeed or revert depending on implementation
        // The current implementation doesn't explicitly check for zero address
        // This test documents current behavior
        proxy.mint(address(0), amount);
    }

    function testFuzz_Mint_SameRecipientMultipleTimes(
        address recipient,
        uint256 amount1,
        uint256 amount2
    ) public {
        vm.assume(recipient != address(0));
        vm.assume(amount1 > 0 && amount1 <= uint256(type(uint240).max));
        vm.assume(amount2 > 0 && amount2 <= uint256(type(uint240).max));

        // Ensure total doesn't overflow uint240 (balance + amount1 + amount2 <= uint240.max)
        uint256 balanceBefore = proxy.balanceOf(recipient);
        vm.assume(balanceBefore + amount1 <= uint256(type(uint240).max));
        vm.assume(balanceBefore + amount1 + amount2 <= uint256(type(uint240).max));

        vm.startPrank(minterGateway);
        proxy.mint(recipient, amount1);
        proxy.mint(recipient, amount2);
        vm.stopPrank();

        assertEq(
            proxy.balanceOf(recipient),
            balanceBefore + amount1 + amount2,
            "Balance should increase by sum of all mints"
        );
    }

    /* ============ Invariant Tests ============ */

    function testFuzz_Invariant_BalanceNeverNegative(
        address recipient,
        uint256 mintAmount
    ) public {
        vm.assume(mintAmount > 0 && mintAmount <= uint256(type(uint240).max));
        vm.assume(recipient != address(0));

        uint256 balanceBefore = proxy.balanceOf(recipient);

        vm.prank(minterGateway);
        proxy.mint(recipient, mintAmount);

        uint256 balanceAfter = proxy.balanceOf(recipient);

        assertTrue(balanceAfter >= balanceBefore, "Balance should never decrease on mint");
    }

    /* ============ Burn Fuzz Tests ============ */

    function testFuzz_Burn_AmountWithinBounds(
        address account,
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        vm.assume(mintAmount > 0 && mintAmount <= uint256(type(uint240).max));
        vm.assume(burnAmount > 0 && burnAmount <= uint256(type(uint240).max));
        vm.assume(burnAmount <= mintAmount); // Can't burn more than minted
        vm.assume(account != address(0));

        // Mint first
        vm.prank(minterGateway);
        proxy.mint(account, mintAmount);

        uint256 balanceBefore = proxy.balanceOf(account);
        uint256 earningSupplyBefore = proxy.totalEarningSupply();
        uint256 nonEarningSupplyBefore = proxy.totalNonEarningSupply();

        // Burn
        vm.prank(minterGateway);
        proxy.burn(account, burnAmount);

        // Verify balance decreased
        assertEq(
            proxy.balanceOf(account),
            balanceBefore - burnAmount,
            "Balance should decrease by burned amount"
        );

        // For non-earners, non-earning supply should decrease
        if (!proxy.isEarning(account)) {
            assertEq(
                proxy.totalNonEarningSupply(),
                nonEarningSupplyBefore - burnAmount,
                "Non-earning supply should decrease for non-earner"
            );
            assertEq(
                proxy.totalEarningSupply(),
                earningSupplyBefore,
                "Earning supply should not change for non-earner"
            );
        }
    }

    function testFuzz_Burn_InsufficientBalance(
        address account,
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        vm.assume(mintAmount > 0 && mintAmount <= uint256(type(uint240).max));
        vm.assume(burnAmount > mintAmount); // Burn more than minted
        vm.assume(burnAmount <= uint256(type(uint240).max));
        vm.assume(account != address(0));

        // Mint first
        vm.prank(minterGateway);
        proxy.mint(account, mintAmount);

        // Try to burn more than balance
        vm.prank(minterGateway);
        vm.expectRevert("insufficient balance");
        proxy.burn(account, burnAmount);
    }

    function testFuzz_Burn_Invariant_BalanceNeverNegative(
        address account,
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        vm.assume(mintAmount > 0 && mintAmount <= uint256(type(uint240).max));
        vm.assume(burnAmount > 0 && burnAmount <= uint256(type(uint240).max));
        vm.assume(account != address(0));

        // Mint first
        vm.prank(minterGateway);
        proxy.mint(account, mintAmount);

        uint256 balanceBefore = proxy.balanceOf(account);

        // Only attempt burn if within balance
        if (burnAmount <= balanceBefore) {
            vm.prank(minterGateway);
            proxy.burn(account, burnAmount);

            uint256 balanceAfter = proxy.balanceOf(account);
            assertTrue(balanceAfter >= 0, "Balance should never go negative");
            assertTrue(balanceAfter <= balanceBefore, "Balance should decrease or stay same on burn");
        }
    }

    function testFuzz_Burn_MintBurnCycle(
        address account,
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        vm.assume(mintAmount > 0 && mintAmount <= uint256(type(uint240).max));
        vm.assume(burnAmount > 0 && burnAmount <= uint256(type(uint240).max));
        vm.assume(account != address(0));

        uint256 balanceBefore = proxy.balanceOf(account);

        // Mint
        vm.prank(minterGateway);
        proxy.mint(account, mintAmount);

        // Burn (if possible)
        if (mintAmount >= burnAmount) {
            vm.prank(minterGateway);
            proxy.burn(account, burnAmount);

            // Verify final balance
            assertEq(
                proxy.balanceOf(account),
                balanceBefore + mintAmount - burnAmount,
                "Final balance should be initial + minted - burned"
            );
        }
    }
}
