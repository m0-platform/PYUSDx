// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { SafeProposerBase } from "../../script/configure/SafeProposerBase.sol";
import { Transaction } from "../../script/libraries/TransactionHelper.sol";

/// @notice Exposes SafeProposerBase's internal batch writer for unit testing.
contract SafeProposerHarness is SafeProposerBase {
    function writeSafeBatch(string memory name, Transaction[] memory transactions) external {
        _writeSafeBatch(name, transactions);
    }
}
