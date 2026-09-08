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

    /// @dev Aggregate of the per-contract config structs above, as laid out in
    ///      `deploymentConfigs/<chainId>/protocol.json`. Loaded by `ScriptBase._parseProtocolConfig`.
    struct ProtocolConfig {
        PYUSDXConfig pyusdx;
        IssuerGatewayConfig issuerGateway;
        SwapFacilityConfig swapFacility;
        FactoryConfig extensionFactory;
        PortalConfig portal;
        LayerZeroBridgeAdapterConfig layerZeroBridgeAdapter;
    }

    /// @dev The `migration` and `portalOFTWrapper` blocks of the same file. Both are read only by the
    ///      role-migration scripts: `DeployAll` reads its keys one by one and therefore ignores them,
    ///      which is what keeps the checked-in configs valid for a deploy that predates either block.
    struct MigrationConfig {
        /// @dev The role holders being migrated away from. Explicit because `AccessControl` here is
        ///      not enumerable, so the chain cannot be asked who currently holds a role.
        address[] outgoingHolders;
        PortalOFTWrapperConfig portalOFTWrapper;
        /// @dev False when the file carries no `portalOFTWrapper` block at all.
        bool hasPortalOFTWrapper;
    }
}
