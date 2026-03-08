// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";

/// @title ExtensionFactory Harness
/// @notice Test harness that exposes internal functions for testing
contract ExtensionFactoryHarness is ExtensionFactory {
    /// @notice Constructs the harness with the same parameters as ExtensionFactory
    constructor(address pyusdx_, address swapFacility_) ExtensionFactory(pyusdx_, swapFacility_) {}

    /// @notice Exposes internal _registerExtension for testing
    /// @param proxy The address of the extension proxy
    /// @param extensionType The type of the extension
    function registerExtension(address proxy, IExtensionFactory.ExtensionType extensionType) external {
        _registerExtension(proxy, extensionType);
    }
}
