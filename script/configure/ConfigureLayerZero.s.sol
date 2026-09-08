// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { ConfigurationPlan, PlannedAction } from "../libraries/ConfigurationPlan.sol";
import { Transaction, TransactionHelper } from "../libraries/TransactionHelper.sol";
import { ConfigureLayerZeroBase } from "./ConfigureLayerZeroBase.sol";

/// @title  ConfigureLayerZero
/// @notice Broadcasts the LayerZero V2 ULN security config for the given peer chains, sending only
///         the routes the adapter does not already pin.
/// @dev    The signer (PRIVATE_KEY) must be the LayerZeroBridgeAdapter's LayerZero delegate.
///         Invoke with `--sig "run(uint32[])" "[<peerChainId>,...]"`. The planned/skipped breakdown
///         is printed before anything is broadcast; a rerun that changes nothing broadcasts nothing.
///         Set `FORCE_REPLAY=true` to re-send every route regardless of current state.
contract ConfigureLayerZero is ConfigureLayerZeroBase {
    using ConfigurationPlan for PlannedAction[];
    using TransactionHelper for Transaction[];

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
            console.log("Every inspected route is already pinned; nothing broadcast.");
            return;
        }

        address operator = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        vm.startBroadcast(operator);

        transactions.execute();

        vm.stopBroadcast();
    }
}
