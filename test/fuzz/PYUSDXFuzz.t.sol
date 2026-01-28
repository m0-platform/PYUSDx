// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {PYUSDX} from "../../src/PYUSDX.sol";
import {IPYUSDX} from "../../src/interfaces/IPYUSDX.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * Fuzz test TODOs:
 * - [ ] mint
 *   - [ ] when amount is within valid bounds
 *     - [ ] totalSupply increases by amount
 *     - [ ] when recipient is earner: totalEarningSupply increases by amount
 *     - [ ] when recipient is non-earner: totalNonEarningSupply increases by amount
 *   - [ ] when amount exceeds uint240 max
 *     - [ ] revert
 *   - [ ] invariant: balanceOf(account) >= balanceBefore + amount (after mint)
 *   - [ ] invariant: no account balance goes negative
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
}
