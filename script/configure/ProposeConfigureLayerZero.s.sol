// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Transaction } from "../libraries/TransactionHelper.sol";
import { ConfigureLayerZeroBase } from "./ConfigureLayerZeroBase.sol";
import { SafeProposerBase } from "./SafeProposerBase.sol";

/// @title  ProposeConfigureLayerZero
/// @notice Writes the LayerZero ULN `setConfig` calls as a Safe Transaction Builder batch JSON, for
///         execution by the multisig that is the LayerZero delegate. Does not broadcast.
///         Invoke with `--sig "run(uint32[])" "[<peerChainId>,...]"`.
contract ProposeConfigureLayerZero is ConfigureLayerZeroBase, SafeProposerBase {
    function run(uint32[] memory peerChainIds) external {
        Deployments memory deployment = _readDeployment(block.chainid);

        Transaction[] memory transactions = _buildTransactions(
            uint32(block.chainid),
            deployment.layerZeroBridgeAdapter,
            peerChainIds
        );

        _writeSafeBatch("configure-lz-adapter", transactions);
    }
}
