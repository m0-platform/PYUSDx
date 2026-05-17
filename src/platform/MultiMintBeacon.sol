// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IMultiMintBeacon } from "./interfaces/IMultiMintBeacon.sol";

import { ExtensionBeacon } from "./ExtensionBeacon.sol";

/// @notice ERC-7201 namespaced storage layout for MultiMintBeacon.
abstract contract MultiMintBeaconStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDXMultiMintBeacon
    struct MultiMintBeaconStorage {
        mapping(address asset => bool allowed) assetWhitelist;
    }

    // keccak256(abi.encode(uint256(keccak256("PYUSDX.storage.MultiMintBeacon")) - 0)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _MULTI_MINT_BEACON_STORAGE_LOCATION =
        0xd8951743b745a9a83ad0569967dfddec53decfda146131087d06af86bf06e800;

    function _getMultiMintBeaconStorage() internal pure returns (MultiMintBeaconStorage storage $) {
        bytes32 location = _MULTI_MINT_BEACON_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }
}

/// @title  MultiMint Beacon
/// @notice An ExtensionBeacon specialized for MultiMint extensions. It adds a global
///         asset whitelist: a collateral asset can only be enabled in any MultiMint
///         extension if it has first been whitelisted here by the beacon manager.
/// @author M0 Labs
contract MultiMintBeacon is IMultiMintBeacon, MultiMintBeaconStorageLayout, ExtensionBeacon {
    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Constructs MultiMintBeacon implementation contract.
    /// @param  pyusdx_       The address of the PYUSDX token.
    /// @param  swapFacility_ The address of the SwapFacility contract.
    constructor(address pyusdx_, address swapFacility_) ExtensionBeacon(pyusdx_, swapFacility_) {}

    /* ============ External Functions ============ */

    /// @inheritdoc IMultiMintBeacon
    function setAssetWhitelist(address asset, bool allowed) external onlyRole(BEACON_MANAGER_ROLE) {
        _setAssetWhitelist(asset, allowed);
    }

    /// @inheritdoc IMultiMintBeacon
    function setAssetWhitelist(
        address[] calldata assets,
        bool[] calldata allowed
    ) external onlyRole(BEACON_MANAGER_ROLE) {
        if (assets.length != allowed.length) revert ArrayLengthMismatch();

        for (uint256 i; i < assets.length; ++i) {
            _setAssetWhitelist(assets[i], allowed[i]);
        }
    }

    /* ============ Public View Functions ============ */

    /// @inheritdoc IMultiMintBeacon
    function isAssetWhitelisted(address asset) external view returns (bool) {
        return _getMultiMintBeaconStorage().assetWhitelist[asset];
    }

    /* ============ Internal Functions ============ */

    /// @dev   Sets the whitelist status of `asset`, emitting `AssetWhitelistSet` only on change.
    /// @param asset   The address of the asset.
    /// @param allowed The new whitelist status.
    function _setAssetWhitelist(address asset, bool allowed) internal {
        if (asset == address(0)) revert ZeroAsset();

        MultiMintBeaconStorage storage $ = _getMultiMintBeaconStorage();

        if ($.assetWhitelist[asset] == allowed) return;

        $.assetWhitelist[asset] = allowed;

        emit AssetWhitelistSet(asset, allowed);
    }
}
