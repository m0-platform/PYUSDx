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

        emit IERC1967.BeaconUpgraded(beacon_);

        if (data.length > 0) {
            Address.functionDelegateCall(implementation, data);
        }
    }

    /* ============ Internal Functions ============ */

    /// @notice Returns the current implementation address resolved from the beacon.
    /// @dev    Calls the beacon's implementation getter with the stored extension type.
    /// @return The address of the implementation contract.
    function _implementation() internal view virtual override returns (address) {
        return IExtensionBeacon(beacon).implementation(extensionType);
    }
}
