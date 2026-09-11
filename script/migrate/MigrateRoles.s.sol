// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { Config } from "../Config.sol";
import { Transaction, TransactionHelper } from "../libraries/TransactionHelper.sol";
import { MigrateRolesBase, MigrationAction, NothingExecutable } from "./MigrateRolesBase.sol";

/// @title  MigrateRoles
/// @notice Broadcasts the part of the role migration the signer is authorised to send, moving the
///         deployed suite towards the holders named in `deploymentConfigs/<chainid>/protocol.json`.
/// @dev    The signer (PRIVATE_KEY) needs no particular role to read the plan — it is built from
///         `staticcall`s — but only the calls it can actually send are broadcast. Anything gated on
///         another current holder is reported as deferred and left for that holder's own run, which
///         is how a suite whose authority is split across several addresses is migrated: each holder
///         runs this target in turn until `verify-roles` reports nothing outstanding.
///
///         A rerun after completion broadcasts nothing. A signer that can send none of the
///         outstanding work fails loudly rather than reporting an empty, successful run.
contract MigrateRoles is MigrateRolesBase {
    using TransactionHelper for Transaction[];

    function run() external {
        uint256 chainId = block.chainid;

        string memory json = _readProtocolConfigFile(chainId);
        ProtocolConfig memory config = _parseProtocolConfig(json, chainId);
        Config.MigrationConfig memory migration = _parseMigrationConfig(json);

        address signer = vm.rememberKey(_signerPrivateKey());
        console.log("Signer:", signer);

        MigrationAction[] memory actions = _planMigration(_readDeployment(chainId), config, migration, signer);

        _logPlan(actions, string.concat("PYUSDX role migration plan (chain ", vm.toString(chainId), "):"));

        uint256 outstanding = _outstandingCount(actions);

        if (outstanding == 0) {
            console.log("Every obligation is already carried by the chain; nothing broadcast.");
            return;
        }

        Transaction[] memory transactions = _stagedTransactions(actions);

        if (transactions.length == 0) revert NothingExecutable(signer, outstanding);

        vm.startBroadcast(signer);

        transactions.execute();

        vm.stopBroadcast();

        _reportRemaining(_deferredCount(actions), transactions.length);
    }

    /// @dev Deferred work is an expected outcome, not a failure: reverting here would undo calls that
    ///      succeeded. The run reports what it executed and what still needs another holder, and
    ///      `verify-roles` remains the only thing that declares the handover complete.
    ///
    ///      "Executed", not "sent": the same code path runs under `DRY_RUN=true`, where forge
    ///      simulates every call and broadcasts none, so this script cannot claim a chain write.
    function _reportRemaining(uint256 deferred, uint256 executed) private pure {
        console.log("Executed %s call(s) -- broadcast only when this run was given --broadcast.", executed);

        if (deferred == 0) {
            console.log("No further work was deferred. Run `verify-roles` to confirm the end state.");
            return;
        }

        console.log("%s obligation(s) were deferred to another current holder -- see the", deferred);
        console.log("[defer] lines above for the authority each one needs. The migration is NOT");
        console.log("complete until `verify-roles` passes.");
    }

    /// @dev The key whose signature sends the batch, and whose address is the executor the plan is
    ///      staged for. `virtual` so a test can supply one without writing to the process
    ///      environment, matching `SafeProposerBase._proposerPrivateKey`: forge shares one
    ///      environment across a whole run and interleaves suites, which makes an env-var fixture a
    ///      race with every other suite that reads the same name.
    function _signerPrivateKey() internal view virtual returns (uint256) {
        return vm.envUint("PRIVATE_KEY");
    }
}
