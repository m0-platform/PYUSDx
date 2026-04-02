// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.34;

import { IBridgeAdapter } from "../../../interfaces/IBridgeAdapter.sol";
import { ILayerZeroReceiver } from "./ILayerZeroReceiver.sol";

/// @title  ILayerZeroBridgeAdapter interface.
/// @author M0 Labs
/// @notice Defines interface specific to LayerZero Bridge Adapter.
interface ILayerZeroBridgeAdapter is IBridgeAdapter, ILayerZeroReceiver {
    /* ============ Custom Errors ============ */

    /// @notice Thrown when the LayerZero Endpoint address is 0x0.
    error ZeroEndpoint();

    /// @notice Thrown when the caller is not the LayerZero Endpoint.
    error NotEndpoint();

    /* ============ View/Pure Functions ============ */

    /// @notice Returns the address of the LayerZero Endpoint contract.
    function endpoint() external view returns (address);

    /* ============ Interactive Functions ============ */

    /// @notice Sets the delegate authorized to configure LayerZero settings on the Endpoint.
    /// @param  delegate The address to grant delegate permissions.
    function setDelegate(address delegate) external;
}
