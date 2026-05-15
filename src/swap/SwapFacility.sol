// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Extended } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20Extended.sol";
import { Pausable } from "../../lib/evm-m-extensions/src/components/pausable/Pausable.sol";

import { ReentrancyLock } from "./ReentrancyLock.sol";

import { IMultiMint } from "../platform/projects/interfaces/IMultiMint.sol";
import { IExtension } from "../platform/interfaces/IExtension.sol";
import { IExtensionFactory } from "../platform/interfaces/IExtensionFactory.sol";

import { ISwapFacility } from "./interfaces/ISwapFacility.sol";

/// @title  Swap Facility
/// @notice A contract responsible for swapping between PYUSDX Extensions.
/// @author M0 Labs
contract SwapFacility is ISwapFacility, Pausable, ReentrancyLock {
    using SafeERC20 for IERC20;

    /// @inheritdoc ISwapFacility
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable pyusdx;

    /// @inheritdoc ISwapFacility
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable extensionFactory;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Constructs SwapFacility Implementation contract
    /// @dev    Sets immutable storage.
    /// @param  pyusdx_           The address of PYUSDX token.
    /// @param  extensionFactory_ The address of the PYUSDX Extension Factory.
    constructor(address pyusdx_, address extensionFactory_) {
        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDXToken();
        if ((extensionFactory = extensionFactory_) == address(0)) revert ZeroExtensionFactory();

        _disableInitializers();
    }

    /* ============ Initializer ============ */

    /// @notice Initializes SwapFacility Proxy.
    /// @dev    Used to initialize SwapFacility when deploying for the first time.
    /// @param  admin  Address of the SwapFacility admin.
    /// @param  pauser Address of the SwapFacility pauser.
    function initialize(address admin, address pauser) external initializer {
        __AccessControl_init();
        __ReentrancyLock_init(admin);
        __Pausable_init(pauser);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc ISwapFacility
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address recipient
    ) external isNotLocked whenNotPaused {
        _swap(tokenIn, tokenOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapWithPermit(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external isNotLocked whenNotPaused {
        try IExtension(tokenIn).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        _swap(tokenIn, tokenOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapWithPermit(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata signature
    ) external isNotLocked whenNotPaused {
        try IExtension(tokenIn).permit(msg.sender, address(this), amount, deadline, signature) {} catch {}
        _swap(tokenIn, tokenOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapIn(address extensionOut, uint256 amount, address recipient) external isNotLocked whenNotPaused {
        _swap(pyusdx, extensionOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapOut(address extensionIn, uint256 amount, address recipient) external isNotLocked whenNotPaused {
        _swap(extensionIn, pyusdx, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function replaceAsset(
        address asset,
        address tokenIn,
        address extensionOut,
        uint256 amount,
        address recipient
    ) external isNotLocked whenNotPaused {
        _replaceAsset(asset, tokenIn, extensionOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
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
    ) external isNotLocked whenNotPaused {
        try IERC20Extended(tokenIn).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        _replaceAsset(asset, tokenIn, extensionOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function replaceAssetWithPermit(
        address asset,
        address tokenIn,
        address extensionOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata signature
    ) external isNotLocked whenNotPaused {
        try IERC20Extended(tokenIn).permit(msg.sender, address(this), amount, deadline, signature) {} catch {}
        _replaceAsset(asset, tokenIn, extensionOut, amount, recipient);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc ISwapFacility
    function isApprovedExtension(address extension) public view returns (bool) {
        return IExtensionFactory(extensionFactory).isApprovedExtension(extension);
    }

    /// @inheritdoc ISwapFacility
    function msgSender() public view returns (address) {
        return _getLocker();
    }

    /* ============ Internal Interactive Functions ============ */

    /// @notice Swaps between two tokens, which can be PYUSDX token, PYUSDX Extensions, or an external asset used by MultiMint Extensions.
    /// @param  tokenIn   The address of the token to swap from.
    /// @param  tokenOut  The address of the token to swap to.
    /// @param  amount    The amount to swap.
    /// @param  recipient The address to receive the swapped tokens.
    function _swap(address tokenIn, address tokenOut, uint256 amount, address recipient) internal {
        // Prevent self-swaps (e.g., PYUSDX -> PYUSDX or extension -> same extension)
        if (tokenIn == tokenOut) revert InvalidSwapPath(tokenIn, tokenOut);

        // If the input token is PYUSDX, we swap it for the output token, which must be an approved extension
        // This is checked in _swapIn
        if (tokenIn == pyusdx) return _swapIn(tokenOut, amount, recipient);

        // If the output token is PYUSDX, we swap the input token, which must be an approved extension, for PYUSDX
        // This is checked in _swapOut
        if (tokenOut == pyusdx) return _swapOut(tokenIn, amount, recipient);

        // If both tokens are extensions, we swap one extension for another
        bool isTokenOutApproved = isApprovedExtension(tokenOut);
        if (isApprovedExtension(tokenIn) && isTokenOutApproved)
            return _swapExtensions(tokenIn, tokenOut, amount, recipient);

        // If tokenOut is an extension but tokenIn is an external asset, route through MultiMint
        if (isTokenOutApproved) return _swapInMultiMint(tokenIn, tokenOut, amount, recipient);

        // If none of the above, we revert
        revert InvalidSwapPath(tokenIn, tokenOut);
    }

    /// @notice Swaps one PYUSDX Extension to another.
    /// @param  extensionIn  The address of the PYUSDX Extension to swap from.
    /// @param  extensionOut The address of the PYUSDX Extension to swap to.
    /// @param  amount       The amount to swap.
    /// @param  recipient    The address to receive the swapped PYUSDX Extension tokens.
    function _swapExtensions(address extensionIn, address extensionOut, uint256 amount, address recipient) internal {
        uint256 pyusdxBalanceBefore = _pyusdxBalanceOf(address(this));

        IERC20(extensionIn).transferFrom(msg.sender, address(this), amount);
        IExtension(extensionIn).unwrap(amount);

        // NOTE: Ensures that we wrap the equivalent amount of PYUSDX received from unwrapping.
        amount = _pyusdxBalanceOf(address(this)) - pyusdxBalanceBefore;

        IERC20(pyusdx).approve(extensionOut, amount);
        IExtension(extensionOut).wrap(recipient, amount);

        emit Swapped(extensionIn, extensionOut, amount, recipient);
    }

    /// @notice Swaps PYUSDX token to PYUSDX Extension.
    /// @param  extensionOut The address of the PYUSDX Extension to swap to.
    /// @param  amount       The amount of PYUSDX token to swap.
    /// @param  recipient    The address to receive the swapped PYUSDX Extension tokens.
    function _swapIn(address extensionOut, uint256 amount, address recipient) internal {
        _revertIfNotApprovedExtension(extensionOut);

        IERC20(pyusdx).transferFrom(msg.sender, address(this), amount);
        IERC20(pyusdx).approve(extensionOut, amount);
        IExtension(extensionOut).wrap(recipient, amount);

        emit SwappedIn(pyusdx, extensionOut, amount, recipient);
    }

    /// @notice Swaps PYUSDX Extension to PYUSDX token.
    /// @param  extensionIn The address of the PYUSDX Extension to swap from.
    /// @param  amount      The amount of PYUSDX Extension tokens to swap.
    /// @param  recipient   The address to receive PYUSDX tokens.
    function _swapOut(address extensionIn, uint256 amount, address recipient) internal {
        _revertIfNotApprovedExtension(extensionIn);

        IERC20(extensionIn).transferFrom(msg.sender, address(this), amount);

        uint256 pyusdxBalanceBefore = _pyusdxBalanceOf(address(this));

        // NOTE: Amount and recipient validation is performed in Extensions.
        IExtension(extensionIn).unwrap(amount);

        // NOTE: Ensures that we transfer to recipient the equivalent amount of PYUSDX received from unwrapping.
        amount = _pyusdxBalanceOf(address(this)) - pyusdxBalanceBefore;

        IERC20(pyusdx).transfer(recipient, amount);

        emit SwappedOut(extensionIn, pyusdx, amount, recipient);
    }

    /// @notice Swaps `amount` of `asset` to MultiMint Extension tokens.
    /// @param  asset        The address of the asset to swap.
    /// @param  extensionOut The address of the MultiMint Extension to swap to.
    /// @param  amount       The amount of `asset` to swap.
    /// @param  recipient    The address to receive MultiMint Extension tokens equivalent to `amount` of `asset`.
    function _swapInMultiMint(address asset, address extensionOut, uint256 amount, address recipient) internal {
        _revertIfCannotMultiMint(asset, extensionOut);

        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));

        // NOTE: Use safeTransferFrom and forceApprove to handle assets that do not return a boolean value.
        // NOTE: Fee-on-transfer tokens are not supported. The full `amount` must be received by the contract.
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).forceApprove(extensionOut, amount);
        IMultiMint(extensionOut).wrap(asset, recipient, amount);

        // NOTE: Refund any dust the extension left behind to the caller.
        uint256 leftover = IERC20(asset).balanceOf(address(this)) - balanceBefore;

        if (leftover != 0) {
            // NOTE: Clear the residual allowance scoped to this swap.
            IERC20(asset).forceApprove(extensionOut, 0);
            IERC20(asset).safeTransfer(msg.sender, leftover);
        }

        emit SwappedInMultiMint(asset, extensionOut, amount - leftover, recipient);
    }

    /// @notice Replaces `asset` held in a MultiMint Extension with `amount` of PYUSDX.
    /// @param  asset        The address of the asset.
    /// @param  tokenIn      The address of PYUSDX or a PYUSDX extension to provide PYUSDX from.
    /// @param  extensionOut The address of a MultiMint Extension.
    /// @param  amount       The amount of PYUSDX to replace.
    /// @param  recipient    The address to receive `asset` tokens equivalent to `amount` of PYUSDX.
    function _replaceAsset(
        address asset,
        address tokenIn,
        address extensionOut,
        uint256 amount,
        address recipient
    ) internal {
        // NOTE: `tokenIn` can be PYUSDX or an approved extension
        if (tokenIn != pyusdx) {
            _revertIfNotApprovedExtension(tokenIn);
        }

        _revertIfNotApprovedExtension(extensionOut);

        uint256 pyusdxBalanceBefore = _pyusdxBalanceOf(address(this));

        if (tokenIn == pyusdx) {
            // NOTE: Direct PYUSDX transfer - no unwrap needed
            IERC20(pyusdx).transferFrom(msg.sender, address(this), amount);
        } else {
            // NOTE: Extension tokens - unwrap to get PYUSDX
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);
            IExtension(tokenIn).unwrap(amount);
        }

        // NOTE: Ensures that we replace asset by the equivalent amount of PYUSDX received.
        amount = _pyusdxBalanceOf(address(this)) - pyusdxBalanceBefore;

        IERC20(pyusdx).approve(extensionOut, amount);
        IMultiMint(extensionOut).replaceAsset(asset, recipient, amount);

        emit MultiMintAssetReplaced(asset, extensionOut, amount, recipient);
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev    Returns the PYUSDX Token balance of `account`.
    /// @param  account The account being queried.
    /// @return balance The PYUSDX Token balance of the account.
    function _pyusdxBalanceOf(address account) internal view returns (uint256) {
        return IERC20(pyusdx).balanceOf(account);
    }

    /// @dev   Reverts if `extension` is not an approved earner or an admin-approved extension.
    /// @param extension Address of an extension.
    function _revertIfNotApprovedExtension(address extension) internal view {
        if (!isApprovedExtension(extension)) revert NotApprovedExtension(extension);
    }

    /// @dev   Reverts if `asset` is not an allowed asset in MultiMint Extension.
    /// @param asset        Address of the asset to check.
    /// @param extensionOut Address of the MultiMint Extension.
    function _revertIfCannotMultiMint(address asset, address extensionOut) internal view {
        try IMultiMint(extensionOut).isAllowedAsset(asset) returns (bool allowed) {
            if (!allowed) revert InvalidSwapPath(asset, extensionOut);
        } catch {
            revert InvalidSwapPath(asset, extensionOut);
        }
    }
}
