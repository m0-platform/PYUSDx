// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPYUSDXExtension } from "../../src/interfaces/IPYUSDXExtension.sol";

/**
 * @title  ReentrantExtensionMock
 * @notice Mock extension whose transferFrom reenters the caller's wrapFrom.
 *         Used to test the reentrancy guard.
 */
contract ReentrantExtensionMock {
    address public target;
    address public pyusdx;

    constructor(address target_, address pyusdx_) {
        target = target_;
        pyusdx = pyusdx_;
    }

    function transferFrom(address, address, uint256 amount) external returns (bool) {
        // Reenter the target extension's wrapFrom during transferFrom.
        IPYUSDXExtension(target).wrapFrom(address(this), amount);
        return true;
    }

    function unwrap(uint256) external pure {
        // Intentionally does nothing.
    }
}
