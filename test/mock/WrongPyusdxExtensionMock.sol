// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @dev Minimal mock that returns a different `pyusdx()` address. Used to test extension validation.
contract WrongPyusdxExtensionMock {
    function pyusdx() external pure returns (address) {
        return address(0xdead);
    }
}
