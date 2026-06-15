// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Transaction, TransactionHelper } from "../libraries/TransactionHelper.sol";
import { ConfigurePortalBase } from "./ConfigurePortalBase.sol";

/// @title  ConfigurePortal
/// @notice Broadcasts the Portal + LayerZeroBridgeAdapter wiring for the given peer chains.
/// @dev    The signer (PRIVATE_KEY) must hold OPERATOR_ROLE on the Portal and the adapter.
///         Invoke with `--sig "run(uint32[])" "[<peerChainId>,...]"`.
contract ConfigurePortal is ConfigurePortalBase {
    using TransactionHelper for Transaction[];

    function run(uint32[] memory peerChainIds) external {
        address operator = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        Deployments memory deployment = _readDeployment(block.chainid);

        vm.startBroadcast(operator);

        _configurePeers(deployment.portal, deployment.layerZeroBridgeAdapter, peerChainIds).execute();

        vm.stopBroadcast();
    }
}
