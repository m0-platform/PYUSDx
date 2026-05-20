// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { DeployBase } from "./DeployBase.s.sol";

contract DeployAll is DeployBase {
    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        PYUSDXConfig memory pyusdxConfig = _loadPYUSDXConfig();
        IssuerGatewayConfig memory issuerGatewayConfig = _loadIssuerGatewayConfig();
        SwapFacilityConfig memory swapConfig = _loadSwapFacilityConfig();
        FactoryConfig memory factoryConfig = _loadFactoryConfig();
        PortalConfig memory portalConfig = _loadPortalConfig();
        LayerZeroBridgeAdapterConfig memory layerZeroBridgeAdapterConfig = _loadLayerZeroBridgeAdapterConfig();

        vm.startBroadcast(deployer);

        CoreDeployments memory deployment = _deployCore(
            deployer,
            pyusdxConfig,
            issuerGatewayConfig,
            swapConfig,
            factoryConfig,
            portalConfig,
            layerZeroBridgeAdapterConfig
        );

        vm.stopBroadcast();

        console.log("================================================================================");
        console.log("PYUSDX Proxy:                     ", deployment.pyusdxProxy);
        console.log("PYUSDX ProxyAdmin:                ", deployment.pyusdxProxyAdmin);
        console.log("PYUSDX Implementation:            ", deployment.pyusdxImplementation);
        console.log("IssuerGateway Proxy:              ", deployment.issuerGatewayProxy);
        console.log("IssuerGateway ProxyAdmin:         ", deployment.issuerGatewayProxyAdmin);
        console.log("IssuerGateway Implementation:     ", deployment.issuerGatewayImplementation);
        console.log("SwapFacility Proxy:               ", deployment.swapFacilityProxy);
        console.log("SwapFacility ProxyAdmin:          ", deployment.swapFacilityProxyAdmin);
        console.log("SwapFacility Implementation:      ", deployment.swapFacilityImplementation);
        console.log("YieldToOne Beacon Proxy:                 ", deployment.yieldToOneBeaconProxy);
        console.log("YieldToOne Beacon ProxyAdmin:            ", deployment.yieldToOneBeaconProxyAdmin);
        console.log("YieldToOne Beacon Implementation:        ", deployment.yieldToOneBeaconImplementation);
        console.log("MultiMint Beacon Proxy:                  ", deployment.multiMintBeaconProxy);
        console.log("MultiMint Beacon ProxyAdmin:             ", deployment.multiMintBeaconProxyAdmin);
        console.log("MultiMint Beacon Implementation:         ", deployment.multiMintBeaconImplementation);
        console.log("Factory Proxy:                    ", deployment.factoryProxy);
        console.log("Factory ProxyAdmin:               ", deployment.factoryProxyAdmin);
        console.log("Factory Implementation:           ", deployment.factoryImplementation);
        console.log("Portal Proxy:                     ", deployment.portalProxy);
        console.log("Portal ProxyAdmin:                ", deployment.portalProxyAdmin);
        console.log("Portal Implementation:            ", deployment.portalImplementation);
        console.log("LayerZeroBridgeAdapter Proxy:     ", deployment.layerZeroBridgeAdapterProxy);
        console.log("LayerZeroBridgeAdapter ProxyAdmin:", deployment.layerZeroBridgeAdapterProxyAdmin);
        console.log("LayerZeroBridgeAdapter Impl:      ", deployment.layerZeroBridgeAdapterImplementation);
        console.log("================================================================================");

        _writeDeployment(block.chainid, "pyusdx", deployment.pyusdxProxy);
        _writeDeployment(block.chainid, "issuerGateway", deployment.issuerGatewayProxy);
        _writeDeployment(block.chainid, "swapFacility", deployment.swapFacilityProxy);
        _writeDeployment(block.chainid, "extensionFactory", deployment.factoryProxy);
        _writeDeployment(block.chainid, "portal", deployment.portalProxy);
        _writeDeployment(block.chainid, "layerZeroBridgeAdapter", deployment.layerZeroBridgeAdapterProxy);
    }

    function _loadPYUSDXConfig() private view returns (PYUSDXConfig memory config) {
        config.name = vm.envString("PYUSDX_NAME");
        config.symbol = vm.envString("PYUSDX_SYMBOL");
        require(bytes(config.name).length != 0, "PYUSDX_NAME must be set");
        require(bytes(config.symbol).length != 0, "PYUSDX_SYMBOL must be set");
        config.admin = vm.envAddress("PYUSDX_ADMIN");
        config.pauser = vm.envAddress("PYUSDX_PAUSER");
        config.freezeManager = vm.envAddress("PYUSDX_FREEZE_MANAGER");
        config.forcedTransferManager = vm.envAddress("PYUSDX_FORCED_TRANSFER_MANAGER");
        config.earnerManager = vm.envAddress("PYUSDX_EARNER_MANAGER");
        config.rateManager = vm.envAddress("PYUSDX_RATE_MANAGER");
    }

    function _loadIssuerGatewayConfig() private view returns (IssuerGatewayConfig memory config) {
        config.admin = vm.envAddress("ISSUER_GATEWAY_ADMIN");
        config.operator = vm.envAddress("ISSUER_GATEWAY_OPERATOR");
        config.executor = vm.envAddress("ISSUER_GATEWAY_EXECUTOR");
        config.mintDelay = uint32(vm.envUint("ISSUER_GATEWAY_MINT_DELAY"));
        config.mintTTL = uint32(vm.envUint("ISSUER_GATEWAY_MINT_TTL"));
        config.rateLimitCapacity = uint128(vm.envUint("ISSUER_GATEWAY_RATE_LIMIT_CAPACITY"));
        config.rateLimitRefillPerSecond = uint128(vm.envUint("ISSUER_GATEWAY_RATE_LIMIT_REFILL"));
    }

    function _loadSwapFacilityConfig() private view returns (SwapFacilityConfig memory config) {
        config.admin = vm.envAddress("SWAP_FACILITY_ADMIN");
        config.pauser = vm.envAddress("SWAP_FACILITY_PAUSER");
    }

    function _loadFactoryConfig() private view returns (FactoryConfig memory config) {
        config.admin = vm.envAddress("FACTORY_ADMIN");
        config.factoryManager = vm.envAddress("FACTORY_MANAGER");
    }

    function _loadPortalConfig() private view returns (PortalConfig memory config) {
        config.admin = vm.envAddress("PORTAL_ADMIN");
        config.pauser = vm.envAddress("PORTAL_PAUSER");
        config.operator = vm.envAddress("PORTAL_OPERATOR");
        config.fallbackRecipient = vm.envAddress("PORTAL_FALLBACK_RECIPIENT");
        require(config.fallbackRecipient != address(0), "PORTAL_FALLBACK_RECIPIENT must be set");
        config.rateLimitCapacity = uint128(vm.envUint("PORTAL_RATE_LIMIT_CAPACITY"));
        config.rateLimitRefillPerSecond = uint128(vm.envUint("PORTAL_RATE_LIMIT_REFILL"));
    }

    function _loadLayerZeroBridgeAdapterConfig() private view returns (LayerZeroBridgeAdapterConfig memory config) {
        config.lzEndpoint = vm.envAddress("LAYER_ZERO_ENDPOINT");
        config.admin = vm.envAddress("LAYER_ZERO_BRIDGE_ADAPTER_ADMIN");
        config.operator = vm.envAddress("LAYER_ZERO_BRIDGE_ADAPTER_OPERATOR");
    }
}
