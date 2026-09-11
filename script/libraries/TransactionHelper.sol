// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Safe } from "../../lib/safe-utils/src/Safe.sol";

/// @notice A single contract call to be executed (broadcast) or proposed (to a Safe).
struct Transaction {
    address target;
    bytes data;
    uint256 value;
}

/// @notice Thrown when a transaction carrying value would be proposed to a Safe.
/// @dev    `Safe.getProposeTransactionsTargetAndData` packs every call in a batch at zero value, so
///         a non-zero one would be queued as something other than what the offline export shows.
///         Every configuration call this repo proposes is value-free; this exists so that stops
///         being true loudly rather than silently.
error ProposalValueNotSupported(uint256 index, uint256 value);

/// @title  TransactionHelper
/// @notice Executes batches of `Transaction`s built by the configuration scripts, or hands them to
///         `lib/safe-utils` to be queued on the Safe transaction service.
/// @dev    The same `Transaction[]` produced by a builder can be broadcast here, or serialized
///         for a Safe multisig by the `Propose*` scripts.
///
///         `propose` mirrors `evm-m-suite-deployment/src/libraries/TransactionHelper.sol`: it only
///         reshapes a `Transaction[]` into the parallel arrays `Safe.proposeTransactions` takes.
///         Nonce handling, `MultiSend` packing, signing and the HTTP request all belong to
///         `safe-utils` and are deliberately not reimplemented here.
library TransactionHelper {
    /// @notice Executes a single transaction, bubbling up the revert reason on failure.
    function execute(Transaction memory transaction) internal {
        (bool success, bytes memory returnData) = transaction.target.call{ value: transaction.value }(transaction.data);

        if (!success) {
            // Propagate the underlying revert reason from the failed call.
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }

    /// @notice Executes a batch of transactions in order.
    function execute(Transaction[] memory transactions) internal {
        for (uint256 i; i < transactions.length; ++i) {
            execute(transactions[i]);
        }
    }

    /// @notice Queues the batch on the Safe transaction service as one `MultiSend` transaction.
    /// @dev    Reverts unless the service answers 2xx, so a caller reaching the next statement has a
    ///         proposal that exists on the Safe side.
    /// @return safeTxHash The digest the Safe's signers will be asked to sign.
    function propose(
        Transaction[] memory transactions,
        Safe.Client storage safeClient,
        address safe,
        address sender
    ) internal returns (bytes32 safeTxHash) {
        Safe.initialize(safeClient, safe);

        address[] memory targets = new address[](transactions.length);
        bytes[] memory datas = new bytes[](transactions.length);

        for (uint256 i; i < transactions.length; ++i) {
            if (transactions[i].value != 0) revert ProposalValueNotSupported(i, transactions[i].value);

            targets[i] = transactions[i].target;
            datas[i] = transactions[i].data;
        }

        return Safe.proposeTransactions(safeClient, targets, datas, sender, "");
    }
}
