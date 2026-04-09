// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";

/// @title Mock Extension Beacon
/// @notice A minimal mock implementing IExtensionBeacon for unit tests.
contract MockExtensionBeacon is IExtensionBeacon {
    mapping(IExtensionBeacon.ExtensionType => address) private _implementations;

    function setImplementation(IExtensionBeacon.ExtensionType extensionType, address impl) external {
        _implementations[extensionType] = impl;
    }

    function registerImplementation(
        IExtensionBeacon.ExtensionType extensionType,
        address implementation
    ) external returns (uint256 version) {
        _implementations[extensionType] = implementation;
        version = 1;
    }

    function implementation(IExtensionBeacon.ExtensionType extensionType) external view returns (address) {
        return _implementations[extensionType];
    }

    function implementation(
        IExtensionBeacon.ExtensionType extensionType,
        uint256 /* version */
    ) external view returns (address) {
        return _implementations[extensionType];
    }

    function latestVersion(IExtensionBeacon.ExtensionType) external pure returns (uint256) {
        return 1;
    }

    function pyusdx() external pure returns (address) {
        return address(0);
    }

    function swapFacility() external pure returns (address) {
        return address(0);
    }

    function BEACON_MANAGER_ROLE() external pure returns (bytes32) {
        return keccak256("BEACON_MANAGER_ROLE");
    }
}
