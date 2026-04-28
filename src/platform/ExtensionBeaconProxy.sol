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
///         Supports two modes: beacon mode (follows latest) and pinned mode (frozen to a
///         specific implementation). Fully ERC-1967 compliant.
/// @author M0 Labs
contract ExtensionBeaconProxy is Proxy {
    /* ============ Constants ============ */

    /// @notice ERC-1967 beacon storage slot.
    /// @dev    bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1)
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// @notice ERC-1967 implementation storage slot (used for pinned mode).
    /// @dev    bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Storage location for the origin beacon address (written at construction, never modified).
    /// @dev    keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXOriginBeacon")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ORIGIN_BEACON_SLOT = 0x0db096ce50da19b63b97b47df5b0c87e2ed1677b3d801ad424e1bbfc0bb0c300;

    /* ============ Constructor ============ */

    /// @param  beacon_ The address of the ExtensionBeacon registry.
    /// @param  data    The initializer calldata to delegate to the implementation.
    constructor(address beacon_, bytes memory data) payable {
        if (beacon_.code.length == 0) revert ERC1967Utils.ERC1967InvalidBeacon(beacon_);

        address implementation = IExtensionBeacon(beacon_).implementation();
        if (implementation.code.length == 0) revert ERC1967Utils.ERC1967InvalidImplementation(implementation);

        StorageSlot.getAddressSlot(_BEACON_SLOT).value = beacon_;
        StorageSlot.getAddressSlot(_ORIGIN_BEACON_SLOT).value = beacon_;

        emit IERC1967.BeaconUpgraded(beacon_);

        if (data.length > 0) {
            Address.functionDelegateCall(implementation, data);
        }
    }

    /* ============ Internal Functions ============ */

    /// @notice Returns the current implementation address.
    /// @dev    If pinned (non-zero _IMPLEMENTATION_SLOT), returns the pinned implementation.
    ///         Otherwise reads the beacon from _BEACON_SLOT and queries its latest implementation.
    /// @return The address of the implementation contract.
    function _implementation() internal view virtual override returns (address) {
        address implementation = StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
        if (implementation != address(0)) return implementation;

        address beacon = StorageSlot.getAddressSlot(_BEACON_SLOT).value;
        return IExtensionBeacon(beacon).implementation();
    }
}
