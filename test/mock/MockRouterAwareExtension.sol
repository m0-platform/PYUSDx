// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { ERC20 } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";

import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

contract MockRouterAwareExtension is ERC20 {
    address public immutable pyusdx;
    address public immutable swapFacility;

    address public lastResolvedSender;

    constructor(address pyusdx_, address swapFacility_) ERC20("Mock Router Aware Extension", "mRAE") {
        pyusdx = pyusdx_;
        swapFacility = swapFacility_;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function wrap(address recipient, uint256 amount) external {
        require(msg.sender == swapFacility, "not swap");

        lastResolvedSender = ISwapFacility(msg.sender).msgSender();

        IERC20(pyusdx).transferFrom(swapFacility, address(this), amount);
        _mint(recipient, amount);
    }

    function unwrap(uint256 amount) external {
        require(msg.sender == swapFacility, "not swap");

        lastResolvedSender = ISwapFacility(msg.sender).msgSender();

        _burn(msg.sender, amount);
        IERC20(pyusdx).transfer(swapFacility, amount);
    }
}
