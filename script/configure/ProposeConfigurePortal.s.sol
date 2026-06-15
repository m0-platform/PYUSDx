// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Transaction } from "../libraries/TransactionHelper.sol";
import { ConfigurePortalBase } from "./ConfigurePortalBase.sol";
import { SafeProposerBase } from "./SafeProposerBase.sol";

/// @title  ProposeConfigurePortal
/// @notice Writes the Portal + adapter wiring as a Safe Transaction Builder batch JSON, for execution
///         by the multisig holding OPERATOR_ROLE. Does not broadcast.
///         Invoke with `--sig "run(uint32[])" "[<peerChainId>,...]"`.
contract ProposeConfigurePortal is ConfigurePortalBase, SafeProposerBase {
    function run(uint32[] memory peerChainIds) external {
        Deployments memory deployment = _readDeployment(block.chainid);

        Transaction[] memory transactions = _configurePeers(
            deployment.portal,
            deployment.layerZeroBridgeAdapter,
            peerChainIds
        );

        _writeSafeBatch("configure-portal", transactions);
    }
}
