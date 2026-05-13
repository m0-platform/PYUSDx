// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { IYieldToOne } from "./IYieldToOne.sol";

interface IMultiMint is IYieldToOne {
    /* ============ Events ============ */

    /// @notice Emitted when asset cap is set.
    /// @param  asset Address of the asset.
    /// @param  cap   Maximum allowed amount of `asset` that can back the extension.
    event AssetCapSet(address indexed asset, uint256 cap);

    /// @notice Emitted when a caller's allow status on the replaceAsset whitelist changes.
    /// @param  caller  The caller whose allow status changed.
    /// @param  allowed The new allow status (true = whitelisted, false = removed).
    event ReplaceAssetWhitelistCallerSet(address indexed caller, bool indexed allowed);

    /// @notice Emitted when an asset is wrapped into extension tokens.
    /// @param  asset           Address of the asset deposited.
    /// @param  assetAmount     Amount of asset deposited (in asset decimals).
    /// @param  recipient       Address that received the extension tokens.
    /// @param  extensionAmount Amount of extension tokens minted.
    event AssetWrapped(address indexed asset, uint256 assetAmount, address indexed recipient, uint256 extensionAmount);

    /// @notice Emitted when an asset is replaced with PYUSDX.
    /// @param  asset        Address of the asset.
    /// @param  assetAmount  Amount of asset replaced.
    /// @param  recipient    Address that received the asset.
    /// @param  pyusdxAmount Amount of PYUSDX deposited.
    event AssetReplaced(address indexed asset, uint256 assetAmount, address indexed recipient, uint256 pyusdxAmount);

    /* ============ Custom Errors ============ */

    /// @notice Emitted in initializer if Asset Cap Manager is 0x0.
    error ZeroAssetCapManager();

    /// @notice Reverts when batch input arrays have differing lengths.
    error ArrayLengthMismatch();

    /// @notice Emitted if the asset cap is reached.
    /// @param  asset Address of the asset.
    error AssetCapReached(address asset);

    /// @notice Emitted if there is not enough of an asset to replace with PYUSDX.
    /// @param  asset          Address of the asset.
    /// @param  amount         Amount of asset requested.
    /// @param  assetAvailable Amount of asset available.
    error InsufficientAssetBacking(address asset, uint256 amount, uint256 assetAvailable);

    /// @notice Emitted when wrapping an asset and receiving less than expected (fee-on-transfer).
    /// @param  asset          Address of the asset.
    /// @param  amountExpected Amount of asset expected.
    /// @param  amountReceived Amount of asset received.
    error InsufficientAssetReceived(address asset, uint256 amountExpected, uint256 amountReceived);

    /// @notice Emitted if `unwrap()` is called but there is not enough PYUSDX backing.
    /// @param  amount    Amount of PYUSDX to unwrap requested.
    /// @param  available Amount of PYUSDX backing available.
    error InsufficientPYUSDXBacking(uint256 amount, uint256 available);

    /// @notice Emitted if an invalid asset is used.
    /// @param  asset Address of the invalid asset.
    error InvalidAsset(address asset);

    /// @notice Emitted if `asset` has cap == 0 (unregistered or disabled).
    /// @param  asset Address of the disallowed asset.
    error AssetNotAllowed(address asset);

    /// @notice Reverts when the caller is not permitted to perform the operation.
    /// @param  caller The address that attempted the call.
    error CallerNotAllowed(address caller);

    /* ============ Interactive Functions ============ */

    /// @notice Mint extension tokens by depositing `asset` tokens.
    /// @dev    `amount` must be formatted in the `asset` token's decimals.
    /// @param  asset     Address of the asset to deposit.
    /// @param  recipient Address that will receive the extension tokens.
    /// @param  amount    Amount of asset tokens to deposit.
    function wrap(address asset, address recipient, uint256 amount) external;

    /// @notice Allows depositing PYUSDX to receive `asset` tokens from reserves.
    /// @dev    `amount` MUST be formatted in PYUSDX decimals (6).
    /// @param  asset     Address of the asset to receive.
    /// @param  recipient Address that will receive the `asset` token.
    /// @param  amount    Amount of PYUSDX to deposit (in PYUSDX decimals).
    function replaceAsset(address asset, address recipient, uint256 amount) external;

    /// @notice Sets the asset cap for a given `asset`.
    /// @dev    MUST only be callable by an account with the ASSET_CAP_MANAGER_ROLE.
    ///         Setting `cap` to 0 disables both `wrap` and `replaceAsset` for this asset;
    ///         existing balances remain unwrappable to PYUSDX.
    /// @param  asset Address of the asset.
    /// @param  cap   Maximum allowed amount of `asset` that can back the extension.
    function setAssetCap(address asset, uint256 cap) external;

    /// @notice Sets `caller`'s allow status on the replaceAsset whitelist.
    /// @dev    MUST only be callable by ASSET_CAP_MANAGER_ROLE.
    ///         No-op (no event) if the caller is already in the requested state.
    /// @param  caller  The caller to add or remove.
    /// @param  allowed True to add, false to remove.
    function setReplaceAssetWhitelistCaller(address caller, bool allowed) external;

    /// @notice Batch variant of setReplaceAssetWhitelistCaller.
    /// @dev    MUST only be callable by ASSET_CAP_MANAGER_ROLE.
    ///         Reverts on array length mismatch.
    /// @param  callers The callers to add or remove.
    /// @param  allowed The corresponding allow statuses.
    function setReplaceAssetWhitelistCaller(address[] calldata callers, bool[] calldata allowed) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can set the assets cap.
    function ASSET_CAP_MANAGER_ROLE() external view returns (bytes32);

    /// @notice Number of decimals used by PYUSDX.
    function PYUSDX_DECIMALS() external view returns (uint8);

    /// @notice Gets the cached balance of a given asset held by the extension.
    function assetBalanceOf(address asset) external view returns (uint256);

    /// @notice Gets the asset cap for a given asset.
    function assetCap(address asset) external view returns (uint256);

    /// @notice Gets the cached decimals of a given asset.
    function assetDecimals(address asset) external view returns (uint8);

    /// @notice Gets the total non-PYUSDX assets held by the extension (in extension decimals).
    function totalAssets() external view returns (uint256);

    /// @notice Get the addresses allowed to call `replaceAsset`.
    function getReplaceAssetWhitelist() external view returns (address[] memory);

    /// @notice Checks if an asset is allowed as backing.
    function isAllowedAsset(address asset) external view returns (bool);

    /// @notice Checks if wrapping `amount` of `asset` is allowed.
    /// @dev    `amount` MUST be formatted in `asset`'s decimals.
    function isAllowedToWrap(address asset, uint256 amount) external view returns (bool);

    /// @notice Checks if unwrapping `amount` of extension tokens is allowed.
    /// @dev    `amount` MUST be formatted in extension's decimals (6).
    function isAllowedToUnwrap(uint256 amount) external view returns (bool);

    /// @notice Checks if `caller` is allowed to replace `asset` with `amount` of PYUSDX.
    /// @dev    `amount` MUST be formatted in PYUSDX decimals.
    /// @param  caller The address of the caller to check.
    /// @param  asset  The address of the asset to replace.
    /// @param  amount The amount of PYUSDX to deposit.
    function isAllowedToReplaceAsset(address caller, address asset, uint256 amount) external view returns (bool);

    /// @notice Whether the replaceAsset whitelist is currently enforced.
    function isReplaceAssetWhitelistEnabled() external view returns (bool);
}
