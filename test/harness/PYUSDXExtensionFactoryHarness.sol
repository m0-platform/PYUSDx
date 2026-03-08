// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPYUSDXExtensionFactory } from "../../src/deploy/interfaces/IPYUSDXExtensionFactory.sol";
import { PYUSDXExtensionFactory } from "../../src/deploy/PYUSDXExtensionFactory.sol";

/// @title PYUSDXExtensionFactory Harness
/// @notice Test harness that exposes internal functions for testing
contract PYUSDXExtensionFactoryHarness is PYUSDXExtensionFactory {
    /// @notice Constructs the harness with the same parameters as PYUSDXExtensionFactory
    constructor(address pyusdx_, address swapFacility_) PYUSDXExtensionFactory(pyusdx_, swapFacility_) {}

    /// @notice Exposes internal _registerExtension for testing
    /// @param proxy The address of the extension proxy
    /// @param extensionType The type of the extension
    function registerExtension(address proxy, IPYUSDXExtensionFactory.ExtensionType extensionType) external {
        _registerExtension(proxy, extensionType);
    }
}
