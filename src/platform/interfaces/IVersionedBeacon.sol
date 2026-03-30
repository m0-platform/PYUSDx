// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { IBeacon } from "../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";

/// @title  IVersionedBeacon
/// @notice Interface for a non-upgradeable singleton beacon that resolves per-proxy implementation
///         addresses from a version registry. M0 registers approved versions; extension owners
///         choose which version their proxy runs. Extension types are identified by `bytes32` type
///         keys (e.g., `keccak256("YIELD_TO_ONE")`), making the beacon agnostic to which types exist.
/// @author M0 Labs
interface IVersionedBeacon is IBeacon {
    /* ============ Events ============ */

    /// @notice Emitted when a new implementation version is registered.
    /// @param  typeKey        The extension type key.
    /// @param  versionId      The assigned version ID (1-indexed, per type key).
    /// @param  implementation The implementation address.
    event VersionRegistered(bytes32 indexed typeKey, uint256 indexed versionId, address indexed implementation);

    /// @notice Emitted when the latest version is updated for an extension type.
    /// @param  typeKey   The extension type key.
    /// @param  versionId The version ID now marked as latest.
    event LatestVersionSet(bytes32 indexed typeKey, uint256 indexed versionId);

    /// @notice Emitted when a new proxy is registered in the beacon.
    /// @param  proxy     The proxy address.
    /// @param  typeKey   The extension type key of the proxy.
    /// @param  versionId The version the proxy is pinned to.
    /// @param  owner     The extension owner who controls version pinning.
    event ProxyRegistered(address indexed proxy, bytes32 indexed typeKey, uint256 indexed versionId, address owner);

    /// @notice Emitted when a proxy's pinned version changes.
    /// @param  proxy     The proxy address.
    /// @param  versionId The new pinned version (0 means follow latest).
    event ProxyVersionSet(address indexed proxy, uint256 indexed versionId);

    /// @notice Emitted when a proxy's ownership is transferred.
    /// @param  proxy        The proxy address.
    /// @param  previousOwner The previous owner address.
    /// @param  newOwner     The new owner address.
    event ProxyOwnershipTransferred(address indexed proxy, address indexed previousOwner, address indexed newOwner);

    /* ============ Errors ============ */

    /// @notice Thrown if the implementation address is 0x0.
    error ZeroImplementation();

    /// @notice Thrown if the implementation has mismatched pyusdx or swapFacility.
    error InvalidImplementation();

    /// @notice Thrown if the type key is bytes32(0).
    error InvalidTypeKey();

    /// @notice Thrown if the version ID is 0 or out of range for the given type key.
    error InvalidVersion();

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

    /// @notice Thrown if the version manager address is 0x0.
    error ZeroVersionManager();

    /// @notice Thrown if the proxy address is 0x0.
    error ZeroProxy();

    /// @notice Thrown if the owner address is 0x0.
    error ZeroOwner();

    /* ============ Interactive Functions ============ */

    /// @notice Registers a new implementation version. Append-only — cannot overwrite existing versions.
    /// @dev    MUST only be callable by an address with the `VERSION_MANAGER_ROLE` role.
    ///         Validates that the implementation's `pyusdx()` and `swapFacility()` match this beacon's.
    ///         Version IDs are scoped per type key and 1-indexed. The first call for a new type key
    ///         implicitly initializes that type.
    /// @param  typeKey   The extension type key (e.g., `keccak256("YIELD_TO_ONE")`).
    /// @param  impl      The implementation address.
    /// @return versionId The assigned version ID (1-indexed, per type key).
    function registerVersion(bytes32 typeKey, address impl) external returns (uint256 versionId);

    /// @notice Sets which version is "latest" for an extension type.
    /// @dev    MUST only be callable by an address with the `VERSION_MANAGER_ROLE` role.
    /// @param  typeKey   The extension type key.
    /// @param  versionId The version to mark as latest.
    function setLatestVersion(bytes32 typeKey, uint256 versionId) external;

    /// @notice Registers a new proxy in the beacon, pinned to a specific version.
    /// @dev    MUST only be callable by the factory. Called BEFORE the BeaconProxy is deployed
    ///         so that `implementation()` resolves correctly during proxy construction.
    /// @param  proxy     The pre-computed proxy address.
    /// @param  typeKey   The extension type key.
    /// @param  versionId The version to pin to.
    /// @param  owner     The extension owner (who controls version pinning).
    function registerProxy(address proxy, bytes32 typeKey, uint256 versionId, address owner) external;

    /// @notice Pins the proxy to a specific registered version, or unpins it to follow latest.
    /// @dev    MUST only be callable by the proxy's registered owner.
    ///         If `versionId` is 0, the proxy follows the latest version for its type.
    ///         If `versionId` is nonzero, it must exist for the proxy's type.
    /// @param  proxy     The proxy address.
    /// @param  versionId The version to pin to (0 = follow latest).
    function pinVersion(address proxy, uint256 versionId) external;

    /// @notice Transfers ownership of a proxy to a new address.
    /// @dev    MUST only be callable by the proxy's current registered owner.
    /// @param  proxy    The proxy address.
    /// @param  newOwner The new owner address.
    function transferProxyOwnership(address proxy, address newOwner) external;

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

    /// @notice Returns the type key of a registered proxy.
    /// @param  proxy The proxy address.
    /// @return The type key (bytes32(0) if not registered).
    function proxyTypeKey(address proxy) external view returns (bytes32);

    /// @notice Returns the latest version ID for a type key.
    /// @param  typeKey The extension type key.
    /// @return The latest version ID.
    function latestVersion(bytes32 typeKey) external view returns (uint256);

    /// @notice Returns the implementation address for a given type key and version.
    /// @param  typeKey   The extension type key.
    /// @param  versionId The version ID (1-indexed, per type key).
    /// @return The implementation address.
    function getVersion(bytes32 typeKey, uint256 versionId) external view returns (address);

    /// @notice Returns the total number of registered versions for a type key.
    /// @param  typeKey The extension type key.
    /// @return The version count (excluding the dummy at index 0).
    function versionCount(bytes32 typeKey) external view returns (uint256);
}
