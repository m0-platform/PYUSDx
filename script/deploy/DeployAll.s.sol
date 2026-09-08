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
    /// @dev Aggregate of the per-contract config structs declared in `script/Config.sol`.
    struct ProtocolConfig {
        PYUSDXConfig pyusdx;
        IssuerGatewayConfig issuerGateway;
        SwapFacilityConfig swapFacility;
        FactoryConfig extensionFactory;
        PortalConfig portal;
        LayerZeroBridgeAdapterConfig layerZeroBridgeAdapter;
    }

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

    /* ============ Config Loading ============ */

    function _protocolConfigPath(uint256 chainId) internal view returns (string memory) {
        string memory overridePath = vm.envOr("PROTOCOL_CONFIG", string(""));
        if (bytes(overridePath).length != 0) return overridePath;

        return string.concat(vm.projectRoot(), "/deploymentConfigs/", vm.toString(chainId), "/protocol.json");
    }

    function _readProtocolConfig(uint256 chainId) internal view returns (ProtocolConfig memory) {
        string memory path = _protocolConfigPath(chainId);
        require(
            vm.isFile(path),
            string.concat(
                "missing protocol config file (see deploymentConfigs/README.md#deployment-configuration): ",
                path
            )
        );

        console.log("Config file:", path);

        return _parseProtocolConfig(vm.readFile(path), chainId);
    }

    /// @dev `chainId` is passed in rather than read from `block.chainid` so the guard is testable.
    function _parseProtocolConfig(
        string memory json,
        uint256 chainId
    ) internal pure returns (ProtocolConfig memory config) {
        require(vm.parseJsonUint(json, ".chainId") == chainId, "config chainId does not match the target chain");

        config.pyusdx = PYUSDXConfig({
            name: vm.parseJsonString(json, ".pyusdx.name"),
            symbol: vm.parseJsonString(json, ".pyusdx.symbol"),
            admin: vm.parseJsonAddress(json, ".pyusdx.admin"),
            pauser: vm.parseJsonAddress(json, ".pyusdx.pauser"),
            freezeManager: vm.parseJsonAddress(json, ".pyusdx.freezeManager"),
            forcedTransferManager: vm.parseJsonAddress(json, ".pyusdx.forcedTransferManager"),
            earnerManager: vm.parseJsonAddress(json, ".pyusdx.earnerManager"),
            rateManager: vm.parseJsonAddress(json, ".pyusdx.rateManager"),
            earnerManagerRateLimitCapacity: _parseUint128(json, ".pyusdx.earnerManagerRateLimit.capacity"),
            earnerManagerRateLimitRefillPerSecond: _parseUint128(json, ".pyusdx.earnerManagerRateLimit.refillPerSecond")
        });

        config.issuerGateway = IssuerGatewayConfig({
            admin: vm.parseJsonAddress(json, ".issuerGateway.admin"),
            operator: vm.parseJsonAddress(json, ".issuerGateway.operator"),
            executor: vm.parseJsonAddress(json, ".issuerGateway.executor"),
            mintDelay: _parseUint32(json, ".issuerGateway.mintDelay"),
            mintTTL: _parseUint32(json, ".issuerGateway.mintTTL"),
            rateLimitCapacity: _parseUint128(json, ".issuerGateway.rateLimit.capacity"),
            rateLimitRefillPerSecond: _parseUint128(json, ".issuerGateway.rateLimit.refillPerSecond")
        });

        config.swapFacility = SwapFacilityConfig({
            admin: vm.parseJsonAddress(json, ".swapFacility.admin"),
            pauser: vm.parseJsonAddress(json, ".swapFacility.pauser")
        });

        config.extensionFactory = FactoryConfig({
            admin: vm.parseJsonAddress(json, ".extensionFactory.admin"),
            factoryManager: vm.parseJsonAddress(json, ".extensionFactory.factoryManager")
        });

        config.portal = PortalConfig({
            admin: vm.parseJsonAddress(json, ".portal.admin"),
            pauser: vm.parseJsonAddress(json, ".portal.pauser"),
            operator: vm.parseJsonAddress(json, ".portal.operator"),
            fallbackRecipient: vm.parseJsonAddress(json, ".portal.fallbackRecipient"),
            rateLimitCapacity: _parseUint128(json, ".portal.rateLimit.capacity"),
            rateLimitRefillPerSecond: _parseUint128(json, ".portal.rateLimit.refillPerSecond")
        });

        config.layerZeroBridgeAdapter = LayerZeroBridgeAdapterConfig({
            lzEndpoint: vm.parseJsonAddress(json, ".layerZeroBridgeAdapter.endpoint"),
            admin: vm.parseJsonAddress(json, ".layerZeroBridgeAdapter.admin"),
            operator: vm.parseJsonAddress(json, ".layerZeroBridgeAdapter.operator")
        });

        _validateProtocolConfig(config);
    }

    /// @dev JSON numbers are read as uint256 and range-checked here, so an out-of-range value fails
    ///      with a readable message instead of silently truncating on the cast.
    function _parseUint128(string memory json, string memory key) internal pure returns (uint128) {
        uint256 value = vm.parseJsonUint(json, key);
        require(value <= type(uint128).max, string.concat(key, " exceeds uint128"));
        return uint128(value);
    }

    function _parseUint32(string memory json, string memory key) internal pure returns (uint32) {
        uint256 value = vm.parseJsonUint(json, key);
        require(value <= type(uint32).max, string.concat(key, " exceeds uint32"));
        return uint32(value);
    }

    /* ============ Config Validation ============ */

    function _validateProtocolConfig(ProtocolConfig memory config) internal pure {
        require(bytes(config.pyusdx.name).length != 0, "zero pyusdx.name");
        require(bytes(config.pyusdx.symbol).length != 0, "zero pyusdx.symbol");
        require(config.pyusdx.admin != address(0), "zero pyusdx.admin");
        require(config.pyusdx.pauser != address(0), "zero pyusdx.pauser");
        require(config.pyusdx.freezeManager != address(0), "zero pyusdx.freezeManager");
        require(config.pyusdx.forcedTransferManager != address(0), "zero pyusdx.forcedTransferManager");
        require(config.pyusdx.earnerManager != address(0), "zero pyusdx.earnerManager");
        require(config.pyusdx.rateManager != address(0), "zero pyusdx.rateManager");
        _validateRateLimit(
            "pyusdx.earnerManagerRateLimit",
            config.pyusdx.earnerManagerRateLimitCapacity,
            config.pyusdx.earnerManagerRateLimitRefillPerSecond
        );

        require(config.issuerGateway.admin != address(0), "zero issuerGateway.admin");
        require(config.issuerGateway.operator != address(0), "zero issuerGateway.operator");
        require(config.issuerGateway.executor != address(0), "zero issuerGateway.executor");
        // IssuerGateway._setMintTTL reverts on a zero TTL; mintDelay may legitimately be zero.
        require(config.issuerGateway.mintTTL != 0, "zero issuerGateway.mintTTL");
        _validateRateLimit(
            "issuerGateway.rateLimit",
            config.issuerGateway.rateLimitCapacity,
            config.issuerGateway.rateLimitRefillPerSecond
        );

        require(config.swapFacility.admin != address(0), "zero swapFacility.admin");
        require(config.swapFacility.pauser != address(0), "zero swapFacility.pauser");

        require(config.extensionFactory.admin != address(0), "zero extensionFactory.admin");
        require(config.extensionFactory.factoryManager != address(0), "zero extensionFactory.factoryManager");

        require(config.portal.admin != address(0), "zero portal.admin");
        require(config.portal.pauser != address(0), "zero portal.pauser");
        require(config.portal.operator != address(0), "zero portal.operator");
        require(config.portal.fallbackRecipient != address(0), "zero portal.fallbackRecipient");
        _validateRateLimit("portal.rateLimit", config.portal.rateLimitCapacity, config.portal.rateLimitRefillPerSecond);

        require(config.layerZeroBridgeAdapter.lzEndpoint != address(0), "zero layerZeroBridgeAdapter.endpoint");
        require(config.layerZeroBridgeAdapter.admin != address(0), "zero layerZeroBridgeAdapter.admin");
        require(config.layerZeroBridgeAdapter.operator != address(0), "zero layerZeroBridgeAdapter.operator");
    }

    /// @dev Every rate limit this script sets is enabled, and `RateLimiter.setRateLimit` reverts with
    ///      `InvalidRateLimitConfig` on a zero capacity — catch it here rather than mid-deploy. A
    ///      refill above the capacity refills a full bucket in under a second, which is never intended.
    function _validateRateLimit(string memory label, uint128 capacity, uint128 refillPerSecond) internal pure {
        require(capacity != 0, string.concat("zero ", label, ".capacity: an enabled rate limit needs capacity"));
        require(refillPerSecond <= capacity, string.concat(label, ".refillPerSecond exceeds capacity"));
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
