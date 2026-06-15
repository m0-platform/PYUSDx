// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Transaction, TransactionHelper } from "../libraries/TransactionHelper.sol";
import { ConfigureLayerZeroBase } from "./ConfigureLayerZeroBase.sol";

/// @title  ConfigureLayerZero
/// @notice Broadcasts the LayerZero V2 ULN security config for the given peer chains.
/// @dev    The signer (PRIVATE_KEY) must be the LayerZeroBridgeAdapter's LayerZero delegate.
///         Invoke with `--sig "run(uint32[])" "[<peerChainId>,...]"`.
contract ConfigureLayerZero is ConfigureLayerZeroBase {
    using TransactionHelper for Transaction[];

    function run(uint32[] memory peerChainIds) external {
        address operator = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        Deployments memory deployment = _readDeployment(block.chainid);

        vm.startBroadcast(operator);

        _buildTransactions(uint32(block.chainid), deployment.layerZeroBridgeAdapter, peerChainIds).execute();

        vm.stopBroadcast();
    }
}
