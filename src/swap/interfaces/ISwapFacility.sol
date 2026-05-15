// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  Swap Facility interface.
/// @author M0 Labs
interface ISwapFacility {
    /* ============ Events ============ */

    /// @notice Emitted when PYUSDX Extension is swapped for another PYUSDX Extension.
    /// @param  extensionIn  The address of the input PYUSDX Extension.
    /// @param  extensionOut The address of the output PYUSDX Extension.
    /// @param  amount       The amount swapped.
    /// @param  recipient    The address to receive the output PYUSDX Extension token.
    event Swapped(address indexed extensionIn, address indexed extensionOut, uint256 amount, address indexed recipient);

    /// @notice Emitted when PYUSDX token is swapped for PYUSDX Extension.
    /// @param  token        The address of the PYUSDX token.
    /// @param  extensionOut The address of the output PYUSDX Extension.
    /// @param  amount       The amount swapped.
    /// @param  recipient    The address to receive the output PYUSDX Extension token.
    event SwappedIn(address indexed token, address indexed extensionOut, uint256 amount, address indexed recipient);

    /// @notice Emitted when PYUSDX Extension is swapped for PYUSDX token.
    /// @param  token       The address of the PYUSDX token.
    /// @param  extensionIn The address of the input PYUSDX Extension.
    /// @param  amount      The amount swapped.
    /// @param  recipient   The address to receive the PYUSDX token.
    event SwappedOut(address indexed extensionIn, address indexed token, uint256 amount, address indexed recipient);

    /// @notice Emitted when PYUSDX token is swapped for MultiMint Extension.
    /// @param  asset        The address of the asset.
    /// @param  extensionOut The address of the MultiMint Extension.
    /// @param  amount       The amount swapped.
    /// @param  recipient    The address to receive the MultiMint Extension tokens.
    event SwappedInMultiMint(
        address indexed asset,
        address indexed extensionOut,
        uint256 amount,
        address indexed recipient
    );

    /// @notice Emitted when `asset` is replaced with PYUSDX for a MultiMint Extension.
    /// @param  asset        The address of an asset.
    /// @param  extensionOut The address of a MultiMint Extension.
    /// @param  amount       The amount of PYUSDX tokens deposited to replace `asset`.
    /// @param  recipient    The address that received the `asset` tokens.
    event MultiMintAssetReplaced(
        address indexed asset,
        address indexed extensionOut,
        uint256 amount,
        address indexed recipient
    );

    /* ============ Custom Errors ============ */

    /// @notice Thrown in the constructor if the extension factory is 0x0.
    error ZeroExtensionFactory();

    /// @notice Thrown in the constructor if PYUSDX Token is 0x0.
    error ZeroPYUSDXToken();

    /// @notice Thrown in `swap` functions if an extension is not approved.
    error NotApprovedExtension(address extension);

    /// @notice Thrown in `swap` function if the provided tokens do not represent a valid swap path.
    error InvalidSwapPath(address tokenIn, address tokenOut);

    /* ============ Interactive Functions ============ */

    /// @notice Swaps between two tokens, which can be PYUSDX, PYUSDX Extensions, or an asset used by MultiMint Extensions.
    /// @param  tokenIn   The address of the token to swap from.
    /// @param  tokenOut  The address of the token to swap to.
    /// @param  amount    The amount to swap.
    /// @param  recipient The address to receive the swapped tokens.
    function swap(address tokenIn, address tokenOut, uint256 amount, address recipient) external;

    /// @notice Swaps between two tokens using permit.
    /// @param  tokenIn   The address of the token to swap from.
    /// @param  tokenOut  The address of the token to swap to.
    /// @param  amount    The amount to swap.
    /// @param  recipient The address to receive the swapped tokens.
    /// @param  deadline  The last timestamp where the signature is still valid.
    /// @param  v         An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
    /// @param  r         An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
    /// @param  s         An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
    function swapWithPermit(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Swaps between two tokens using permit.
    /// @param  tokenIn   The address of the token to swap from.
    /// @param  tokenOut  The address of the token to swap to.
    /// @param  amount    The amount to swap.
    /// @param  recipient The address to receive the swapped tokens.
    /// @param  deadline  The last timestamp where the signature is still valid.
    /// @param  signature An arbitrary signature (EIP-712).
    function swapWithPermit(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Swaps PYUSDX token to PYUSDX Extension.
    /// @param  extensionOut The address of the PYUSDX Extension to swap to.
    /// @param  amount       The amount of PYUSDX token to swap.
    /// @param  recipient    The address to receive the swapped PYUSDX Extension tokens.
    function swapIn(address extensionOut, uint256 amount, address recipient) external;

    /// @notice Swaps PYUSDX Extension to PYUSDX token.
    /// @param  extensionIn The address of the PYUSDX Extension to swap from.
    /// @param  amount      The amount of PYUSDX Extension tokens to swap.
    /// @param  recipient   The address to receive PYUSDX tokens.
    function swapOut(address extensionIn, uint256 amount, address recipient) external;

    /// @notice Replaces `asset` held in a MultiMint Extension with `amount` of PYUSDX.
    /// @param  asset        The address of the asset.
    /// @param  tokenIn      The address of PYUSDX or a PYUSDX extension to provide PYUSDX from.
    /// @param  extensionOut The address of a MultiMint Extension.
    /// @param  amount       The amount of PYUSDX to replace.
    /// @param  recipient    The address to receive `asset` tokens equivalent to `amount` of PYUSDX.
    function replaceAsset(
        address asset,
        address tokenIn,
        address extensionOut,
        uint256 amount,
        address recipient
    ) external;

    /// @notice Replaces `asset` held in a MultiMint Extension with `amount` of PYUSDX using permit.
    /// @param  asset        The address of the asset.
    /// @param  tokenIn      The address of PYUSDX or a PYUSDX extension to provide PYUSDX from.
    /// @param  extensionOut The address of a MultiMint Extension.
    /// @param  amount       The amount of PYUSDX to replace.
    /// @param  recipient    The address to receive `asset` tokens equivalent to `amount` of PYUSDX.
    /// @param  deadline     The last timestamp where the signature is still valid.
    /// @param  v            An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
    /// @param  r            An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
    /// @param  s            An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
    function replaceAssetWithPermit(
        address asset,
        address tokenIn,
        address extensionOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Replaces `asset` held in a MultiMint Extension with `amount` of PYUSDX using permit.
    /// @param  asset        The address of the asset.
    /// @param  tokenIn      The address of PYUSDX or a PYUSDX extension to provide PYUSDX from.
    /// @param  extensionOut The address of a MultiMint Extension.
    /// @param  amount       The amount of PYUSDX to replace.
    /// @param  recipient    The address to receive `asset` tokens equivalent to `amount` of PYUSDX.
    /// @param  deadline     The last timestamp where the signature is still valid.
    /// @param  signature    An arbitrary signature (EIP-712).
    function replaceAssetWithPermit(
        address asset,
        address tokenIn,
        address extensionOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The address of the PYUSDX Token contract.
    function pyusdx() external view returns (address);

    /// @notice The address of the PYUSDX Extension Factory contract.
    function extensionFactory() external view returns (address);

    /// @notice Returns the address that called `swap`.
    /// @dev    Must be used instead of `msg.sender` in PYUSDX Extensions contracts to get the original sender.
    function msgSender() external view returns (address);

    /// @notice Checks if the extension is approved.
    /// @param  extension The extension address to check.
    /// @return True if approved, false otherwise.
    function isApprovedExtension(address extension) external view returns (bool);
}
