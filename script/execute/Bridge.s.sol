// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { TypeConverter } from "../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IPortal } from "../../src/portal/interfaces/IPortal.sol";

import { ScriptBase } from "../ScriptBase.s.sol";

/// @notice Thrown when the Portal on the source chain carries a zero address in its deployment record.
error PortalNotDeployed(uint32 chainId);

/// @notice Thrown when PYUSDX on the source chain carries a zero address in its deployment record.
error SourceTokenNotDeployed(uint32 chainId);

/// @notice Thrown when PYUSDX on the destination chain carries a zero address in its deployment record.
error DestinationTokenNotDeployed(uint32 destinationChainId);

/// @title  Bridge
/// @notice Bridges PYUSDX to a destination chain via the PYUSDX Portal using the default bridge adapter.
/// @dev    The signer (PRIVATE_KEY) must hold the bridged PYUSDX and enough native gas for the fee.
///         Invoke with `--sig "run(uint32,uint256,address)" <destinationChainId> <amount> <recipient>`,
///         where `recipient = address(0)` defaults to the signer.
contract Bridge is ScriptBase {
    using TypeConverter for address;

    function run(uint32 destinationChainId, uint256 amount, address recipient) external {
        address signer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        Deployments memory source = _readDeployment(block.chainid);
        if (source.portal == address(0)) revert PortalNotDeployed(uint32(block.chainid));
        if (source.pyusdx == address(0)) revert SourceTokenNotDeployed(uint32(block.chainid));

        address destinationToken = _readDeployment(destinationChainId).pyusdx;
        if (destinationToken == address(0)) revert DestinationTokenNotDeployed(destinationChainId);

        address effectiveRecipient = recipient == address(0) ? signer : recipient;

        uint256 fee = IPortal(source.portal).quote(destinationChainId);

        vm.startBroadcast(signer);

        if (IERC20(source.pyusdx).allowance(signer, source.portal) < amount) {
            IERC20(source.pyusdx).approve(source.portal, amount);
        }

        IPortal(source.portal).sendToken{ value: fee }(
            amount,
            source.pyusdx,
            destinationChainId,
            destinationToken.toBytes32(),
            effectiveRecipient.toBytes32(),
            signer.toBytes32()
        );

        vm.stopBroadcast();
    }
}
