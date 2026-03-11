// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IPYUSDX } from "../../src/IPYUSDX.sol";

/// @title Minter Gateway Mock
/// @notice Mock contract to test PYUSDX mint functionality
contract MockMinterGateway {
    IPYUSDX public pyusdx;

    constructor(address pyusdx_) {
        pyusdx = IPYUSDX(pyusdx_);
    }

    // Allow updating pyusdx address after deployment (to handle circular dependency)
    function setPyusdx(address pyusdx_) external {
        pyusdx = IPYUSDX(pyusdx_);
    }

    function mint(address account, uint256 amount) external {
        pyusdx.mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        pyusdx.burn(account, amount);
    }
}
