// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

/// @title  MockVersionedBeacon
/// @notice Minimal mock that implements `isProxyPaused` and `isFrozen` for unit-testing.
contract MockVersionedBeacon {
    bool private _paused;
    mapping(address => bool) private _frozen;

    function setPaused(bool paused_) external {
        _paused = paused_;
    }

    function isProxyPaused(address) external view returns (bool) {
        return _paused;
    }

    function setFrozen(address account, bool frozen_) external {
        _frozen[account] = frozen_;
    }

    function isFrozen(address account) external view returns (bool) {
        return _frozen[account];
    }
}
