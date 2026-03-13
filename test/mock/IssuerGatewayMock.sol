// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IPYUSDX } from "../../src/IPYUSDX.sol";

/// @title Issuer Gateway Mock
/// @notice Mock contract to test PYUSDX mint functionality
<<<<<<<< HEAD:test/mock/IssuerGatewayMock.sol
contract IssuerGatewayMock {
========
contract MockMinterGateway {
>>>>>>>> c3ce391 (chore: use Solidity version 0.8.34 (#19)):test/mock/MockMinterGateway.sol
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
