// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Test } from "../../lib/evm-m-extensions/lib/forge-std/src/Test.sol";

import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";

contract ExtensionUnitTests is Test {
    address public pyusdx = makeAddr("pyusdx");
    address public swapFacility = makeAddr("swapFacility");

    /* ============ constructor ============ */

    function testUnit_constructor_revert_zeroPYUSDX() public {
        vm.expectRevert(IExtension.ZeroPYUSDX.selector);
        new YieldToOne(address(0), swapFacility);
    }

    function testUnit_constructor_revert_zeroSwapFacility() public {
        vm.expectRevert(IExtension.ZeroSwapFacility.selector);
        new YieldToOne(pyusdx, address(0));
    }
}
