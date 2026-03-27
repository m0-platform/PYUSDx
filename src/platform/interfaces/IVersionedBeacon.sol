// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { IBeacon } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";

import { IExtensionFactory } from "./IExtensionFactory.sol";

/// @title  IVersionedBeacon
/// @notice Interface for a non-upgradeable singleton beacon that resolves per-proxy implementation
///         addresses from a version registry. M0 registers approved versions; extension owners
///         choose which version their proxy runs.
/// @author M0 Labs
interface IVersionedBeacon is IBeacon {
    /* ============ Structs ============ */

    /// @notice A registered implementation version.
    struct Version {
        address implementation;
        IExtensionFactory.ExtensionType extensionType;
    }

    /* ============ Events ============ */

    /// @notice Emitted when a new implementation version is registered.
    /// @param  extensionType  The extension type this version applies to.
    /// @param  versionId      The assigned version ID (1-indexed).
    /// @param  implementation The implementation address.
    event VersionRegistered(
        IExtensionFactory.ExtensionType indexed extensionType,
        uint256 indexed versionId,
        address indexed implementation
    );

    /// @notice Emitted when the latest version is updated for an extension type.
    /// @param  extensionType The extension type.
    /// @param  versionId     The version ID now marked as latest.
    event LatestVersionSet(IExtensionFactory.ExtensionType indexed extensionType, uint256 indexed versionId);

    /// @notice Emitted when a new proxy is registered in the beacon.
    /// @param  proxy         The proxy address.
    /// @param  extensionType The extension type of the proxy.
    /// @param  versionId     The version the proxy is pinned to.
    /// @param  owner         The extension owner who controls version pinning.
    event ProxyRegistered(
        address indexed proxy,
        IExtensionFactory.ExtensionType indexed extensionType,
        uint256 indexed versionId,
        address owner
    );

    /// @notice Emitted when a proxy's pinned version changes.
    /// @param  proxy     The proxy address.
    /// @param  versionId The new pinned version (0 means follow latest).
    event ProxyVersionSet(address indexed proxy, uint256 indexed versionId);

    /* ============ Errors ============ */

    /// @notice Thrown if the implementation address is 0x0.
    error ZeroImplementation();

    /// @notice Thrown if the implementation has mismatched pyusdx or swapFacility.
    error InvalidImplementation();

    /// @notice Thrown if the extension type is not YIELD_TO_ONE or MULTI_MINT.
    error InvalidExtensionType();

    /// @notice Thrown if the version ID is 0 or out of range.
    error InvalidVersion();

    /// @notice Thrown if a version's extension type does not match the proxy's extension type.
    error VersionTypeMismatch();

    /// @notice Thrown if the proxy is not registered in the beacon.
    error ProxyNotRegistered();

    /// @notice Thrown if the proxy is already registered in the beacon.
    error ProxyAlreadyRegistered();

    /// @notice Thrown if the caller is not the proxy's registered owner.
    error NotProxyOwner();

    /// @notice Thrown if the caller is not the factory.
    error NotFactory();

    /// @notice Thrown if the factory address is 0x0.
    error ZeroFactory();

    /// @notice Thrown if the PYUSDX address is 0x0.
    error ZeroPYUSDX();

    /// @notice Thrown if the SwapFacility address is 0x0.
    error ZeroSwapFacility();

    /// @notice Thrown if the admin address is 0x0.
    error ZeroAdmin();

    /// @notice Thrown if the proxy address is 0x0.
    error ZeroProxy();

    /// @notice Thrown if the owner address is 0x0.
    error ZeroOwner();

    /* ============ Interactive Functions ============ */

    /// @notice Registers a new implementation version. Append-only — cannot overwrite existing versions.
    /// @dev    MUST only be callable by an address with the `VERSION_MANAGER_ROLE` role.
    ///         Validates that the implementation's `pyusdx()` and `swapFacility()` match this beacon's.
    /// @param  extensionType The extension type this version applies to.
    /// @param  impl          The implementation address.
    /// @return versionId     The assigned version ID (1-indexed).
    function registerVersion(
        IExtensionFactory.ExtensionType extensionType,
        address impl
    ) external returns (uint256 versionId);

    /// @notice Sets which version is "latest" for an extension type.
    /// @dev    MUST only be callable by an address with the `VERSION_MANAGER_ROLE` role.
    ///         The version must exist and match the given extension type.
    /// @param  extensionType The extension type.
    /// @param  versionId     The version to mark as latest.
    function setLatestVersion(IExtensionFactory.ExtensionType extensionType, uint256 versionId) external;

    /// @notice Registers a new proxy in the beacon, pinned to a specific version.
    /// @dev    MUST only be callable by the factory. Called BEFORE the BeaconProxy is deployed
    ///         so that `implementation()` resolves correctly during proxy construction.
    /// @param  proxy         The pre-computed proxy address.
    /// @param  extensionType The extension type.
    /// @param  versionId     The version to pin to.
    /// @param  owner         The extension owner (who controls version pinning).
    function registerProxy(
        address proxy,
        IExtensionFactory.ExtensionType extensionType,
        uint256 versionId,
        address owner
    ) external;

    /// @notice Pins the proxy to a specific registered version.
    /// @dev    MUST only be callable by the proxy's registered owner.
    ///         The version must exist and match the proxy's extension type.
    /// @param  proxy     The proxy address.
    /// @param  versionId The version to pin to.
    function pinVersion(address proxy, uint256 versionId) external;

    /// @notice Unpins the proxy so it follows the latest version for its extension type.
    /// @dev    MUST only be callable by the proxy's registered owner.
    /// @param  proxy The proxy address.
    function unpinVersion(address proxy) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role identifier for the version manager role.
    function VERSION_MANAGER_ROLE() external view returns (bytes32);

    /// @notice The factory address (immutable).
    function factory() external view returns (address);

    /// @notice The PYUSDX token address (immutable, used for implementation validation).
    function pyusdx() external view returns (address);

    /// @notice The SwapFacility address (immutable, used for implementation validation).
    function swapFacility() external view returns (address);

    /// @notice Returns the implementation for a given proxy (for off-chain use).
    /// @param  proxy The proxy address.
    /// @return The resolved implementation address.
    function implementationFor(address proxy) external view returns (address);

    /// @notice Returns the version a proxy is pinned to.
    /// @param  proxy The proxy address.
    /// @return The pinned version ID (0 means following latest).
    function proxyVersion(address proxy) external view returns (uint256);

    /// @notice Returns the registered owner of a proxy.
    /// @param  proxy The proxy address.
    /// @return The owner address.
    function proxyOwner(address proxy) external view returns (address);

    /// @notice Returns the latest version ID for an extension type.
    /// @param  extensionType The extension type.
    /// @return The latest version ID.
    function latestVersion(IExtensionFactory.ExtensionType extensionType) external view returns (uint256);

    /// @notice Returns version details.
    /// @param  versionId The version ID.
    /// @return The Version struct (implementation address and extension type).
    function getVersion(uint256 versionId) external view returns (Version memory);

    /// @notice Returns the total number of registered versions.
    /// @return The version count (excluding the dummy at index 0).
    function versionCount() external view returns (uint256);
}
