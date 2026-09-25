// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { ScriptBase } from "../../script/ScriptBase.s.sol";

/// @notice Exposes ScriptBase's deployment-record reader/writer externally and redirects the record
///         to a scratch directory, so the tests never touch the checked-in `deployments/` files.
contract DeploymentRecordHarness is ScriptBase {
    string internal _dir;

    constructor(string memory dir_) {
        _dir = dir_;
    }

    function _deployOutputDir() internal view override returns (string memory) {
        return _dir;
    }

    function outputDir() external view returns (string memory) {
        return _deployOutputDir();
    }

    function outputPath(uint256 chainId_) external view returns (string memory) {
        return _deployOutputPath(chainId_);
    }

    function writeDeployment(uint256 chainId_, string memory key_, address value_) external {
        _writeDeployment(chainId_, key_, value_);
    }

    function readDeployment(uint256 chainId_) external view returns (Deployments memory) {
        return _readDeployment(chainId_);
    }

    function isCoreDeploymentKey(string memory key_) external pure returns (bool) {
        return _isCoreDeploymentKey(key_);
    }
}
