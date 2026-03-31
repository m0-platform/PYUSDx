// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IVersionedBeacon } from "../interfaces/IVersionedBeacon.sol";
import { IYieldToOne } from "./interfaces/IYieldToOne.sol";

import { MultiMint } from "./MultiMint.sol";
import { YieldToOne } from "./YieldToOne.sol";

/// @title  PausedMultiMint
/// @notice Read-only implementation of MultiMint used when a version is paused at the beacon level.
///         All view functions work (balanceOf, totalSupply, yield, assetBalanceOf, assetCap, etc.)
///         because they read from the same ERC-7201 storage slots via delegatecall. All state-changing
///         functions revert with `ExtensionPaused()`.
/// @author M0 Labs
contract PausedMultiMint is MultiMint {
    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param pyusdx_       The address of the PYUSDX token.
    /// @param swapFacility_ The address of the swap facility.
    constructor(address pyusdx_, address swapFacility_) MultiMint(pyusdx_, swapFacility_) {}

    /* ============ Interactive Functions ============ */

    /// @dev Reverts — cannot initialize via paused implementation.
    function initialize(
        string memory,
        string memory,
        address,
        address,
        address,
        address,
        address,
        address
    ) public pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /// @dev Reverts — yield recipient changes are blocked while paused.
    function setYieldRecipient(address) external pure override(IYieldToOne, YieldToOne) {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /// @dev Reverts — asset cap changes are blocked while paused.
    function setAssetCap(address, uint256) external pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /* ============ Internal Hook Overrides ============ */

    /// @dev Reverts on all PYUSDX wrap attempts (3-arg from YieldToOne).
    function _beforeWrap(address, address, uint256) internal pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /// @dev Reverts on all asset wrap attempts (4-arg from MultiMint).
    function _beforeWrap(address, address, address, uint256) internal pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /// @dev Reverts on all unwrap attempts.
    function _beforeUnwrap(address, uint256) internal pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /// @dev Reverts on all transfer attempts.
    function _beforeTransfer(address, address, uint256) internal pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /// @dev Reverts on all approval attempts.
    function _beforeApprove(address, address, uint256) internal pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /// @dev Reverts on all yield claim attempts.
    function _beforeClaimYield() internal pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }

    /// @dev Reverts on all asset replacement attempts.
    function _replaceAsset(address, address, address, uint256) internal pure override {
        revert IVersionedBeacon.ExtensionPaused();
    }
}
