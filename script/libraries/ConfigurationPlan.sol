// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { Transaction } from "./TransactionHelper.sol";

/// @notice One intended configuration setting, paired with whether the chain already carries it.
/// @dev    `applied == true` means the current on-chain state already matches `transaction`, so the
///         call is dropped from the batch that is broadcast or proposed. Builders that cannot read
///         the current state (no code at the target, an unexpected return shape) leave `applied`
///         false, so an unreadable setting is re-sent rather than silently skipped.
struct PlannedAction {
    Transaction transaction;
    string description;
    bool applied;
}

/// @title  ConfigurationPlan
/// @notice Compacts a configuration plan down to the transactions that still need to be sent, and
///         prints the planned/skipped breakdown before anything is broadcast or proposed.
/// @dev    Shared by the Portal and LayerZero configuration builders so direct execution and Safe
///         proposals compact and report identically.
library ConfigurationPlan {
    /// @notice Returns only the transactions whose setting is not already applied on chain.
    function compact(PlannedAction[] memory actions) internal pure returns (Transaction[] memory transactions) {
        transactions = new Transaction[](plannedCount(actions));

        uint256 txCount;

        for (uint256 i; i < actions.length; ++i) {
            if (!actions[i].applied) transactions[txCount++] = actions[i].transaction;
        }
    }

    /// @notice Returns the number of settings that still need a transaction.
    function plannedCount(PlannedAction[] memory actions) internal pure returns (uint256 count) {
        for (uint256 i; i < actions.length; ++i) {
            if (!actions[i].applied) ++count;
        }
    }

    /// @notice Returns the number of settings the chain already carries.
    function skippedCount(PlannedAction[] memory actions) internal pure returns (uint256) {
        return actions.length - plannedCount(actions);
    }

    /// @notice Prints every setting as either planned or skipped, followed by a one-line summary.
    /// @dev    Called before the batch is broadcast or written, so a rerun shows what it decided to
    ///         drop and why the resulting batch is smaller than the peer list implies.
    function log(PlannedAction[] memory actions, string memory title) internal pure {
        console.log(title);

        for (uint256 i; i < actions.length; ++i) {
            console.log(string.concat(actions[i].applied ? "  [skip] " : "  [plan] ", actions[i].description));
        }

        console.log(
            "  planned / already applied / inspected:",
            plannedCount(actions),
            skippedCount(actions),
            actions.length
        );
    }
}
