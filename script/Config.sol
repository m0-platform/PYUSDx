// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

contract Config {
    error UnsupportedChain(uint256 chainId);

    struct PYUSDXConfig {
        string name;
        string symbol;
        address admin;
        address pauser;
        address freezeManager;
        address forcedTransferManager;
        address earnerManager;
    }

    struct IssuerGatewayConfig {
        address admin;
        address minter;
        address rateLimitManager;
        uint32 mintDelay;
        uint32 mintTTL;
    }

    struct SwapFacilityConfig {
        address admin;
        address pauser;
    }

    struct FactoryConfig {
        address admin;
        address factoryManager;
    }

    struct YieldToOneConfig {
        string name;
        string symbol;
        address yieldRecipient;
        address admin;
        address freezeManager;
        address yieldRecipientManager;
        address pauser;
    }

    struct MultiMintConfig {
        string name;
        string symbol;
        address yieldRecipient;
        address admin;
        address assetCapManager;
        address freezeManager;
        address pauser;
        address yieldRecipientManager;
    }
}
