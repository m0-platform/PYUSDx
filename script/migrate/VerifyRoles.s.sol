// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { Config } from "../Config.sol";
import { MigrateRolesBase, MigrationAction, MigrationIncomplete } from "./MigrateRolesBase.sol";

/// @title  VerifyRoles
/// @notice Confirms the deployed suite carries every role, singleton, rate-limit bucket, ProxyAdmin
///         owner and LayerZero delegate named in `deploymentConfigs/<chainid>/protocol.json`, and
///         that no configured outgoing holder still holds anything it was migrated out of.
/// @dev    Verification is the migration plan asserted empty. That is deliberate: one predicate
///         decides both what still needs doing and whether anything does, so a check cannot drift
///         from the work. The plan is built with no executor, so the result is the same whoever
///         would have sent the remaining calls and whichever round they belong to.
///
///         Reads only — no key, no broadcast, no network writes. A getter that cannot be read leaves
///         its obligation outstanding, so unreadable state fails rather than passing quietly, and the
///         preflight in `_planMigration` additionally fails on a suite that is not wired as
///         configured or has lost `ISSUER_ROLE` on the IssuerGateway or Portal.
contract VerifyRoles is MigrateRolesBase {
    function run() external view {
        uint256 chainId = block.chainid;

        string memory json = _readProtocolConfigFile(chainId);
        ProtocolConfig memory config = _parseProtocolConfig(json, chainId);
        Config.MigrationConfig memory migration = _parseMigrationConfig(json);

        MigrationAction[] memory actions = _planMigration(_readDeployment(chainId), config, migration, address(0));

        _logPlan(actions, string.concat("PYUSDX role migration verification (chain ", vm.toString(chainId), "):"));

        uint256 outstanding = _outstandingCount(actions);

        if (outstanding != 0) revert MigrationIncomplete(outstanding);

        console.log("Every configured role, singleton, bucket, proxy owner and delegate is in place,");
        console.log("and no configured outgoing holder retains a role it was migrated out of.");
        console.log("Holders granted outside `migration.outgoingHolders` cannot be detected on chain:");
        console.log("this suite's AccessControl is not enumerable. See deploymentConfigs/README.md.");
    }
}
