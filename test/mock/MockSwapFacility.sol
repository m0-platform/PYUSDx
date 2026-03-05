// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";

import { ISwapFacility } from "../../src/interfaces/ISwapFacility.sol";
import { IPYUSDXExtension } from "../../src/interfaces/IPYUSDXExtension.sol";
import { IMultiMint } from "../../src/interfaces/IMultiMint.sol";

contract MockSwapFacility is ISwapFacility {
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
        IPYUSDXExtension(extension).wrap(recipient, amount);
        _locker = address(0);
    }

    function swapOut(address extension, uint256 amount, address recipient) external {
        _locker = msg.sender;
        IERC20(extension).transferFrom(msg.sender, address(this), amount);
        IPYUSDXExtension(extension).unwrap(amount);
        IERC20(pyusdx).transfer(recipient, amount);
        _locker = address(0);
    }

    function swapExtensions(address extIn, address extOut, uint256 amount, address recipient) external {
        _locker = msg.sender;
        IERC20(extIn).transferFrom(msg.sender, address(this), amount);
        IPYUSDXExtension(extIn).unwrap(amount);
        uint256 bal = IERC20(pyusdx).balanceOf(address(this));
        IERC20(pyusdx).approve(extOut, bal);
        IPYUSDXExtension(extOut).wrap(recipient, bal);
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
        IMultiMint(extension).replaceAssetWithPYUSDX(asset, recipient, amount);
        _locker = address(0);
    }
}
