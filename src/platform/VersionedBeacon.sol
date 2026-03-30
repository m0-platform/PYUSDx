// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { AccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

import { IExtension } from "./interfaces/IExtension.sol";
import { IVersionedBeacon } from "./interfaces/IVersionedBeacon.sol";

/// @title  VersionedBeacon
/// @notice A non-upgradeable singleton beacon that resolves per-proxy implementation addresses
///         from an append-only version registry. M0 registers approved versions; extension owners
///         choose which version their proxy runs. M0 cannot force-upgrade any extension.
///         Extension types are identified by `bytes32` type keys, making the beacon agnostic to
///         which types exist. New types are implicitly created on first `registerVersion` call.
/// @author M0 Labs
contract VersionedBeacon is IVersionedBeacon, AccessControl {
    /* ============ Variables ============ */

    /// @inheritdoc IVersionedBeacon
    bytes32 public constant VERSION_MANAGER_ROLE = keccak256("VERSION_MANAGER_ROLE");

    /// @inheritdoc IVersionedBeacon
    address public immutable factory;

    /// @inheritdoc IVersionedBeacon
    address public immutable pyusdx;

    /// @inheritdoc IVersionedBeacon
    address public immutable swapFacility;

    /// @dev 1-indexed implementation arrays per type key.
    ///      Index 0 is a dummy entry, pushed lazily on first registerVersion call for each type.
    mapping(bytes32 typeKey => address[] implementations) internal _implementations;

    /// @dev Latest version ID per type key.
    mapping(bytes32 typeKey => uint256 versionId) internal _latestVersion;

    /// @dev Per-proxy registration and version state.
    ///      A proxy is considered registered if typeKey != bytes32(0).
    struct ProxyInfo {
        bytes32 typeKey;
        address owner;
        uint256 pinnedVersion; // 0 = follow latest
    }

    mapping(address proxy => ProxyInfo info) internal _proxies;

    /* ============ Constructor ============ */

    /// @notice Constructs the VersionedBeacon. This contract is NOT upgradeable.
    /// @param  factory_        The ExtensionFactory proxy address (only caller of registerProxy).
    /// @param  pyusdx_         The PYUSDX token address (for implementation validation).
    /// @param  swapFacility_   The SwapFacility address (for implementation validation).
    /// @param  admin_          The address granted DEFAULT_ADMIN_ROLE.
    /// @param  versionManager_ The address granted VERSION_MANAGER_ROLE.
    constructor(address factory_, address pyusdx_, address swapFacility_, address admin_, address versionManager_) {
        if (factory_ == address(0)) revert ZeroFactory();
        if (pyusdx_ == address(0)) revert ZeroPYUSDX();
        if (swapFacility_ == address(0)) revert ZeroSwapFacility();
        if (admin_ == address(0)) revert ZeroAdmin();
        if (versionManager_ == address(0)) revert ZeroVersionManager();

        factory = factory_;
        pyusdx = pyusdx_;
        swapFacility = swapFacility_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(VERSION_MANAGER_ROLE, versionManager_);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IVersionedBeacon
    function registerVersion(
        bytes32 typeKey,
        address impl
    ) external onlyRole(VERSION_MANAGER_ROLE) returns (uint256 versionId) {
        if (typeKey == bytes32(0)) revert InvalidTypeKey();

        _revertIfInvalidImplementation(impl);

        address[] storage impls = _implementations[typeKey];

        // Lazy-init: push dummy at index 0 on first version registration for this type.
        if (impls.length == 0) impls.push(address(0));

        impls.push(impl);

        // NOTE: Safe because length >= 2 after the push above.
        unchecked {
            versionId = impls.length - 1;
        }

        emit VersionRegistered(typeKey, versionId, impl);
    }

    /// @inheritdoc IVersionedBeacon
    function setLatestVersion(bytes32 typeKey, uint256 versionId) external onlyRole(VERSION_MANAGER_ROLE) {
        _revertIfInvalidVersionId(typeKey, versionId);

        _latestVersion[typeKey] = versionId;

        emit LatestVersionSet(typeKey, versionId);
    }

    /// @inheritdoc IVersionedBeacon
    function registerProxy(address proxy, bytes32 typeKey, uint256 versionId, address owner) external {
        if (msg.sender != factory) revert NotFactory();
        if (proxy == address(0)) revert ZeroProxy();
        if (owner == address(0)) revert ZeroOwner();
        if (_proxies[proxy].typeKey != bytes32(0)) revert ProxyAlreadyRegistered();

        _revertIfInvalidVersionId(typeKey, versionId);

        _proxies[proxy] = ProxyInfo({ typeKey: typeKey, owner: owner, pinnedVersion: versionId });

        emit ProxyRegistered(proxy, typeKey, versionId, owner);
    }

    /// @inheritdoc IVersionedBeacon
    function pinVersion(address proxy, uint256 versionId) external {
        ProxyInfo storage info = _proxies[proxy];
        if (info.typeKey == bytes32(0)) revert ProxyNotRegistered();
        if (msg.sender != info.owner) revert NotProxyOwner();

        if (versionId != 0) {
            _revertIfInvalidVersionId(info.typeKey, versionId);
        }

        info.pinnedVersion = versionId;

        emit ProxyVersionSet(proxy, versionId);
    }

    /* ============ View/Pure Functions ============ */

    /// @dev Returns the implementation for the calling proxy. Reverts if the caller is not registered.
    function implementation() external view returns (address) {
        return _resolveImplementation(msg.sender);
    }

    /// @inheritdoc IVersionedBeacon
    function implementationFor(address proxy) external view returns (address) {
        return _resolveImplementation(proxy);
    }

    /// @inheritdoc IVersionedBeacon
    function proxyVersion(address proxy) external view returns (uint256) {
        return _proxies[proxy].pinnedVersion;
    }

    /// @inheritdoc IVersionedBeacon
    function proxyOwner(address proxy) external view returns (address) {
        return _proxies[proxy].owner;
    }

    /// @inheritdoc IVersionedBeacon
    function proxyTypeKey(address proxy) external view returns (bytes32) {
        return _proxies[proxy].typeKey;
    }

    /// @inheritdoc IVersionedBeacon
    function latestVersion(bytes32 typeKey) external view returns (uint256) {
        return _latestVersion[typeKey];
    }

    /// @inheritdoc IVersionedBeacon
    function getVersion(bytes32 typeKey, uint256 versionId) external view returns (address) {
        _revertIfInvalidVersionId(typeKey, versionId);
        return _implementations[typeKey][versionId];
    }

    /// @inheritdoc IVersionedBeacon
    function versionCount(bytes32 typeKey) external view returns (uint256) {
        uint256 length = _implementations[typeKey].length;
        if (length == 0) return 0;

        // NOTE: Subtract 1 for the dummy at index 0.
        unchecked {
            return length - 1;
        }
    }

    /* ============ Internal View Functions ============ */

    /// @dev   Resolves the implementation address for a given proxy.
    /// @param proxy The proxy address.
    function _resolveImplementation(address proxy) internal view returns (address) {
        ProxyInfo storage info = _proxies[proxy];
        if (info.typeKey == bytes32(0)) revert ProxyNotRegistered();

        uint256 versionId = info.pinnedVersion;
        if (versionId == 0) {
            versionId = _latestVersion[info.typeKey];
        }

        return _implementations[info.typeKey][versionId];
    }

    /// @dev   Reverts if the version ID is 0 or out of range for the given type key.
    /// @param typeKey   The extension type key.
    /// @param versionId The version ID to validate.
    function _revertIfInvalidVersionId(bytes32 typeKey, uint256 versionId) internal view {
        if (versionId == 0 || versionId >= _implementations[typeKey].length) revert InvalidVersion();
    }

    /// @dev   Reverts if the implementation address is zero or wired to wrong pyusdx/swapFacility.
    /// @param impl The implementation address to validate.
    function _revertIfInvalidImplementation(address impl) internal view {
        if (impl == address(0)) revert ZeroImplementation();

        if (IExtension(impl).pyusdx() != pyusdx || IExtension(impl).swapFacility() != swapFacility)
            revert InvalidImplementation();
    }
}
