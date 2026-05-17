// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { IExtensionBeacon } from "./IExtensionBeacon.sol";

/// @title  PYUSDX MultiMint Beacon interface.
/// @notice Extends the extension beacon with a global asset whitelist that gates
///         which collateral assets any MultiMint extension is allowed to enable.
/// @author M0 Labs
interface IMultiMintBeacon is IExtensionBeacon {
    /* ============ Events ============ */

    /// @notice Emitted when the global whitelist status of an asset changes.
    /// @param  asset   The address of the asset.
    /// @param  allowed The new whitelist status.
    event AssetWhitelistSet(address indexed asset, bool indexed allowed);

    /* ============ Errors ============ */

    /// @notice Thrown if the asset address is 0x0.
    error ZeroAsset();

    /// @notice Thrown if the input array lengths do not match.
    error ArrayLengthMismatch();

    /* ============ Interactive Functions ============ */

    /// @notice Sets the global whitelist status of `asset`.
    /// @dev    MUST only be callable by an address with the `BEACON_MANAGER_ROLE` role.
    /// @param  asset   The address of the asset.
    /// @param  allowed True to whitelist the asset, false to remove it.
    function setAssetWhitelist(address asset, bool allowed) external;

    /// @notice Sets the global whitelist status of multiple assets.
    /// @dev    MUST only be callable by an address with the `BEACON_MANAGER_ROLE` role.
    /// @param  assets  The addresses of the assets.
    /// @param  allowed The new whitelist status for each asset.
    function setAssetWhitelist(address[] calldata assets, bool[] calldata allowed) external;

    /* ============ View/Pure Functions ============ */

    /// @notice Returns whether `asset` is globally whitelisted as MultiMint collateral.
    /// @param  asset The address of the asset.
    /// @return True if the asset is whitelisted.
    function isAssetWhitelisted(address asset) external view returns (bool);
}
