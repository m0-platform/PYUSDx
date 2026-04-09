// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Extension } from "../../src/platform/Extension.sol";

/// @title ExtensionHarness
/// @notice Minimal concrete Extension for isolated testing of base-level behavior
///         (freeze, pause, transfer, wrap, unwrap).
contract ExtensionHarness is Extension {
    uint256 private _totalSupply;
    mapping(address account => uint256) private _balances;

    /// @notice Identifiable version for upgrade propagation testing.
    uint256 public immutable harnessVersion;

    /// @param  version_ Identifiable version for upgrade propagation testing.
    constructor(address pyusdx_, address swapFacility_, uint256 version_) Extension(pyusdx_, swapFacility_) {
        harnessVersion = version_;
    }

    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address freezeManager,
        address pauser
    ) public initializer {
        __Extension_init(name, symbol, freezeManager, pauser);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @dev   Mints `amount` tokens to `recipient`.
    /// @param recipient The address to which the tokens will be minted.
    /// @param amount    The amount of tokens to mint.
    function _mint(address recipient, uint256 amount) internal override {
        _totalSupply += amount;

        unchecked {
            _balances[recipient] += amount;
        }

        emit Transfer(address(0), recipient, amount);
    }

    /// @dev   Burns `amount` tokens from `account`.
    /// @param account The address from which the tokens will be burned.
    /// @param amount  The amount of tokens to burn.
    function _burn(address account, uint256 amount) internal override {
        _totalSupply -= amount;

        unchecked {
            _balances[account] -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    /// @dev   Internal balance update function.
    /// @param sender    The sender's address.
    /// @param recipient The recipient's address.
    /// @param amount    The amount to be transferred.
    function _update(address sender, address recipient, uint256 amount) internal override {
        unchecked {
            _balances[sender] -= amount;
            _balances[recipient] += amount;
        }
    }

    /// @inheritdoc Extension
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /// @dev Returns the total supply of tokens.
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /// @notice Expose internal mint for testing.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
