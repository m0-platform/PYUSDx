// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { DeployAll } from "../../script/deploy/DeployAll.s.sol";

/// @notice Exposes DeployAll's protocol-config loader externally, to avoid forge-std diamond
///         inheritance in tests.
contract DeployAllHarness is DeployAll {
    function parseProtocolConfig(string memory json_, uint256 chainId_) external pure returns (ProtocolConfig memory) {
        return _parseProtocolConfig(json_, chainId_);
    }

    function validateProtocolConfig(ProtocolConfig memory config_) external pure {
        _validateProtocolConfig(config_);
    }

    function readProtocolConfig(uint256 chainId_) external view returns (ProtocolConfig memory) {
        return _readProtocolConfig(chainId_);
    }

    function protocolConfigPath(uint256 chainId_) external view returns (string memory) {
        return _protocolConfigPath(chainId_);
    }
}
