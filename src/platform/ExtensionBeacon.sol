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
        mapping(uint256 version => address implementation) implementations;
        uint256 latestVersion;
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
/// @notice Upgradeable registry contract for a single extension type (YieldToOne or MultiMint).
///         ERC-1967 compliant: emits `Upgraded(address)` on every registration and provides
///         a zero-arg `implementation()` returning the latest.
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
    /// @param  admin                 The address granted DEFAULT_ADMIN_ROLE.
    /// @param  beaconManager         The address granted BEACON_MANAGER_ROLE.
    /// @param  initialImplementation The initial implementation address.
    function initialize(address admin, address beaconManager, address initialImplementation) external initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (beaconManager == address(0)) revert ZeroBeaconManager();

        _validateImplementation(initialImplementation);

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BEACON_MANAGER_ROLE, beaconManager);

        _registerImplementation(initialImplementation);
    }

    /* ============ External Functions ============ */

    /// @inheritdoc IExtensionBeacon
    function registerImplementation(address implementation) external onlyRole(BEACON_MANAGER_ROLE) returns (uint256) {
        _validateImplementation(implementation);

        return _registerImplementation(implementation);
    }

    /* ============ Public View Functions ============ */

    /// @inheritdoc IExtensionBeacon
    function implementation() external view returns (address) {
        return _implementation(latestVersion());
    }

    /// @inheritdoc IExtensionBeacon
    function implementation(uint256 version) external view returns (address) {
        return _implementation(version);
    }

    /// @inheritdoc IExtensionBeacon
    function latestVersion() public view returns (uint256) {
        return _getExtensionBeaconStorage().latestVersion;
    }

    /* ============ Internal Functions ============ */

    /// @dev    Returns the implementation address for the given version.
    /// @param  version The version number.
    /// @return The address of the implementation contract.
    function _implementation(uint256 version) internal view returns (address) {
        address implementation = _getExtensionBeaconStorage().implementations[version];

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
    /// @param  implementation The address of the implementation.
    /// @return version The version number assigned.
    function _registerImplementation(address implementation) internal returns (uint256 version) {
        ExtensionBeaconStorage storage $ = _getExtensionBeaconStorage();

        version = ++$.latestVersion;
        $.implementations[version] = implementation;

        emit IERC1967.Upgraded(implementation);
        emit ImplementationRegistered(version, implementation);
    }
}
