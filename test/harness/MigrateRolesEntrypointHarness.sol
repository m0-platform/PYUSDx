// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { MigrateRoles } from "../../script/migrate/MigrateRoles.s.sol";
import { ProposeMigrateRoles } from "../../script/migrate/ProposeMigrateRoles.s.sol";
import { VerifyRoles } from "../../script/migrate/VerifyRoles.s.sol";

/// @notice The migration entry points, pointed at a scratch protocol config and deployment record.
/// @dev    Only the two path seams move, through the `virtual` hooks production already leaves for
///         exactly this. `run()`, the config loader, the plan, the staging, `vm.rememberKey` /
///         `vm.startBroadcast` and the Safe serialization are the production code paths, and the
///         scratch config is a real file on disk read and parsed like any checked-in one.
///
///         Redirected rather than driven through `PROTOCOL_CONFIG`, because that variable is a
///         process-global and forge interleaves suites: a test that wrote it would change what
///         `DeployAllConfigTests` reads at the same moment. An empty scratch path falls through to
///         the production lookup, which is how the environment-driven path is exercised -- by an
///         isolated run with the variable set, never by the normal suite.
///
///         The three cannot share a mixin: each already inherits `ScriptBase` through its own entry
///         point, so a second path to it would need an explicit `override(...)` in every derived
///         contract, which is longer than the repetition it would remove.
contract MigrateRolesEntrypointHarness is MigrateRoles {
    string internal _scratchConfigPath;

    string internal _scratchOutputDir;

    uint256 internal _signerKey;

    function useScratchPaths(string memory configPath, string memory outputDir) external {
        _scratchConfigPath = configPath;
        _scratchOutputDir = outputDir;
    }

    function useSignerKey(uint256 signerKey) external {
        _signerKey = signerKey;
    }

    function _protocolConfigPath(uint256 chainId) internal view override returns (string memory) {
        if (bytes(_scratchConfigPath).length == 0) return super._protocolConfigPath(chainId);

        return _scratchConfigPath;
    }

    function _deployOutputDir() internal view override returns (string memory) {
        return _scratchOutputDir;
    }

    function _signerPrivateKey() internal view override returns (uint256) {
        return _signerKey;
    }
}

/// @notice `VerifyRoles` on the same scratch paths. It needs no key and no Safe.
contract VerifyRolesEntrypointHarness is VerifyRoles {
    string internal _scratchConfigPath;

    string internal _scratchOutputDir;

    function useScratchPaths(string memory configPath, string memory outputDir) external {
        _scratchConfigPath = configPath;
        _scratchOutputDir = outputDir;
    }

    function _protocolConfigPath(uint256 chainId) internal view override returns (string memory) {
        if (bytes(_scratchConfigPath).length == 0) return super._protocolConfigPath(chainId);

        return _scratchConfigPath;
    }

    function _deployOutputDir() internal view override returns (string memory) {
        return _scratchOutputDir;
    }
}

/// @notice `ProposeMigrateRoles` on the same scratch paths, pinned to the offline export.
/// @dev    Pinned for the same reason as `SafeProposerHarness`: a developer with a real webhook or
///         `SAFE_SUBMIT=true` in `.env` must not have a test reach a live channel or transaction
///         service. Nothing here touches the network.
contract ProposeMigrateRolesEntrypointHarness is ProposeMigrateRoles {
    string internal _scratchConfigPath;

    string internal _scratchOutputDir;

    address internal _safe;

    function useScratchPaths(string memory configPath, string memory outputDir) external {
        _scratchConfigPath = configPath;
        _scratchOutputDir = outputDir;
    }

    function useSafe(address safe) external {
        _safe = safe;
    }

    function _protocolConfigPath(uint256 chainId) internal view override returns (string memory) {
        if (bytes(_scratchConfigPath).length == 0) return super._protocolConfigPath(chainId);

        return _scratchConfigPath;
    }

    function _deployOutputDir() internal view override returns (string memory) {
        return _scratchOutputDir;
    }

    function _safeMultisig() internal view override returns (address) {
        return _safe;
    }

    function _submitEnabled() internal pure override returns (bool) {
        return false;
    }

    function _alertWebhookUrl() internal pure override returns (string memory) {
        return "";
    }
}
