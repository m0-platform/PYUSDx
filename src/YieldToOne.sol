// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20 } from "../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";

import { IYieldToOne } from "./interfaces/IYieldToOne.sol";
import { IPYUSDX } from "./interfaces/IPYUSDX.sol";

import { Freezable } from "../lib/m-extensions/src/components/freezable/Freezable.sol";
import { Pausable } from "../lib/m-extensions/src/components/pausable/Pausable.sol";
import { PYUSDXExtension } from "./PYUSDXExtension.sol";

abstract contract YieldToOneStorageLayout {
    /// @custom:storage-location erc7201:PYUSDX.storage.YieldToOne
    struct YieldToOneStorageStruct {
        address yieldRecipient;
        mapping(address account => uint256 balance) balanceOf;
    }

    // keccak256(abi.encode(uint256(keccak256("PYUSDX.storage.YieldToOne")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _YIELD_TO_ONE_STORAGE_LOCATION =
        0xdeb0f77528a555c599f306cdb984f1f31ca08f014cad1aa7b02fa3fece5e2e00;

    function _getYieldToOneStorage() internal pure returns (YieldToOneStorageStruct storage $) {
        bytes32 location = _YIELD_TO_ONE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }
}

/**
 * @title  YieldToOne
 * @notice Upgradeable ERC20 token wrapping PYUSDX into a branded non-rebasing stablecoin
 *         with all yield claimable by a single recipient.
 * @dev    Yield accrues on the extension's PYUSDX balance via PYUSDX's per-account earning
 *         system. When the extension's pending yield is claimed, it is first realized from
 *         PYUSDX (net of PYUSDX's fee), then minted as extension tokens to the yield recipient.
 * @author M0 Labs
 */
