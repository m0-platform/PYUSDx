// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Chains } from "./Chains.sol";

/// @title  SafeAppConfig
/// @notice Chain-specific values needed to build a link into the Safe web app that holds a multisig.
/// @dev    A chain belongs here only if some Safe web app serves it. Not necessarily Safe's own --
///         several chain teams and Protofire run their own instances, and a link must point at
///         whichever one holds the Safe.
///
///         Chain IDs come from `Chains` rather than literals so this map cannot name a chain the
///         rest of the repo does not know about.
library SafeAppConfig {
    /// @dev Safe's own multi-chain app. Roster: `https://safe-config.safe.global/api/v1/chains/`.
    string internal constant SAFE_APP_URL = "https://app.safe.global";

    /// @notice Returns the EIP-3770 short name and the base URL of the Safe app serving a chain.
    /// @dev    Returns empty strings for chains no Safe app serves, and never reverts, so callers
    ///         degrade to an alert with no link rather than one with a dead link.
    ///
    ///         Short name and app URL are returned together because a short name is only meaningful
    ///         to the app that issued it; pairing them at one site makes a link pointing at the
    ///         wrong host unrepresentable.
    ///
    ///         Arbitrum Sepolia and Monad Testnet are deployment targets that no Safe app serves,
    ///         so they fall through deliberately.
    function getConfig(uint32 chainId) internal pure returns (string memory shortName, string memory appUrl) {
        // Mainnet
        if (chainId == Chains.ETHEREUM) return ("eth", SAFE_APP_URL);
        if (chainId == Chains.ARBITRUM) return ("arb1", SAFE_APP_URL);
        if (chainId == Chains.MONAD) return ("monad", SAFE_APP_URL);
        if (chainId == Chains.BASE) return ("base", SAFE_APP_URL);

        // Testnet
        if (chainId == Chains.SEPOLIA) return ("sep", SAFE_APP_URL);
        if (chainId == Chains.BASE_SEPOLIA) return ("basesep", SAFE_APP_URL);

        return ("", "");
    }
}
