// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { UlnConfig } from "../config/LayerZeroConfig.sol";

/// @title  IUln302Like
/// @notice Minimal subset of the LayerZero V2 ULN302 message library used to read back the ULN
///         configuration an OApp has explicitly set for a route.
/// @dev    `getAppUlnConfig` returns the OApp's own stored config, unmerged. This is deliberately
///         not `ILayerZeroEndpointV2Like.getConfig`, which returns the *effective* config: for any
///         field the OApp has left unset, the endpoint substitutes the library default. PYUSDX's
///         intended ULN configs are chosen to match the LayerZero defaults on several routes, so an
///         effective read cannot distinguish "pinned by us" from "inherited and not pinned at all",
///         and comparing against it would report a never-configured route as already configured.
interface IUln302Like {
    /// @notice Returns the ULN config the OApp itself has set for a remote endpoint, with no
    ///         default substitution.
    /// @param  oapp      The OApp address (the LayerZeroBridgeAdapter).
    /// @param  remoteEid The remote LayerZero endpoint ID.
    /// @return config    The OApp's stored ULN config; zero-valued when it has never been set.
    function getAppUlnConfig(address oapp, uint32 remoteEid) external view returns (UlnConfig memory config);

    /// @notice Returns the *effective* ULN config for a route: the OApp's own values with the
    ///         library defaults substituted for every field it left unset.
    /// @dev    This is what actually secures the route, and what `ILayerZeroEndpointV2Like.getConfig`
    ///         returns. It is the right read for asserting the security stack that is in force, and
    ///         the wrong read for deciding whether a rerun still has work to do. Note that it also
    ///         normalises `NIL_DVN_COUNT` (255) back to 0.
    /// @param  oapp      The OApp address (the LayerZeroBridgeAdapter).
    /// @param  remoteEid The remote LayerZero endpoint ID.
    /// @return config    The merged ULN config in force for the route.
    function getUlnConfig(address oapp, uint32 remoteEid) external view returns (UlnConfig memory config);
}