contract YieldToOne is IYieldToOne, YieldToOneStorageLayout, PYUSDXExtension, Freezable, Pausable {
    /* ============ Variables ============ */

    /// @inheritdoc IYieldToOne
    bytes32 public constant YIELD_RECIPIENT_MANAGER_ROLE = keccak256("YIELD_RECIPIENT_MANAGER_ROLE");

    /* ============ Constructor ============ */

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     * @param pyusdx_       The address of the PYUSDX token.
     * @param swapFacility_ The address of the swap facility.
     */
    constructor(address pyusdx_, address swapFacility_) PYUSDXExtension(pyusdx_, swapFacility_) {}

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the YieldToOne extension token.
     * @param  name                  The name of the token.
     * @param  symbol                The symbol of the token.
     * @param  yieldRecipient_       The address of the yield recipient.
     * @param  admin                 The address of the admin.
     * @param  freezeManager         The address of the freeze manager.
     * @param  yieldRecipientManager The address of the yield recipient manager.
     * @param  pauser                The address of the pauser.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser
    ) public virtual initializer {
        __YieldToOne_init(name, symbol, yieldRecipient_, admin, freezeManager, yieldRecipientManager, pauser);
    }

    /**
     * @dev   Internal initializer. Sets up ERC20 metadata, roles, and the
     *        yield recipient.
     * @param name                  The name of the token.
     * @param symbol                The symbol of the token.
     * @param yieldRecipient_       The address of the yield recipient.
     * @param admin                 The address of the admin.
     * @param freezeManager         The address of the freeze manager.
     * @param yieldRecipientManager The address of the yield recipient manager.
     * @param pauser                The address of the pauser.
     */
    function __YieldToOne_init(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser
    ) internal onlyInitializing {
        if (yieldRecipientManager == address(0)) revert ZeroYieldRecipientManager();
        if (admin == address(0)) revert ZeroAdmin();
        if (IPYUSDX(pyusdx).claimRecipientFor(address(this)) != address(this)) revert InvalidClaimRecipient();

        __PYUSDXExtension_init(name, symbol);
        __Freezable_init(freezeManager);
        __Pausable_init(pauser);

        _setYieldRecipient(yieldRecipient_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IYieldToOne
    function claimYield() public virtual returns (uint256) {
        _beforeClaimYield();

        uint256 totalSupplyBefore_ = totalSupply();

        IPYUSDX(pyusdx).claimFor(address(this));

        uint256 yield_ = totalSupply() - totalSupplyBefore_;

        if (yield_ == 0) return 0;

        emit YieldClaimed(yield_);

        _mint(yieldRecipient(), yield_);

        return yield_;
    }

    /// @inheritdoc IYieldToOne
    function setYieldRecipient(address account) external virtual onlyRole(YIELD_RECIPIENT_MANAGER_ROLE) {
        // Claim yield for the previous yield recipient before changing.
        claimYield();

        _setYieldRecipient(account);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override returns (uint256) {
        return _getYieldToOneStorage().balanceOf[account];
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual returns (uint256) {
        return _pyusdxBalanceOf(address(this));
    }

    /// @inheritdoc IYieldToOne
    function yield() public view virtual returns (uint256) {
        return IPYUSDX(pyusdx).accruedYieldOf(address(this));
    }

    /// @inheritdoc IYieldToOne
    function yieldRecipient() public view returns (address) {
        return _getYieldToOneStorage().yieldRecipient;
    }

    /* ============ Hooks ============ */

    /**
     * @dev   Hook called before approval. Reverts if frozen.
     * @param account The account granting approval.
     * @param spender The account being approved.
     */
    function _beforeApprove(address account, address spender, uint256) internal view virtual override {
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();
        _revertIfFrozen($, account);
        _revertIfFrozen($, spender);
    }

    /**
     * @dev   Hook called before wrapping PYUSDX into extension tokens.
     * @param account   The account depositing PYUSDX.
     * @param recipient The account receiving extension tokens.
     */
    function _beforeWrap(address account, address recipient, uint256) internal view virtual override {
        _requireNotPaused();
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();
        _revertIfFrozen($, account);
        _revertIfFrozen($, recipient);
    }

    /**
     * @dev   Hook called before unwrapping extension tokens for PYUSDX.
     * @param account The account from which extension tokens are burned.
     */
    function _beforeUnwrap(address account, uint256) internal view virtual override {
        _requireNotPaused();
        _revertIfFrozen(_getFreezableStorageLocation(), account);
    }

    /**
     * @dev   Hook called before transferring extension tokens.
     * @param sender    The address sending tokens.
     * @param recipient The address receiving tokens.
     */
    function _beforeTransfer(address sender, address recipient, uint256) internal view virtual override {
        _requireNotPaused();
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();
        _revertIfFrozen($, msg.sender);
        _revertIfFrozen($, sender);
        _revertIfFrozen($, recipient);
    }

    /// @dev   Hook called before claiming yield. Reverts if the PYUSDX claimRecipient is misconfigured.
    ///        Inheriting contracts that override this function MUST call `super._beforeClaimYield()`.
    function _beforeClaimYield() internal view virtual {
        if (IPYUSDX(pyusdx).claimRecipientFor(address(this)) != address(this)) revert InvalidClaimRecipient();
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev   Mints `amount` extension tokens to `recipient`.
     * @param recipient The address receiving the minted tokens.
     * @param amount    The amount of tokens to mint.
     */
    function _mint(address recipient, uint256 amount) internal override {
        unchecked {
            _getYieldToOneStorage().balanceOf[recipient] += amount;
        }

        emit Transfer(address(0), recipient, amount);
    }

    /**
     * @dev   Burns `amount` extension tokens from `account`.
     * @param account The address from which tokens are burned.
     * @param amount  The amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal override {
        unchecked {
            _getYieldToOneStorage().balanceOf[account] -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev   Internal balance update on transfer.
     * @param sender    The address sending tokens.
     * @param recipient The address receiving tokens.
     * @param amount    The amount to transfer.
     */
    function _update(address sender, address recipient, uint256 amount) internal override {
        YieldToOneStorageStruct storage $ = _getYieldToOneStorage();

        unchecked {
            $.balanceOf[sender] -= amount;
            $.balanceOf[recipient] += amount;
        }
    }

    /**
     * @dev   Sets the yield recipient. Reverts if address(0).
     * @param yieldRecipient_ The address of the new yield recipient.
     */
    function _setYieldRecipient(address yieldRecipient_) internal {
        if (yieldRecipient_ == address(0)) revert ZeroYieldRecipient();

        YieldToOneStorageStruct storage $ = _getYieldToOneStorage();

        if (yieldRecipient_ == $.yieldRecipient) return;

        $.yieldRecipient = yieldRecipient_;

        emit YieldRecipientSet(yieldRecipient_);
    }
}
