// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { ConfigurationPlan, PlannedAction } from "../libraries/ConfigurationPlan.sol";
import { Transaction } from "../libraries/TransactionHelper.sol";
import { ConfigurePortalBase } from "./ConfigurePortalBase.sol";
import { SafeProposerBase } from "./SafeProposerBase.sol";

/// @title  ProposeConfigurePortal
/// @notice Writes the Portal + adapter wiring as a Safe Transaction Builder batch JSON, for execution
///         by the multisig holding OPERATOR_ROLE. Does not broadcast.
///         Invoke with `--sig "run(uint32[])" "[<peerChainId>,...]"`.
/// @dev    The batch carries the same transactions `ConfigurePortal` would broadcast: both compact
///         the plan built by `ConfigurePortalBase._planPeers`. The planned/skipped breakdown is
///         printed before the batch is written, and a rerun that changes nothing writes no batch at
///         all rather than proposing an empty one. Set `FORCE_REPLAY=true` to propose every setting
///         regardless of current state.
contract ProposeConfigurePortal is ConfigurePortalBase, SafeProposerBase {
    using ConfigurationPlan for PlannedAction[];

    function run(uint32[] memory peerChainIds) external {
        Deployments memory deployment = _readDeployment(block.chainid);

        PlannedAction[] memory plan = _planPeers(deployment.portal, deployment.layerZeroBridgeAdapter, peerChainIds);

        plan.log(string.concat("Portal configuration plan (chain ", vm.toString(block.chainid), "):"));

        Transaction[] memory transactions = plan.compact();

        if (transactions.length == 0) {
            console.log("Every inspected setting is already applied; no Safe batch written.");
            console.log("Any existing export from an earlier run is stale; do not import it for this run.");
            return;
        }

        _writeSafeBatch("configure-portal", transactions);
    }
}
