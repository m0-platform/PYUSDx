// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

/// @notice LayerZero V2 message-library (ULN) configuration parameter.
struct SetConfigParam {
    uint32 eid;
    uint32 configType;
    bytes config;
}

/// @title  ILayerZeroEndpointV2Like
/// @notice Minimal subset of the LayerZero V2 Endpoint used by the configuration scripts to set and
///         read message-library (ULN) configuration.
/// @dev    Kept local to `script/` so the deployed `ILayerZeroEndpointV2` interface is not modified.
interface ILayerZeroEndpointV2Like {
    /// @notice Sets message library configuration for an OApp (e.g. ULN config).
    /// @param  oapp   The OApp address to configure.
    /// @param  lib    The message library to configure (send or receive library).
    /// @param  params The configuration parameters.
    function setConfig(address oapp, address lib, SetConfigParam[] calldata params) external;

    /// @notice Returns the send library used by an OApp for a destination endpoint.
    /// @param  sender The OApp address.
    /// @param  dstEid The destination endpoint ID.
    /// @return lib    The send library address.
    function getSendLibrary(address sender, uint32 dstEid) external view returns (address lib);

    /// @notice Returns the receive library used by an OApp for a source endpoint.
    /// @param  receiver  The OApp address.
    /// @param  srcEid    The source endpoint ID.
    /// @return lib       The receive library address.
    /// @return isDefault Whether the returned library is the endpoint default.
    function getReceiveLibrary(address receiver, uint32 srcEid) external view returns (address lib, bool isDefault);
}
