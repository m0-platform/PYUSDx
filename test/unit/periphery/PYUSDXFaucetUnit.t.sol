// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { IPYUSDXFaucet } from "../../../src/periphery/interfaces/IPYUSDXFaucet.sol";
import { PYUSDXFaucet } from "../../../src/periphery/PYUSDXFaucet.sol";

import { MockERC20 } from "../../mock/MockERC20.sol";

contract PYUSDXFaucetTests is Test {
    MockERC20 public pyusdx;
    PYUSDXFaucet public faucet;

    uint256 public constant AMOUNT = 100e6;

    function setUp() public {
        pyusdx = new MockERC20("PayPal USD", "PYUSD", 6);
        faucet = new PYUSDXFaucet(address(pyusdx));
    }

    /* ============ constructor ============ */

    function test_constructor_zeroPYUSDX() public {
        vm.expectRevert(abi.encodeWithSelector(IPYUSDXFaucet.ZeroPYUSDX.selector));

        new PYUSDXFaucet(address(0));
    }

    function test_constructor() public view {
        assertEq(faucet.pyusdx(), address(pyusdx));
        assertEq(faucet.AMOUNT(), AMOUNT);
    }

    /* ============ requestPYUSDX ============ */

    function test_requestPYUSDX_insufficientBalance() public {
        pyusdx.mint(address(faucet), AMOUNT - 1);

        address recipient = makeAddr("recipient");

        vm.expectRevert(abi.encodeWithSelector(IPYUSDXFaucet.InsufficientFaucetBalance.selector, AMOUNT, AMOUNT - 1));

        faucet.requestPYUSDX(recipient);
    }

    function test_requestPYUSDX() public {
        pyusdx.mint(address(faucet), AMOUNT);

        address recipient = makeAddr("recipient");

        vm.expectEmit();
        emit IPYUSDXFaucet.Requested(recipient, AMOUNT);

        faucet.requestPYUSDX(recipient);

        assertEq(pyusdx.balanceOf(recipient), AMOUNT);
        assertEq(pyusdx.balanceOf(address(faucet)), 0);
    }

    function test_requestPYUSDX_drainsAcrossCalls() public {
        pyusdx.mint(address(faucet), 2 * AMOUNT);

        address first = makeAddr("first");
        address second = makeAddr("second");
        address third = makeAddr("third");

        faucet.requestPYUSDX(first);
        faucet.requestPYUSDX(second);

        assertEq(pyusdx.balanceOf(first), AMOUNT);
        assertEq(pyusdx.balanceOf(second), AMOUNT);
        assertEq(pyusdx.balanceOf(address(faucet)), 0);

        vm.expectRevert(abi.encodeWithSelector(IPYUSDXFaucet.InsufficientFaucetBalance.selector, AMOUNT, 0));

        faucet.requestPYUSDX(third);
    }
}
