// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";

/// @title Mock Extension Beacon
/// @notice A minimal mock implementing IExtensionBeacon for unit tests.
contract MockExtensionBeacon is IExtensionBeacon {
    mapping(uint256 => address) private _implementations;
    uint256 private _latestVersion;
    address private _latestImpl;
    address private immutable _pyusdx;
    address private immutable _swapFacility;

    constructor(address pyusdx_, address swapFacility_) {
        _pyusdx = pyusdx_;
        _swapFacility = swapFacility_;
    }

    function setImplementation(address implementation_) external {
        _latestVersion++;
        _implementations[_latestVersion] = implementation_;
        _latestImpl = implementation_;
    }

    function registerImplementation(address implementation_) external returns (uint256 version) {
        _latestVersion++;
        version = _latestVersion;
        _implementations[version] = implementation_;
        _latestImpl = implementation_;
    }

    function implementation() external view returns (address) {
        return _latestImpl;
    }

    function implementation(uint256 version) external view returns (address) {
        return _implementations[version];
    }

    function latestVersion() external pure returns (uint256) {
        return 1;
    }

    function pyusdx() external view returns (address) {
        return _pyusdx;
    }

    function swapFacility() external view returns (address) {
        return _swapFacility;
    }

    function BEACON_MANAGER_ROLE() external pure returns (bytes32) {
        return keccak256("BEACON_MANAGER_ROLE");
    }
}
