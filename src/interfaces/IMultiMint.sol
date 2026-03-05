// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.34;

import { IYieldToOne } from "./IYieldToOne.sol";

interface IMultiMint is IYieldToOne {
    /* ============ Events ============ */

    /**
     * @notice Emitted when asset cap is set.
     * @param  asset Address of the asset.
     * @param  cap   Maximum allowed amount of `asset` that can back the extension.
     */
    event AssetCapSet(address indexed asset, uint256 cap);

    /**
     * @notice Emitted when an asset is wrapped into extension tokens.
     * @param  asset           Address of the asset deposited.
     * @param  assetAmount     Amount of asset deposited (in asset decimals).
     * @param  recipient       Address that received the extension tokens.
     * @param  extensionAmount Amount of extension tokens minted.
     */
    event AssetWrapped(address indexed asset, uint256 assetAmount, address indexed recipient, uint256 extensionAmount);

    /**
     * @notice Emitted when an asset is replaced with PYUSDX.
     * @param  asset        Address of the asset.
     * @param  assetAmount  Amount of asset replaced.
     * @param  recipient    Address that received the asset.
     * @param  pyusdxAmount Amount of PYUSDX deposited.
     */
    event AssetReplacedWithPYUSDX(
        address indexed asset,
        uint256 assetAmount,
        address indexed recipient,
        uint256 pyusdxAmount
    );

    /* ============ Custom Errors ============ */

    /// @notice Emitted in initializer if Asset Cap Manager is 0x0.
    error ZeroAssetCapManager();

    /**
     * @notice Emitted if the asset cap is reached.
     * @param  asset Address of the asset.
     */
    error AssetCapReached(address asset);

    /**
     * @notice Emitted if there is not enough of an asset to replace with PYUSDX.
     * @param  asset          Address of the asset.
     * @param  amount         Amount of asset requested.
     * @param  assetAvailable Amount of asset available.
     */
    error InsufficientAssetBacking(address asset, uint256 amount, uint256 assetAvailable);

    /**
     * @notice Emitted when wrapping an asset and receiving less than expected (fee-on-transfer).
     * @param  asset          Address of the asset.
     * @param  amountExpected Amount of asset expected.
     * @param  amountReceived Amount of asset received.
     */
    error InsufficientAssetReceived(address asset, uint256 amountExpected, uint256 amountReceived);

    /**
     * @notice Emitted if `unwrap()` is called but there is not enough PYUSDX backing.
     * @param  amount    Amount of PYUSDX to unwrap requested.
     * @param  available Amount of PYUSDX backing available.
     */
    error InsufficientPYUSDXBacking(uint256 amount, uint256 available);

    /**
     * @notice Emitted if an invalid asset is used.
     * @param  asset Address of the invalid asset.
     */
    error InvalidAsset(address asset);

    /* ============ Interactive Functions ============ */

    /**
     * @notice Mint extension tokens by depositing `asset` tokens.
     * @dev    `amount` must be formatted in the `asset` token's decimals.
     * @param  asset     Address of the asset to deposit.
     * @param  recipient Address that will receive the extension tokens.
     * @param  amount    Amount of asset tokens to deposit.
     */
    function wrap(address asset, address recipient, uint256 amount) external;

    /**
     * @notice Allows depositing PYUSDX to receive `asset` tokens from reserves.
     * @dev    `amount` MUST be formatted in PYUSDX decimals (6).
     * @param  asset     Address of the asset to receive.
     * @param  recipient Address that will receive the `asset` token.
     * @param  amount    Amount of PYUSDX to deposit (in PYUSDX decimals).
     */
    function replaceAssetWithPYUSDX(address asset, address recipient, uint256 amount) external;

    /**
     * @notice Sets the asset cap for a given `asset`.
     * @dev    MUST only be callable by an account with the ASSET_CAP_MANAGER_ROLE.
     * @param  asset Address of the asset.
     * @param  cap   Maximum allowed amount of `asset` that can back the extension.
     */
    function setAssetCap(address asset, uint256 cap) external;

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

    /// @notice Checks if an asset is allowed as backing.
    function isAllowedAsset(address asset) external view returns (bool);

    /**
     * @notice Checks if wrapping `amount` of `asset` is allowed.
     * @dev    `amount` MUST be formatted in `asset`'s decimals.
     */
    function isAllowedToWrap(address asset, uint256 amount) external view returns (bool);

    /**
     * @notice Checks if unwrapping `amount` of extension tokens is allowed.
     * @dev    `amount` MUST be formatted in extension's decimals (6).
     */
    function isAllowedToUnwrap(uint256 amount) external view returns (bool);

    /**
     * @notice Checks if replacing `asset` with PYUSDX is allowed.
     * @dev    `amount` MUST be formatted in `asset`'s decimals.
     */
    function isAllowedToReplaceAssetWithPYUSDX(address asset, uint256 amount) external view returns (bool);
}
