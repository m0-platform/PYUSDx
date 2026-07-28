// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Models LayerZero's single-purpose TransferDelegate: the only contract users grant
///         token allowance to in the Value Transfer API flow. It can move tokens and nothing else.
contract MockTransferDelegate {
    function delegateTransferFrom(address token, address from, address to, uint256 amount) external {
        IERC20(token).transferFrom(from, to, amount);
    }
}
