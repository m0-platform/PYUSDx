// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

/// @title PYUSDX Mock
/// @notice Minimal mock for testing MinterGateway unit tests
contract MockPYUSDX {
    address public minterGateway;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address minterGateway_) {
        minterGateway = minterGateway_;
    }

    modifier onlyMinterGateway() {
        require(msg.sender == minterGateway, "NotMinterGateway");
        _;
    }

    function mint(address account, uint256 amount) external onlyMinterGateway {
        balanceOf[account] += amount;
        totalSupply += amount;
    }

    function burn(address account, uint256 amount) external onlyMinterGateway {
        balanceOf[account] -= amount;
        totalSupply -= amount;
    }
}
