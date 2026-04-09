// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";

/// @title ExtensionFactory Harness
/// @notice Test harness that exposes internal functions for testing
contract ExtensionFactoryHarness is ExtensionFactory {
    /// @notice Constructs the harness with the same parameters as ExtensionFactory
    constructor(
        address pyusdx_,
        address swapFacility_,
        address extensionBeacon_
    ) ExtensionFactory(pyusdx_, swapFacility_, extensionBeacon_) {}

    /// @notice Exposes internal _registerExtension for testing
    /// @param proxy The address of the extension proxy
    /// @param extensionType The type of the extension
    function registerExtension(address proxy, IExtensionBeacon.ExtensionType extensionType) external {
        _registerExtension(proxy, extensionType);
    }
}
