// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { AccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

import { IExtensionFactory } from "./interfaces/IExtensionFactory.sol";
import { IVersionedBeacon } from "./interfaces/IVersionedBeacon.sol";

/// @dev Minimal interface for reading extension immutables during implementation validation.
interface IExtensionLike {
    function pyusdx() external view returns (address);
    function swapFacility() external view returns (address);
}

/// @title  VersionedBeacon
/// @notice A non-upgradeable singleton beacon that resolves per-proxy implementation addresses
///         from an append-only version registry. M0 registers approved versions; extension owners
///         choose which version their proxy runs. M0 cannot force-upgrade any extension.
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

    /// @dev 1-indexed version array. Index 0 is a dummy entry so version IDs start at 1.
    Version[] internal _versions;

    /// @dev Latest version ID per extension type.
    mapping(IExtensionFactory.ExtensionType extensionType => uint256 versionId) internal _latestVersion;

    /// @dev Per-proxy registration and version state.
    struct ProxyInfo {
        IExtensionFactory.ExtensionType extensionType;
        address owner;
        uint256 pinnedVersion; // 0 = follow latest
        bool registered;
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

        // Push dummy at index 0 so version IDs are 1-indexed.
        _versions.push(Version(address(0), IExtensionFactory.ExtensionType.NONE));
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IVersionedBeacon
    function registerVersion(
        IExtensionFactory.ExtensionType extensionType,
        address impl
    ) external onlyRole(VERSION_MANAGER_ROLE) returns (uint256 versionId) {
        if (
            extensionType != IExtensionFactory.ExtensionType.YIELD_TO_ONE &&
            extensionType != IExtensionFactory.ExtensionType.MULTI_MINT
        ) revert InvalidExtensionType();

        _revertIfInvalidImplementation(impl);

        _versions.push(Version(impl, extensionType));

        // NOTE: Safe because we always have at least the dummy at index 0, so length >= 2 here.
        unchecked {
            versionId = _versions.length - 1;
        }

        emit VersionRegistered(extensionType, versionId, impl);
    }

    /// @inheritdoc IVersionedBeacon
    function setLatestVersion(
        IExtensionFactory.ExtensionType extensionType,
        uint256 versionId
    ) external onlyRole(VERSION_MANAGER_ROLE) {
        _revertIfInvalidVersionId(versionId);
        if (_versions[versionId].extensionType != extensionType) revert VersionTypeMismatch();

        _latestVersion[extensionType] = versionId;

        emit LatestVersionSet(extensionType, versionId);
    }

    /// @inheritdoc IVersionedBeacon
    function registerProxy(
        address proxy,
        IExtensionFactory.ExtensionType extensionType,
        uint256 versionId,
        address owner
    ) external {
        if (msg.sender != factory) revert NotFactory();
        if (proxy == address(0)) revert ZeroProxy();
        if (owner == address(0)) revert ZeroOwner();
        if (_proxies[proxy].registered) revert ProxyAlreadyRegistered();

        _revertIfInvalidVersionId(versionId);
        if (_versions[versionId].extensionType != extensionType) revert VersionTypeMismatch();

        _proxies[proxy] = ProxyInfo({
            extensionType: extensionType,
            owner: owner,
            pinnedVersion: versionId,
            registered: true
        });

        emit ProxyRegistered(proxy, extensionType, versionId, owner);
    }

    /// @inheritdoc IVersionedBeacon
    function pinVersion(address proxy, uint256 versionId) external {
        ProxyInfo storage info = _proxies[proxy];
        if (!info.registered) revert ProxyNotRegistered();
        if (msg.sender != info.owner) revert NotProxyOwner();

        _revertIfInvalidVersionId(versionId);
        if (_versions[versionId].extensionType != info.extensionType) revert VersionTypeMismatch();

        info.pinnedVersion = versionId;

        emit ProxyVersionSet(proxy, versionId);
    }

    /// @inheritdoc IVersionedBeacon
    function unpinVersion(address proxy) external {
        ProxyInfo storage info = _proxies[proxy];
        if (!info.registered) revert ProxyNotRegistered();
        if (msg.sender != info.owner) revert NotProxyOwner();

        info.pinnedVersion = 0;

        emit ProxyVersionSet(proxy, 0);
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
    function latestVersion(IExtensionFactory.ExtensionType extensionType) external view returns (uint256) {
        return _latestVersion[extensionType];
    }

    /// @inheritdoc IVersionedBeacon
    function getVersion(uint256 versionId) external view returns (Version memory) {
        _revertIfInvalidVersionId(versionId);
        return _versions[versionId];
    }

    /// @inheritdoc IVersionedBeacon
    function versionCount() external view returns (uint256) {
        // NOTE: Subtract 1 for the dummy at index 0.
        unchecked {
            return _versions.length - 1;
        }
    }

    /* ============ Internal View Functions ============ */

    /// @dev   Resolves the implementation address for a given proxy.
    /// @param proxy The proxy address.
    function _resolveImplementation(address proxy) internal view returns (address) {
        ProxyInfo storage info = _proxies[proxy];
        if (!info.registered) revert ProxyNotRegistered();

        uint256 versionId = info.pinnedVersion;
        if (versionId == 0) {
            versionId = _latestVersion[info.extensionType];
        }

        return _versions[versionId].implementation;
    }

    /// @dev   Reverts if the version ID is 0 or out of range.
    /// @param versionId The version ID to validate.
    function _revertIfInvalidVersionId(uint256 versionId) internal view {
        if (versionId == 0 || versionId >= _versions.length) revert InvalidVersion();
    }

    /// @dev   Reverts if the implementation address is zero or wired to wrong pyusdx/swapFacility.
    /// @param impl The implementation address to validate.
    function _revertIfInvalidImplementation(address impl) internal view {
        if (impl == address(0)) revert ZeroImplementation();

        if (IExtensionLike(impl).pyusdx() != pyusdx || IExtensionLike(impl).swapFacility() != swapFacility)
            revert InvalidImplementation();
    }
}
