// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { IERC1967 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";

import { IExtension } from "./interfaces/IExtension.sol";
import { IExtensionBeacon } from "./interfaces/IExtensionBeacon.sol";
import { ISwapFacility } from "../swap/interfaces/ISwapFacility.sol";

/// @notice ERC-7201 namespaced storage layout for ExtensionBeacon.
abstract contract ExtensionBeaconStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDXExtensionBeacon
    struct ExtensionBeaconStorage {
        mapping(IExtensionBeacon.ExtensionType extensionType => mapping(uint256 version => address implementation)) implementations;
        mapping(IExtensionBeacon.ExtensionType extensionType => uint256 latestVersion) latestVersions;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXExtensionBeacon")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _EXTENSION_BEACON_STORAGE_LOCATION =
        0xea0c2eec9f3cb72c51d142ff5c076f11b507be969141547f15f83f9b92f55900;

    function _getExtensionBeaconStorage() internal pure returns (ExtensionBeaconStorage storage $) {
        bytes32 location = _EXTENSION_BEACON_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }
}

/// @title  Extension Beacon
/// @notice Upgradeable registry contract mapping ExtensionType to versioned implementations.
///         Serves as the single source of truth for implementation resolution by ExtensionBeaconProxy.
/// @author M0 Labs
contract ExtensionBeacon is IExtensionBeacon, AccessControlUpgradeable, ExtensionBeaconStorageLayout {
    /* ============ Variables ============ */

    /// @inheritdoc IExtensionBeacon
    bytes32 public constant BEACON_MANAGER_ROLE = keccak256("BEACON_MANAGER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionBeacon
    address public immutable pyusdx;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionBeacon
    address public immutable swapFacility;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Constructs ExtensionBeacon implementation contract.
    /// @dev    Sets immutable storage and validates wiring.
    /// @param  pyusdx_       The address of the PYUSDX token.
    /// @param  swapFacility_ The address of the SwapFacility contract.
    constructor(address pyusdx_, address swapFacility_) {
        _disableInitializers();

        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDX();
        if ((swapFacility = swapFacility_) == address(0)) revert ZeroSwapFacility();
        if (pyusdx != ISwapFacility(swapFacility).pyusdx()) revert PYUSDXMismatch();
    }

    /* ============ Initializer ============ */

    /// @notice Initializes the ExtensionBeacon proxy.
    /// @param  admin                    The address granted DEFAULT_ADMIN_ROLE.
    /// @param  beaconManager            The address granted BEACON_MANAGER_ROLE.
    /// @param  yieldToOneImplementation The initial YieldToOne implementation address.
    /// @param  multiMintImplementation  The initial MultiMint implementation address.
    function initialize(
        address admin,
        address beaconManager,
        address yieldToOneImplementation,
        address multiMintImplementation
    ) external initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (beaconManager == address(0)) revert ZeroBeaconManager();

        _validateImplementation(yieldToOneImplementation);
        _validateImplementation(multiMintImplementation);

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BEACON_MANAGER_ROLE, beaconManager);

        _registerImplementation(IExtensionBeacon.ExtensionType.YIELD_TO_ONE, yieldToOneImplementation);
        _registerImplementation(IExtensionBeacon.ExtensionType.MULTI_MINT, multiMintImplementation);
    }

    /* ============ External Functions ============ */

    /// @inheritdoc IExtensionBeacon
    function registerImplementation(
        IExtensionBeacon.ExtensionType extensionType,
        address implementation
    ) external onlyRole(BEACON_MANAGER_ROLE) returns (uint256) {
        if (extensionType == IExtensionBeacon.ExtensionType.NONE) revert InvalidExtensionType();

        _validateImplementation(implementation);

        return _registerImplementation(extensionType, implementation);
    }

    /* ============ Public View Functions ============ */

    /// @inheritdoc IExtensionBeacon
    function implementation(IExtensionBeacon.ExtensionType extensionType) external view returns (address) {
        return _implementation(extensionType, latestVersion(extensionType));
    }

    /// @inheritdoc IExtensionBeacon
    function implementation(
        IExtensionBeacon.ExtensionType extensionType,
        uint256 version
    ) external view returns (address) {
        return _implementation(extensionType, version);
    }

    /// @inheritdoc IExtensionBeacon
    function latestVersion(IExtensionBeacon.ExtensionType extensionType) public view returns (uint256) {
        return _getExtensionBeaconStorage().latestVersions[extensionType];
    }

    /* ============ Internal Functions ============ */

    /// @dev    Returns the implementation address for the given extension type and version.
    /// @param  extensionType  The type of extension.
    /// @param  version        The version number.
    /// @return                The address of the implementation contract.
    function _implementation(
        IExtensionBeacon.ExtensionType extensionType,
        uint256 version
    ) internal view returns (address) {
        address implementation = _getExtensionBeaconStorage().implementations[extensionType][version];

        if (implementation == address(0)) revert NoImplementationRegistered();

        return implementation;
    }

    /// @dev    Validates that the implementation is a non-zero contract with correct pyusdx/swapFacility wiring.
    /// @param  implementation The implementation address to validate.
    function _validateImplementation(address implementation) internal view {
        if (implementation == address(0)) revert ZeroImplementation();

        if (
            IExtension(implementation).pyusdx() != pyusdx || IExtension(implementation).swapFacility() != swapFacility
        ) {
            revert InvalidExtension();
        }
    }

    /// @dev    Registers an implementation, auto-incrementing the version.
    /// @param  extensionType  The type of extension.
    /// @param  implementation The address of the implementation.
    /// @return version        The version number assigned.
    function _registerImplementation(
        IExtensionBeacon.ExtensionType extensionType,
        address implementation
    ) internal returns (uint256 version) {
        ExtensionBeaconStorage storage $ = _getExtensionBeaconStorage();

        version = ++$.latestVersions[extensionType];
        $.implementations[extensionType][version] = implementation;

        emit IERC1967.Upgraded(implementation);
        emit ImplementationRegistered(extensionType, version, implementation);
    }
}
