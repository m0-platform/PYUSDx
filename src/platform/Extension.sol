// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { ERC20ExtendedUpgradeable } from "../../lib/evm-m-extensions/lib/common/src/ERC20ExtendedUpgradeable.sol";

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { IExtension } from "./interfaces/IExtension.sol";
import { ISwapFacility } from "../swap/interfaces/ISwapFacility.sol";

/**
 * @title  Extension
 * @notice Upgradeable ERC20 base contract for wrapping PYUSDX into a branded extension token.
 * @author M0 Labs
 */
abstract contract Extension is IExtension, ERC20ExtendedUpgradeable {
    /* ============ Variables ============ */

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtension
    address public immutable pyusdx;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtension
    address public immutable swapFacility;

    /* ============ Modifiers ============ */

    modifier onlySwapFacility() {
        if (msg.sender != swapFacility) revert NotSwapFacility();
        _;
    }

    /* ============ Constructor ============ */

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     * @notice Constructs Extension Implementation contract.
     * @dev    Sets immutable storage.
     * @param  pyusdx_       The address of the PYUSDX token.
     * @param  swapFacility_ The address of the swap facility.
     */
    constructor(address pyusdx_, address swapFacility_) {
        _disableInitializers();

        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDX();
        if ((swapFacility = swapFacility_) == address(0)) revert ZeroSwapFacility();
    }

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the generic PYUSDX extension token.
     * @param  name   The name of the token.
     * @param  symbol The symbol of the token.
     */
    function __Extension_init(string memory name, string memory symbol) internal onlyInitializing {
        __ERC20ExtendedUpgradeable_init(name, symbol, 6);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IExtension
    function wrap(address recipient, uint256 amount) external onlySwapFacility {
        _wrap(ISwapFacility(msg.sender).msgSender(), recipient, amount);
    }

    /// @inheritdoc IExtension
    function unwrap(uint256 amount) external onlySwapFacility {
        _unwrap(ISwapFacility(msg.sender).msgSender(), amount);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IERC20
    function balanceOf(address account) public view virtual returns (uint256);

    /* ============ Hooks For Internal Interactive Functions ============ */

    /**
     * @dev   Hook called before approval of PYUSDX Extension token.
     * @param account The sender's address.
     * @param spender The spender address.
     * @param amount  The amount to be approved.
     */
    function _beforeApprove(address account, address spender, uint256 amount) internal virtual {}

    /**
     * @dev    Hook called before wrapping PYUSDX into PYUSDX Extension token.
     * @param  account   The account from which PYUSDX is deposited.
     * @param  recipient The account receiving the minted PYUSDX Extension token.
     * @param  amount    The amount of PYUSDX deposited.
     */
    function _beforeWrap(address account, address recipient, uint256 amount) internal virtual {}

    /**
     * @dev   Hook called before unwrapping PYUSDX Extension token.
     * @param account The original caller (resolved via swap facility).
     * @param amount  The amount of PYUSDX Extension token burned.
     */
    function _beforeUnwrap(address account, uint256 amount) internal virtual {}

    /**
     * @dev   Hook called before transferring PYUSDX Extension token.
     * @param sender    The sender's address.
     * @param recipient The recipient's address.
     * @param amount    The amount to be transferred.
     */
    function _beforeTransfer(address sender, address recipient, uint256 amount) internal virtual {}

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Approve `spender` to spend `amount` of tokens from `account`.
     * @param account The address approving the allowance.
     * @param spender The address approved to spend the tokens.
     * @param amount  The amount of tokens being approved for spending.
     */
    function _approve(address account, address spender, uint256 amount) internal override {
        _beforeApprove(account, spender, amount);
        super._approve(account, spender, amount);
    }

    /**
     * @dev    Wraps `amount` PYUSDX from `account` into extension token for `recipient`.
     * @param  account   The original caller (resolved via swap facility).
     * @param  recipient The account receiving the minted extension token.
     * @param  amount    The amount of PYUSDX deposited.
     */
    function _wrap(address account, address recipient, uint256 amount) internal {
        _revertIfZeroAccount(recipient);
        _revertIfZeroAmount(amount);

        _beforeWrap(account, recipient, amount);

        IERC20(pyusdx).transferFrom(msg.sender, address(this), amount);

        _mint(recipient, amount);
    }

    /**
     * @dev   Unwraps `amount` extension token from `account` into PYUSDX.
     * @param account The original caller (resolved via swap facility).
     * @param amount  The amount of extension token burned.
     */
    function _unwrap(address account, uint256 amount) internal {
        _revertIfZeroAmount(amount);
        _revertIfInsufficientBalance(msg.sender, amount);

        _beforeUnwrap(account, amount);

        _burn(msg.sender, amount);

        IERC20(pyusdx).transfer(msg.sender, amount);
    }

    /**
     * @dev   Mints `amount` tokens to `recipient`.
     * @param recipient The address to which the tokens will be minted.
     * @param amount    The amount of tokens to mint.
     */
    function _mint(address recipient, uint256 amount) internal virtual;

    /**
     * @dev   Burns `amount` tokens from `account`.
     * @param account The address from which the tokens will be burned.
     * @param amount  The amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal virtual;

    /**
     * @dev   Internal balance update function that needs to be implemented by the inheriting contract.
     * @param sender    The sender's address.
     * @param recipient The recipient's address.
     * @param amount    The amount to be transferred.
     */
    function _update(address sender, address recipient, uint256 amount) internal virtual;

    /**
     * @dev   Internal ERC20 transfer function.
     * @param sender    The sender's address.
     * @param recipient The recipient's address.
     * @param amount    The amount to be transferred.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        _revertIfZeroAccount(recipient);
        _beforeTransfer(sender, recipient, amount);

        emit Transfer(sender, recipient, amount);

        if (amount == 0) return;

        _revertIfInsufficientBalance(sender, amount);

        _update(sender, recipient, amount);
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Returns the PYUSDX balance of `account`.
     * @param  account The account being queried.
     * @return balance The PYUSDX balance of the account.
     */
    function _pyusdxBalanceOf(address account) internal view returns (uint256) {
        return IERC20(pyusdx).balanceOf(account);
    }

    /**
     * @dev   Reverts if `recipient` is address(0).
     * @param recipient Address of a recipient.
     */
    function _revertIfZeroAccount(address recipient) internal pure {
        if (recipient == address(0)) revert ZeroAccount();
    }

    /**
     * @dev   Reverts if `amount` is equal to 0.
     * @param amount Amount of token.
     */
    function _revertIfZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /**
     * @dev   Reverts if `account` balance is below `amount`.
     * @param account Address of an account.
     * @param amount  Amount to transfer or burn.
     */
    function _revertIfInsufficientBalance(address account, uint256 amount) internal view {
        uint256 balance = balanceOf(account);

        if (balance < amount) revert InsufficientBalance(account, balance, amount);
    }
}
