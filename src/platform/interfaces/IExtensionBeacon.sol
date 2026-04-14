// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  PYUSDX Extension Beacon interface.
/// @notice Defines the interface for the extension implementation registry.
///         Maps each ExtensionType to a versioned set of implementations.
/// @author M0 Labs
interface IExtensionBeacon {
    /* ============ Enums ============ */

    /// @notice The type of PYUSDX extension.
    enum ExtensionType {
        NONE,
        YIELD_TO_ONE,
        MULTI_MINT
    }

    /* ============ Events ============ */

    /// @notice Emitted when a new implementation is registered for an extension type.
    /// @param  extensionType  The type of extension.
    /// @param  version        The version number assigned to the implementation.
    /// @param  implementation The address of the registered implementation.
    event ImplementationRegistered(
        ExtensionType indexed extensionType,
        uint256 indexed version,
        address indexed implementation
    );

    /* ============ Errors ============ */

    /// @notice Thrown if the implementation address is 0x0.
    error ZeroImplementation();

    /// @notice Thrown if PYUSDX is 0x0.
    error ZeroPYUSDX();

    /// @notice Thrown if swap facility is 0x0.
    error ZeroSwapFacility();

    /// @notice Thrown if the admin address is 0x0.
    error ZeroAdmin();

    /// @notice Thrown if the beacon manager address is 0x0.
    error ZeroBeaconManager();

    /// @notice Thrown if PYUSDX address does not match the one in SwapFacility.
    error PYUSDXMismatch();

    /// @notice Thrown if the extension type is NONE.
    error InvalidExtensionType();

    /// @notice Thrown if the extension address is invalid (e.g. wrong pyusdx/swapFacility wiring or not a contract).
    error InvalidExtension();

    /// @notice Thrown when querying an implementation for a type with no registrations.
    error NoImplementationRegistered();

    /* ============ Interactive Functions ============ */

    /// @notice Registers a new implementation for the given extension type.
    /// @dev    MUST only be callable by an address with the `BEACON_MANAGER_ROLE` role.
    ///         Validates the implementation wiring and auto-increments the version.
    /// @param  extensionType  The type of extension to register.
    /// @param  implementation The address of the implementation contract.
    /// @return version        The version number assigned to the implementation.
    function registerImplementation(
        ExtensionType extensionType,
        address implementation
    ) external returns (uint256 version);

    /* ============ View/Pure Functions ============ */

    /// @notice The role identifier for the beacon manager role.
    function BEACON_MANAGER_ROLE() external view returns (bytes32);

    /// @notice Returns the latest registered implementation for the given extension type.
    /// @param  extensionType The type of extension.
    /// @return The address of the latest implementation.
    function implementation(ExtensionType extensionType) external view returns (address);

    /// @notice Returns the implementation for the given extension type at a specific version.
    /// @param  extensionType The type of extension.
    /// @param  version       The version number.
    /// @return The address of the implementation at the specified version.
    function implementation(ExtensionType extensionType, uint256 version) external view returns (address);

    /// @notice Returns the latest version number for the given extension type.
    /// @dev    Version numbering starts at 1 (the first registered implementation is version 1).
    /// @param  extensionType The type of extension.
    /// @return The latest version number.
    function latestVersion(ExtensionType extensionType) external view returns (uint256);

    /// @notice The address of the PYUSDX token contract.
    function pyusdx() external view returns (address);

    /// @notice The address of the SwapFacility contract.
    function swapFacility() external view returns (address);
}
