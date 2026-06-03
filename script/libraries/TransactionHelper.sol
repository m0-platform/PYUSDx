// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

/// @notice A single contract call to be executed (broadcast) or proposed (to a Safe).
struct Transaction {
    address target;
    bytes data;
    uint256 value;
}

/// @title  TransactionHelper
/// @notice Executes batches of `Transaction`s built by the configuration scripts.
/// @dev    The same `Transaction[]` produced by a builder can be broadcast here, or serialized
///         for a Safe multisig by the `Propose*` scripts.
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
}
