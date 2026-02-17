// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/**
 * @title  MaliciousExtensionMock
 * @notice Mock extension that accepts transferFrom but does nothing on unwrap (no PYUSDX sent).
 *         Used to test the balance-diff check in wrapFrom.
 */
contract MaliciousExtensionMock {
    address public pyusdx;

    constructor(address pyusdx_) {
        pyusdx = pyusdx_;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function unwrap(uint256) external pure {
        // Intentionally does nothing — no PYUSDX is sent.
    }
}
