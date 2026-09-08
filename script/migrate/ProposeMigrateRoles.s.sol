// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { Config } from "../Config.sol";
import { SafeProposerBase } from "../configure/SafeProposerBase.sol";
import { Transaction } from "../libraries/TransactionHelper.sol";
import { MigrateRolesBase, MigrationAction, NothingExecutable } from "./MigrateRolesBase.sol";

/// @notice Thrown when a proposal is requested without a Safe to execute it.
error SafeMultisigRequired();

/// @title  ProposeMigrateRoles
/// @notice Writes the role migration as a Safe Transaction Builder batch JSON, for execution by the
///         multisig that currently holds the authority. Does not broadcast.
/// @dev    The plan is built for `SAFE_MULTISIG`, not for the proposer EOA: the Safe is what will
///         send these calls, so the Safe's authority is what decides which of them can be batched.
///         Building it for the proposer would queue calls the Safe cannot execute and omit ones it
///         can.
///
///         The batch carries exactly the transactions `MigrateRoles` would broadcast for that same
///         executor — both compact the same plan — so the two paths cannot drift.
///
///         Queuing a batch is not a completed handover. Only `verify-roles`, run after the Safe has
///         executed, says the migration is done.
contract ProposeMigrateRoles is MigrateRolesBase, SafeProposerBase {
    function run() external {
        uint256 chainId = block.chainid;

        string memory json = _readProtocolConfigFile(chainId);
        ProtocolConfig memory config = _parseProtocolConfig(json, chainId);
        Config.MigrationConfig memory migration = _parseMigrationConfig(json);

        address safe = _safeMultisig();

        if (safe == address(0)) revert SafeMultisigRequired();

        console.log("Safe (executor):", safe);

        MigrationAction[] memory actions = _planMigration(_readDeployment(chainId), config, migration, safe);

        _logPlan(actions, string.concat("PYUSDX role migration plan (chain ", vm.toString(chainId), "):"));

        uint256 outstanding = _outstandingCount(actions);

        if (outstanding == 0) {
            console.log("Every obligation is already carried by the chain; no Safe batch written.");
            console.log("Any existing export from an earlier run is stale; do not import it for this run.");
            return;
        }

        Transaction[] memory transactions = _stagedTransactions(actions);

        if (transactions.length == 0) revert NothingExecutable(safe, outstanding);

        _writeSafeBatch("migrate-roles", transactions);

        // Not "queued": by default this only writes the offline export, and even with SAFE_SUBMIT a
        // proposal the Safe has not executed has changed nothing on chain.
        console.log("Batch prepared, not migrated: run `verify-roles` after the Safe has executed it.");

        uint256 deferred = _deferredCount(actions);

        if (deferred == 0) return;

        console.log("%s obligation(s) are gated on a holder other than this Safe and are not in", deferred);
        console.log("the batch -- see the [defer] lines above.");
    }
}
