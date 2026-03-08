// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { ERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";
import { IReentrancyLock } from "../../src/swap/interfaces/IReentrancyLock.sol";

contract MockReentrantExtension is ERC20 {
    address public immutable pyusdx;
    address public immutable swapFacility;

    bool public reentrancyAttempted;
    bool public reentrancyBlocked;

    constructor(address pyusdx_, address swapFacility_) ERC20("Mock Reentrant Extension", "mRE") {
        pyusdx = pyusdx_;
        swapFacility = swapFacility_;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function wrap(address recipient, uint256 amount) external {
        require(msg.sender == swapFacility, "not swap");

        reentrancyAttempted = true;

        try ISwapFacility(swapFacility).swapIn(address(this), 1, recipient) {
            // no-op
        } catch (bytes memory reason) {
            reentrancyBlocked = reason.length >= 4 && bytes4(reason) == IReentrancyLock.ContractLocked.selector;
        }

        IERC20(pyusdx).transferFrom(swapFacility, address(this), amount);
        _mint(recipient, amount);
    }

    function unwrap(uint256 amount) external {
        require(msg.sender == swapFacility, "not swap");

        _burn(msg.sender, amount);
        IERC20(pyusdx).transfer(swapFacility, amount);
    }
}
