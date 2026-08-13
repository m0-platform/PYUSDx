// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

/// @title  Chains
/// @notice Canonical chain IDs for the networks PYUSDX is deployed to.
library Chains {
    uint32 internal constant ETHEREUM = 1;

    uint32 internal constant ARBITRUM = 42161;

    uint32 internal constant MONAD = 143;

    uint32 internal constant SEPOLIA = 11155111;

    uint32 internal constant ARBITRUM_SEPOLIA = 421614;

    uint32 internal constant MONAD_TESTNET = 10143;

    /// @notice Thrown when a chain ID has no configuration registered.
    error UnsupportedChain(uint32 chainId);
}
