// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { Transaction } from "../libraries/TransactionHelper.sol";
import { ScriptBase } from "../ScriptBase.s.sol";

/// @notice Thrown when a Safe batch would be written with no transactions, which would otherwise
///         report success for work that was never proposed.
error EmptyTransactionBatch();

/// @title  SafeProposerBase
/// @notice Serializes a `Transaction[]` into a Safe Transaction Builder batch JSON that a signer
///         imports into the Safe UI. Used by the `Propose*` configuration scripts so the wiring can
///         be executed by a multisig instead of broadcast directly.
/// @dev    Output is written to `safe/<chainid>-<name>.json` (allowed by `fs_permissions`).
abstract contract SafeProposerBase is ScriptBase {
    function _writeSafeBatch(string memory name, Transaction[] memory transactions) internal {
        if (transactions.length == 0) revert EmptyTransactionBatch();

        string memory dir = string.concat(vm.projectRoot(), "/safe");
        vm.createDir(dir, true);

        string memory transactionsJson = "[";

        for (uint256 i; i < transactions.length; ++i) {
            if (i > 0) transactionsJson = string.concat(transactionsJson, ",");

            transactionsJson = string.concat(
                transactionsJson,
                '{"to":"',
                vm.toString(transactions[i].target),
                '","value":"',
                vm.toString(transactions[i].value),
                '","data":"',
                vm.toString(transactions[i].data),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        transactionsJson = string.concat(transactionsJson, "]");

        string memory json = string.concat(
            '{"version":"1.0","chainId":"',
            vm.toString(block.chainid),
            '","createdAt":',
            vm.toString(block.timestamp),
            ',"meta":{"name":"',
            name,
            '","txBuilderVersion":"1.16.5"},"transactions":',
            transactionsJson,
            "}"
        );

        string memory path = string.concat(dir, "/", vm.toString(block.chainid), "-", name, ".json");
        vm.writeFile(path, json);

        console.log("Safe batch (%s transactions) written to:", transactions.length);
        console.log(path);
    }
}
