// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { IMultiMint } from "../../src/platform/projects/interfaces/IMultiMint.sol";

contract MockSwapFacility {
    address public pyusdx;
    address private _locker;

    constructor(address pyusdx_) {
        pyusdx = pyusdx_;
    }

    function msgSender() external view returns (address) {
        return _locker;
    }

    function swapIn(address extension, uint256 amount, address recipient) external {
        _locker = msg.sender;
        IERC20(pyusdx).transferFrom(msg.sender, address(this), amount);
        IERC20(pyusdx).approve(extension, amount);
        IExtension(extension).wrap(recipient, amount);
        _locker = address(0);
    }

    function swapOut(address extension, uint256 amount, address recipient) external {
        _locker = msg.sender;
        IERC20(extension).transferFrom(msg.sender, address(this), amount);
        IExtension(extension).unwrap(amount);
        IERC20(pyusdx).transfer(recipient, amount);
        _locker = address(0);
    }

    function swapExtensions(address extIn, address extOut, uint256 amount, address recipient) external {
        _locker = msg.sender;
        IERC20(extIn).transferFrom(msg.sender, address(this), amount);
        IExtension(extIn).unwrap(amount);
        uint256 bal = IERC20(pyusdx).balanceOf(address(this));
        IERC20(pyusdx).approve(extOut, bal);
        IExtension(extOut).wrap(recipient, bal);
        _locker = address(0);
    }

    function swapInAsset(address extension, address asset, uint256 amount, address recipient) external {
        _locker = msg.sender;
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(extension, amount);
        IMultiMint(extension).wrap(asset, recipient, amount);
        _locker = address(0);
    }

    function replaceAsset(address extension, address asset, uint256 amount, address recipient) external {
        _locker = msg.sender;
        IERC20(pyusdx).transferFrom(msg.sender, address(this), amount);
        IERC20(pyusdx).approve(extension, amount);
        IMultiMint(extension).replaceAsset(asset, recipient, amount);

        // Refund any PYUSDX not consumed by the extension (truncation remainder).
        uint256 refund = IERC20(pyusdx).balanceOf(address(this));
        if (refund > 0) IERC20(pyusdx).transfer(msg.sender, refund);

        _locker = address(0);
    }
}
