// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Address } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/Address.sol";
import { ERC1967Utils } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IERC1967 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import { Proxy } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/Proxy.sol";
import { StorageSlot } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol";

import { IExtensionBeacon } from "./interfaces/IExtensionBeacon.sol";

/// @title  Extension Beacon Proxy
/// @notice Custom proxy that resolves its implementation via an ExtensionBeacon registry.
///         Stores the beacon address and extension type as immutables. All proxies of the same
///         type share the same beacon and are upgraded atomically when the beacon is updated.
/// @author M0 Labs
contract ExtensionBeaconProxy is Proxy {
    /* ============ Constants ============ */

    /// @notice ERC-1967 beacon storage slot.
    /// @dev    bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1)
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// @notice Storage location for the extension type (accessible to implementations via delegatecall).
    /// @dev    keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXExtensionType")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _EXTENSION_TYPE_STORAGE_LOCATION =
        0x50809f8892663c0bc92e8283fda4cb9143fb961da9c4bc5652b13b5c450bbc00;

    /// @notice Storage location for the pinned implementation version (0 = follow latest).
    /// @dev    keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXPinnedVersion")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _PINNED_VERSION_STORAGE_LOCATION =
        0xfec66d3fc30888a287564007fecbbfaf6a964b972d5e0e57e4d8faceddbe2b00;

    /* ============ Immutables ============ */

    /// @notice The address of the ExtensionBeacon registry.
    address public immutable beacon;

    /// @notice The extension type for this proxy instance.
    IExtensionBeacon.ExtensionType public immutable extensionType;

    /* ============ Constructor ============ */

    /// @param  beacon_        The address of the ExtensionBeacon registry.
    /// @param  extensionType_ The extension type for this proxy.
    /// @param  data           The initializer calldata to delegate to the implementation.
    constructor(address beacon_, IExtensionBeacon.ExtensionType extensionType_, bytes memory data) payable {
        if (beacon_.code.length == 0) revert ERC1967Utils.ERC1967InvalidBeacon(beacon_);

        beacon = beacon_;
        extensionType = extensionType_;

        address implementation = IExtensionBeacon(beacon_).implementation(extensionType_);
        if (implementation.code.length == 0) revert ERC1967Utils.ERC1967InvalidImplementation(implementation);

        StorageSlot.getAddressSlot(_BEACON_SLOT).value = beacon_;
        StorageSlot.getUint256Slot(_EXTENSION_TYPE_STORAGE_LOCATION).value = uint256(extensionType_);

        emit IERC1967.BeaconUpgraded(beacon_);

        if (data.length > 0) {
            Address.functionDelegateCall(implementation, data);
        }
    }

    /* ============ Internal Functions ============ */

    /// @notice Returns the current implementation address resolved from the beacon.
    /// @dev    If a version is pinned, resolves that specific version; otherwise resolves the latest.
    /// @return The address of the implementation contract.
    function _implementation() internal view virtual override returns (address) {
        uint256 pinnedVersion = StorageSlot.getUint256Slot(_PINNED_VERSION_STORAGE_LOCATION).value;

        if (pinnedVersion == 0) {
            return IExtensionBeacon(beacon).implementation(extensionType);
        }

        return IExtensionBeacon(beacon).implementation(extensionType, pinnedVersion);
    }
}
