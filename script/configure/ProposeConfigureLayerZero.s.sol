// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { ConfigurationPlan, PlannedAction } from "../libraries/ConfigurationPlan.sol";
import { Transaction } from "../libraries/TransactionHelper.sol";
import { ConfigureLayerZeroBase } from "./ConfigureLayerZeroBase.sol";
import { SafeProposerBase } from "./SafeProposerBase.sol";

/// @title  ProposeConfigureLayerZero
/// @notice Writes the LayerZero ULN `setConfig` calls as a Safe Transaction Builder batch JSON, for
///         execution by the multisig that is the LayerZero delegate. Does not broadcast.
///         Invoke with `--sig "run(uint32[])" "[<peerChainId>,...]"`.
/// @dev    The batch carries the same transactions `ConfigureLayerZero` would broadcast: both compact
///         the plan built by `ConfigureLayerZeroBase._planPeers`. The planned/skipped breakdown is
///         printed before the batch is written, and a rerun that changes nothing writes no batch at
///         all rather than proposing an empty one. Set `FORCE_REPLAY=true` to propose every route
///         regardless of current state.
contract ProposeConfigureLayerZero is ConfigureLayerZeroBase, SafeProposerBase {
    using ConfigurationPlan for PlannedAction[];

    function run(uint32[] memory peerChainIds) external {
        Deployments memory deployment = _readDeployment(block.chainid);

        PlannedAction[] memory plan = _planPeers(
            uint32(block.chainid),
            deployment.layerZeroBridgeAdapter,
            peerChainIds
        );

        plan.log(string.concat("LayerZero ULN configuration plan (chain ", vm.toString(block.chainid), "):"));

        Transaction[] memory transactions = plan.compact();

        if (transactions.length == 0) {
            console.log("Every inspected route is already pinned; no Safe batch written.");
            console.log("Any existing export from an earlier run is stale; do not import it for this run.");
            return;
        }

        _writeSafeBatch("configure-lz-adapter", transactions);
    }
}
