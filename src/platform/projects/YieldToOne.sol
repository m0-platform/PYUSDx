// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { IERC20 } from "../../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { IPYUSDX } from "../../IPYUSDX.sol";

import { Extension } from "../Extension.sol";

import { IYieldToOne } from "./interfaces/IYieldToOne.sol";

abstract contract YieldToOneStorageLayout {
    /// @custom:storage-location erc7201:PYUSDX.storage.YieldToOne
    struct YieldToOneStorage {
        uint256 totalSupply;
        address yieldRecipient;
        mapping(address account => uint256 balance) balanceOf;
    }

    // keccak256(abi.encode(uint256(keccak256("PYUSDX.storage.YieldToOne")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _YIELD_TO_ONE_STORAGE_LOCATION =
        0xdeb0f77528a555c599f306cdb984f1f31ca08f014cad1aa7b02fa3fece5e2e00;

    function _getYieldToOneStorage() internal pure returns (YieldToOneStorage storage $) {
        bytes32 location = _YIELD_TO_ONE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }
}

/// @title  YieldToOne
/// @notice Upgradeable ERC20 token wrapping PYUSDX into a branded non-rebasing stablecoin
///         with all yield claimable by a single recipient.
/// @dev    Yield accrues on the extension's PYUSDX balance via PYUSDX's per-account earning
///         system. When the extension's pending yield is claimed, it is first realized from
///         PYUSDX (net of PYUSDX's fee), then minted as extension tokens to the yield recipient.
/// @author M0 Labs
contract YieldToOne is IYieldToOne, YieldToOneStorageLayout, Extension {
    /* ============ Variables ============ */

    /// @inheritdoc IYieldToOne
    bytes32 public constant YIELD_RECIPIENT_MANAGER_ROLE = keccak256("YIELD_RECIPIENT_MANAGER_ROLE");

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param pyusdx_       The address of the PYUSDX token.
    /// @param swapFacility_ The address of the swap facility.
    constructor(address pyusdx_, address swapFacility_) Extension(pyusdx_, swapFacility_) {}

    /* ============ Initializer ============ */

    /// @notice Initializes the YieldToOne extension token.
    /// @param  name                  The name of the token.
    /// @param  symbol                The symbol of the token.
    /// @param  yieldRecipient_       The address of the yield recipient.
    /// @param  admin                 The address of the admin.
    /// @param  freezeManager         The address of the freeze manager.
    /// @param  pauser                The address of the pauser.
    /// @param  yieldRecipientManager The address of the yield recipient manager.
    /// @param  versionManager        The address of the version manager.
    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address pauser,
        address yieldRecipientManager,
        address versionManager
    ) public virtual initializer {
        __YieldToOne_init(
            name,
            symbol,
            yieldRecipient_,
            admin,
            freezeManager,
            pauser,
            yieldRecipientManager,
            versionManager
        );
    }

    /// @dev   Internal initializer. Sets up ERC20 metadata, roles, and the
    ///        yield recipient.
    /// @param name                  The name of the token.
    /// @param symbol                The symbol of the token.
    /// @param yieldRecipient_       The address of the yield recipient.
    /// @param admin                 The address of the admin.
    /// @param freezeManager         The address of the freeze manager.
    /// @param pauser                The address of the pauser.
    /// @param yieldRecipientManager The address of the yield recipient manager.
    /// @param versionManager        The address of the version manager.
    function __YieldToOne_init(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address pauser,
        address yieldRecipientManager,
        address versionManager
    ) internal onlyInitializing {
        if (admin == address(0)) revert ZeroAdmin();
        if (yieldRecipientManager == address(0)) revert ZeroYieldRecipientManager();
        if (versionManager == address(0)) revert ZeroVersionManager();

        __AccessControl_init();
        __Extension_init(name, symbol, freezeManager, pauser);

        _setYieldRecipient(yieldRecipient_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VERSION_MANAGER_ROLE, versionManager);
        _grantRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IYieldToOne
    function claimYield() public virtual returns (uint256) {
        _beforeClaimYield();

        // NOTE: Realize any pending PYUSDX yield
        IPYUSDX(pyusdx).claimFor(address(this));

        // NOTE: Excess accounts for the newly claimed yield and any prior unclaimed yield
        //       (i.e. PYUSDX donation or `claimFor()` the extension at the PYUSDX level)
        uint256 excess = _excess();

        if (excess == 0) return 0;

        emit YieldClaimed(excess);

        // NOTE: mint the excess PYUSDX as extension tokens
        _mint(yieldRecipient(), excess);

        return excess;
    }

    /// @inheritdoc IYieldToOne
    function setYieldRecipient(address account) external virtual onlyRole(YIELD_RECIPIENT_MANAGER_ROLE) {
        // NOTE: Skip the claim when the outgoing recipient is frozen — `_beforeClaimYield`
        //       would otherwise revert on the freeze check, blocking the admin's ability
        //       to rotate a compromised recipient mid-incident. Pending PYUSDX yield
        //       remains as `_excess()` and is paid to the next recipient on their first
        //       claim. The frozen recipient's forgone slice is an accepted cost of the
        //       incident-response path.
        if (!isFrozen(yieldRecipient())) claimYield();

        _setYieldRecipient(account);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override returns (uint256) {
        return _getYieldToOneStorage().balanceOf[account];
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual returns (uint256) {
        return _getYieldToOneStorage().totalSupply;
    }

    /// @inheritdoc IYieldToOne
    function yield() public view virtual returns (uint256) {
        return _excess() + IPYUSDX(pyusdx).accruedYieldToSelfOf(address(this));
    }

    /// @inheritdoc IYieldToOne
    function yieldRecipient() public view returns (address) {
        return _getYieldToOneStorage().yieldRecipient;
    }

    /* ============ Hooks ============ */

    /// @dev Hook called before claiming yield. Restricts the caller to
    ///      `YIELD_RECIPIENT_MANAGER_ROLE` and reverts if the yield recipient is frozen.
    ///      Intentionally omits `_requireNotPaused()` so the admin can rotate a compromised
    ///      recipient mid-incident via `setYieldRecipient` (which calls `claimYield`
    ///      internally). Minted extension tokens cannot move while paused —
    ///      `_beforeTransfer`, `_beforeWrap`, and `_beforeUnwrap` all enforce the pause —
    ///      so supply minted during pause is economically inert until unpause.
    function _beforeClaimYield() internal view virtual onlyRole(YIELD_RECIPIENT_MANAGER_ROLE) {
        _revertIfFrozen(_getFreezableStorageLocation(), yieldRecipient());
    }

    /* ============ Internal Interactive Functions ============ */

    /// @dev   Mints `amount` extension tokens to `recipient`.
    /// @param recipient The address receiving the minted tokens.
    /// @param amount    The amount of tokens to mint.
    function _mint(address recipient, uint256 amount) internal override {
        YieldToOneStorage storage $ = _getYieldToOneStorage();

        $.totalSupply += amount;

        unchecked {
            $.balanceOf[recipient] += amount;
        }

        emit Transfer(address(0), recipient, amount);
    }

    /// @dev   Burns `amount` extension tokens from `account`.
    /// @param account The address from which tokens are burned.
    /// @param amount  The amount of tokens to burn.
    function _burn(address account, uint256 amount) internal override {
        YieldToOneStorage storage $ = _getYieldToOneStorage();

        // NOTE: `amount` is verified to not exceed `$.balanceOf[account]` by the caller, so
        //       subtraction cannot underflow. `totalSupply >= balanceOf[account]` by invariant.
        unchecked {
            $.totalSupply -= amount;
            $.balanceOf[account] -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    /// @dev   Internal balance update on transfer.
    /// @param sender    The address sending tokens.
    /// @param recipient The address receiving tokens.
    /// @param amount    The amount to transfer.
    function _update(address sender, address recipient, uint256 amount) internal override {
        YieldToOneStorage storage $ = _getYieldToOneStorage();

        // NOTE: `amount` is verified to not exceed `$.balanceOf[sender]` by the caller, so
        //       subtraction cannot underflow. Addition cannot overflow because `totalSupply`
        //       (which bounds the sum of all balances) fits in uint256.
        unchecked {
            $.balanceOf[sender] -= amount;
            $.balanceOf[recipient] += amount;
        }
    }

    /// @dev   Sets the yield recipient. Reverts if address(0).
    /// @param yieldRecipient_ The address of the new yield recipient.
    function _setYieldRecipient(address yieldRecipient_) internal {
        if (yieldRecipient_ == address(0)) revert ZeroYieldRecipient();

        YieldToOneStorage storage $ = _getYieldToOneStorage();

        if ($.yieldRecipient == yieldRecipient_) return;

        $.yieldRecipient = yieldRecipient_;

        emit YieldRecipientSet(yieldRecipient_);
    }

    /* ============ Internal View Functions ============ */

    /// @dev Returns the excess PYUSDX balance of the extension
    function _excess() internal view virtual returns (uint256) {
        uint256 pyusdxBalance = _pyusdxBalanceOf(address(this));
        uint256 totalSupply_ = totalSupply();

        unchecked {
            return pyusdxBalance > totalSupply_ ? pyusdxBalance - totalSupply_ : 0;
        }
    }
}
