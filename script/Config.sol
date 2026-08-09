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
        address rateManager;
        uint128 earnerManagerRateLimitCapacity;
        uint128 earnerManagerRateLimitRefillPerSecond;
    }

    struct IssuerGatewayConfig {
        address admin;
        address operator;
        address executor;
        uint32 mintDelay;
        uint32 mintTTL;
        uint128 rateLimitCapacity;
        uint128 rateLimitRefillPerSecond;
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

    struct AssetCapConfig {
        address asset;
        /// @dev Denominated in the asset's decimals.
        uint256 cap;
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
        address versionManager;
        AssetCapConfig[] assets;
        /// @dev Empty means everyone may call `replaceAsset`.
        address[] replaceAssetWhitelist;
    }

    struct PortalConfig {
        address admin;
        address pauser;
        address operator;
        address fallbackRecipient;
        uint128 rateLimitCapacity;
        uint128 rateLimitRefillPerSecond;
    }

    struct LayerZeroBridgeAdapterConfig {
        address lzEndpoint;
        address admin;
        address operator;
    }

    struct PortalOFTWrapperConfig {
        address admin;
        address operator;
    }
}
