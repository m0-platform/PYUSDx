// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { ConfigurationPlan, PlannedAction } from "../libraries/ConfigurationPlan.sol";
import { Transaction, TransactionHelper } from "../libraries/TransactionHelper.sol";
import { ConfigurePortalBase } from "./ConfigurePortalBase.sol";

/// @title  ConfigurePortal
/// @notice Broadcasts the Portal + LayerZeroBridgeAdapter wiring for the given peer chains, sending
///         only the settings the chain does not already carry.
/// @dev    The signer (PRIVATE_KEY) must hold OPERATOR_ROLE on the Portal and the adapter.
///         Invoke with `--sig "run(uint32[])" "[<peerChainId>,...]"`. The planned/skipped breakdown
///         is printed before anything is broadcast; a rerun that changes nothing broadcasts nothing.
///         Set `FORCE_REPLAY=true` to re-send every setting regardless of current state.
contract ConfigurePortal is ConfigurePortalBase {
    using ConfigurationPlan for PlannedAction[];
    using TransactionHelper for Transaction[];

    function run(uint32[] memory peerChainIds) external {
        Deployments memory deployment = _readDeployment(block.chainid);

        PlannedAction[] memory plan = _planPeers(deployment.portal, deployment.layerZeroBridgeAdapter, peerChainIds);

        plan.log(string.concat("Portal configuration plan (chain ", vm.toString(block.chainid), "):"));

        Transaction[] memory transactions = plan.compact();

        if (transactions.length == 0) {
            console.log("Every inspected setting is already applied; nothing broadcast.");
            return;
        }

        address operator = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        vm.startBroadcast(operator);

        transactions.execute();

        vm.stopBroadcast();
    }
}
