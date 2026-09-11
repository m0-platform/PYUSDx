// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { DeployBase } from "./DeployBase.s.sol";

/// @title  DeployAll
/// @notice Deploys the full PYUSDX core stack (PYUSDX, IssuerGateway, SwapFacility, both extension
///         beacons, ExtensionFactory, Portal, LayerZeroBridgeAdapter) and records the resulting
///         addresses in `deployments/<chainid>.json`.
/// @dev    Protocol configuration is read from `deploymentConfigs/<chainid>/protocol.json` (schema in
///         deploymentConfigs/README.md), overridable via PROTOCOL_CONFIG. PRIVATE_KEY stays in the
///         secret workflow (`op run`) and is the only credential read directly by this entry point.
contract DeployAll is DeployBase {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        console.log("Deployer:", deployer);

        ProtocolConfig memory config = _readProtocolConfig(block.chainid);

        _logProtocolConfig(config);

        vm.startBroadcast(deployer);

        CoreDeployments memory deployment = _deployCore(
            deployer,
            config.pyusdx,
            config.issuerGateway,
            config.swapFacility,
            config.extensionFactory,
            config.portal,
            config.layerZeroBridgeAdapter
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
        _writeDeployment(block.chainid, "yieldToOneBeacon", deployment.yieldToOneBeaconProxy);
        _writeDeployment(block.chainid, "multiMintBeacon", deployment.multiMintBeaconProxy);
    }

    /* ============ Logging ============ */

    /// @dev Echoes every deployment input so a dry run shows exactly what a broadcast would use.
    function _logProtocolConfig(ProtocolConfig memory config) internal pure {
        console.log("---------------------------- protocol config ----------------------------");
        console.log("PYUSDX name / symbol:              ", config.pyusdx.name, "/", config.pyusdx.symbol);
        console.log("PYUSDX admin:                      ", config.pyusdx.admin);
        console.log("PYUSDX pauser:                     ", config.pyusdx.pauser);
        console.log("PYUSDX freezeManager:              ", config.pyusdx.freezeManager);
        console.log("PYUSDX forcedTransferManager:      ", config.pyusdx.forcedTransferManager);
        console.log("PYUSDX earnerManager:              ", config.pyusdx.earnerManager);
        console.log("PYUSDX rateManager:                ", config.pyusdx.rateManager);
        console.log(
            "PYUSDX earnerManager rate limit:   ",
            config.pyusdx.earnerManagerRateLimitCapacity,
            "@",
            config.pyusdx.earnerManagerRateLimitRefillPerSecond
        );
        console.log("IssuerGateway admin:               ", config.issuerGateway.admin);
        console.log("IssuerGateway operator:            ", config.issuerGateway.operator);
        console.log("IssuerGateway executor:            ", config.issuerGateway.executor);
        console.log(
            "IssuerGateway mintDelay / mintTTL: ",
            config.issuerGateway.mintDelay,
            "/",
            config.issuerGateway.mintTTL
        );
        console.log(
            "IssuerGateway rate limit:          ",
            config.issuerGateway.rateLimitCapacity,
            "@",
            config.issuerGateway.rateLimitRefillPerSecond
        );
        console.log("SwapFacility admin:                ", config.swapFacility.admin);
        console.log("SwapFacility pauser:               ", config.swapFacility.pauser);
        console.log("ExtensionFactory admin:            ", config.extensionFactory.admin);
        console.log("ExtensionFactory factoryManager:   ", config.extensionFactory.factoryManager);
        console.log("Portal admin:                      ", config.portal.admin);
        console.log("Portal pauser:                     ", config.portal.pauser);
        console.log("Portal operator:                   ", config.portal.operator);
        console.log("Portal fallbackRecipient:          ", config.portal.fallbackRecipient);
        console.log(
            "Portal rate limit:                 ",
            config.portal.rateLimitCapacity,
            "@",
            config.portal.rateLimitRefillPerSecond
        );
        console.log("LayerZero endpoint:                ", config.layerZeroBridgeAdapter.lzEndpoint);
        console.log("LayerZeroBridgeAdapter admin:      ", config.layerZeroBridgeAdapter.admin);
        console.log("LayerZeroBridgeAdapter operator:   ", config.layerZeroBridgeAdapter.operator);
        console.log("-------------------------------------------------------------------------");
    }
}
