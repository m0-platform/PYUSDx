// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { ERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        _burn(to, amount);
    }

    /// @dev Mimics the `IERC20Extended` bytes-signature permit: validates the deadline and grants
    ///      the allowance without verifying the signature itself.
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory) external {
        require(block.timestamp <= deadline, "MockERC20: expired permit");
        _approve(owner, spender, value);
    }
}
