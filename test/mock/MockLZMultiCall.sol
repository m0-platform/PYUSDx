// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Models LayerZero's LZMultiCall: executes arbitrary calls atomically, so the
///         TransferDelegate pre-push and the OFT `send` happen in one transaction and
///         roll back together. In production the OFT sees this contract as `msg.sender`.
contract MockLZMultiCall {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function multicall(Call[] calldata calls) external payable {
        for (uint256 i; i < calls.length; i++) {
            (bool success, bytes memory returnData) = calls[i].target.call{ value: calls[i].value }(calls[i].data);

            // Bubble up the inner revert data so callers observe the original error.
            if (!success) {
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }

    receive() external payable {}
}
