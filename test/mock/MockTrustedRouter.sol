// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

contract MockTrustedRouter {
    address private _currentSender;

    function msgSender() external view returns (address) {
        return _currentSender;
    }

    function swapIn(
        IERC20 tokenIn,
        ISwapFacility swapFacility,
        address extensionOut,
        uint256 amount,
        address recipient
    ) external {
        _currentSender = msg.sender;

        tokenIn.transferFrom(msg.sender, address(this), amount);
        tokenIn.approve(address(swapFacility), amount);

        swapFacility.swapIn(extensionOut, amount, recipient);
        _currentSender = address(0);
    }
}
