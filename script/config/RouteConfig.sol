// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Chains } from "./Chains.sol";

/// @title  RouteConfig
/// @notice Per-destination Portal routing parameters.
library RouteConfig {
    /// @dev Gas budget for executing an inbound `TokenTransfer` payload on the destination chain.
    ///      Sized for the heaviest path — mint PYUSDX then wrap into a PYUSDX Extension via the
    ///      SwapFacility — measured at ~331k for a YieldToOne wrap on a mainnet fork (a direct PYUSDX
    ///      mint is ~127k). The 500k budget adds margin for storage-warmth variability and other
    ///      extension types. See test/integration/PayloadGasLimitIntegration.t.sol.
    uint256 internal constant DEFAULT_PAYLOAD_GAS_LIMIT = 500_000;

    /// @notice Returns the payload gas limit to set on the Portal for a destination chain.
    /// @param  destinationChainId The destination chain ID.
    /// @return The gas limit for destination-side payload execution.
    function getPayloadGasLimit(uint32 destinationChainId) internal pure returns (uint256) {
        if (destinationChainId == Chains.ETHEREUM) return DEFAULT_PAYLOAD_GAS_LIMIT;
        if (destinationChainId == Chains.ARBITRUM) return DEFAULT_PAYLOAD_GAS_LIMIT;
        if (destinationChainId == Chains.SEPOLIA) return DEFAULT_PAYLOAD_GAS_LIMIT;
        if (destinationChainId == Chains.ARBITRUM_SEPOLIA) return DEFAULT_PAYLOAD_GAS_LIMIT;
        if (destinationChainId == Chains.MONAD_TESTNET) return DEFAULT_PAYLOAD_GAS_LIMIT;
        if (destinationChainId == Chains.MONAD_MAINNET) return DEFAULT_PAYLOAD_GAS_LIMIT;

        revert Chains.UnsupportedChain(destinationChainId);
    }
}
