// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";

/// @title ExtensionFactory Harness
/// @notice Test harness that exposes internal functions for testing
contract ExtensionFactoryHarness is ExtensionFactory {
    /// @notice Constructs the harness with the same parameters as ExtensionFactory
    constructor(
        address pyusdx_,
        address swapFacility_,
        address yieldToOneBeacon_,
        address multiMintBeacon_
    ) ExtensionFactory(pyusdx_, swapFacility_, yieldToOneBeacon_, multiMintBeacon_) {}

    /// @notice Writes an extension's type directly, bypassing the role check and validation in
    ///         `setExtensionType`. For unit tests that need to swap against pre-registered extensions
    ///         without bootstrapping the FACTORY_MANAGER_ROLE flow.
    /// @param proxy         The address of the extension proxy.
    /// @param extensionType The type of the extension.
    function registerExtension(address proxy, ExtensionType extensionType) external {
        _getExtensionFactoryStorage().extensionTypes[proxy] = extensionType;
    }
}
