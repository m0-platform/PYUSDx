// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title PYUSDX Mock
/// @notice Minimal mock for testing IssuerGateway unit tests
contract PYUSDXMock {
    address public issuerGateway;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address issuerGateway_) {
        issuerGateway = issuerGateway_;
    }

    modifier onlyIssuerGateway() {
        require(msg.sender == issuerGateway, "NotIssuerGateway");
        _;
    }

    function mint(address account, uint256 amount) external onlyIssuerGateway {
        balanceOf[account] += amount;
        totalSupply += amount;
    }

    function burn(address account, uint256 amount) external onlyIssuerGateway {
        balanceOf[account] -= amount;
        totalSupply -= amount;
    }
}
