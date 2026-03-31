// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

/// @title  MockVersionedBeacon
/// @notice Minimal mock that implements only `isProxyPaused` for unit-testing beacon-based pause.
contract MockVersionedBeacon {
    bool private _paused;

    function setPaused(bool paused_) external {
        _paused = paused_;
    }

    function isProxyPaused(address) external view returns (bool) {
        return _paused;
    }
}
