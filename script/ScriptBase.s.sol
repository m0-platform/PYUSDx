// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Config } from "./Config.sol";

import { console } from "../lib/forge-std/src/console.sol";
import { Script } from "../lib/forge-std/src/Script.sol";
import { VmSafe } from "../lib/forge-std/src/Vm.sol";

contract ScriptBase is Script, Config {
    /// @dev Fields MUST be in alphabetical order: `vm.writeJson` emits object keys sorted, so keeping
    ///      the struct in the same order keeps the record and the struct visually aligned.
    ///      `_readDeployment` reads key by key rather than `abi.decode`-ing the whole object, so a
    ///      record written before a field existed still loads (the missing field reads as address(0)).
    struct Deployments {
        address[] extensionAddresses;
        address extensionFactory;
        string[] extensionNames;
        address issuerGateway;
        address layerZeroBridgeAdapter;
        address multiMintBeacon;
        address portal;
        address pyusdx;
        address pyusdxPortalOFTWrapper;
        address swapFacility;
        address yieldToOneBeacon;
    }

    function _getExtensionName() internal view returns (string memory) {
        return vm.envString("EXTENSION_NAME");
    }

    function _setExtensionDeployment(
        Deployments memory deployments_,
        string memory key_,
        address value_
    ) internal pure returns (Deployments memory) {
        bool append = true;
        for (uint256 i = 0; i < deployments_.extensionNames.length; i++) {
            if (keccak256(bytes(deployments_.extensionNames[i])) == keccak256(bytes(key_))) {
                deployments_.extensionNames[i] = key_;
                deployments_.extensionAddresses[i] = value_;
                append = false;
                break;
            }
        }

        if (append) {
            string[] memory nameReplacements = new string[](deployments_.extensionNames.length + 1);
            address[] memory addressReplacements = new address[](deployments_.extensionNames.length + 1);

            for (uint256 i = 0; i < deployments_.extensionNames.length; i++) {
                nameReplacements[i] = deployments_.extensionNames[i];
                addressReplacements[i] = deployments_.extensionAddresses[i];
            }

            nameReplacements[nameReplacements.length - 1] = key_;
            addressReplacements[addressReplacements.length - 1] = value_;

            deployments_.extensionNames = nameReplacements;
            deployments_.extensionAddresses = addressReplacements;
        }

        return deployments_;
    }

    /// @dev Overridable so tests can redirect the record away from the checked-in `deployments/`.
    function _deployOutputDir() internal view virtual returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments");
    }

    function _deployOutputPath(uint256 chainId_) internal view returns (string memory) {
        return string.concat(_deployOutputDir(), "/", vm.toString(chainId_), ".json");
    }

    /// @dev The top-level keys of the deployment record. Everything else is an extension handle and
    ///      is recorded in the `extensionNames`/`extensionAddresses` pair instead. The beacons are
    ///      core infrastructure shared by every extension, so they are core keys, not extensions.
    function _isCoreDeploymentKey(string memory key_) internal pure returns (bool) {
        bytes32 key = keccak256(bytes(key_));

        return
            key == keccak256("pyusdx") ||
            key == keccak256("issuerGateway") ||
            key == keccak256("swapFacility") ||
            key == keccak256("extensionFactory") ||
            key == keccak256("layerZeroBridgeAdapter") ||
            key == keccak256("portal") ||
            key == keccak256("pyusdxPortalOFTWrapper") ||
            key == keccak256("yieldToOneBeacon") ||
            key == keccak256("multiMintBeacon");
    }

    function _emptyDeployment() internal pure returns (Deployments memory) {
        return
            Deployments({
                extensionAddresses: new address[](0),
                extensionFactory: address(0),
                extensionNames: new string[](0),
                issuerGateway: address(0),
                layerZeroBridgeAdapter: address(0),
                multiMintBeacon: address(0),
                portal: address(0),
                pyusdx: address(0),
                pyusdxPortalOFTWrapper: address(0),
                swapFacility: address(0),
                yieldToOneBeacon: address(0)
            });
    }

    function _writeDeployment(uint256 chainId_, string memory key_, address value_) internal {
        vm.createDir(_deployOutputDir(), true);

        string memory root = "";

        Deployments memory deployments_ = _readDeployment(chainId_);

        if (!_isCoreDeploymentKey(key_)) {
            deployments_ = _setExtensionDeployment(deployments_, key_, value_);
        }

        vm.serializeAddress(root, "pyusdx", _resolve(key_, "pyusdx", value_, deployments_.pyusdx));

        vm.serializeAddress(root, "issuerGateway", _resolve(key_, "issuerGateway", value_, deployments_.issuerGateway));

        vm.serializeAddress(root, "swapFacility", _resolve(key_, "swapFacility", value_, deployments_.swapFacility));

        vm.serializeAddress(
            root,
            "extensionFactory",
            _resolve(key_, "extensionFactory", value_, deployments_.extensionFactory)
        );

        vm.serializeAddress(
            root,
            "layerZeroBridgeAdapter",
            _resolve(key_, "layerZeroBridgeAdapter", value_, deployments_.layerZeroBridgeAdapter)
        );

        vm.serializeAddress(root, "portal", _resolve(key_, "portal", value_, deployments_.portal));

        vm.serializeAddress(
            root,
            "pyusdxPortalOFTWrapper",
            _resolve(key_, "pyusdxPortalOFTWrapper", value_, deployments_.pyusdxPortalOFTWrapper)
        );

        vm.serializeAddress(
            root,
            "yieldToOneBeacon",
            _resolve(key_, "yieldToOneBeacon", value_, deployments_.yieldToOneBeacon)
        );

        vm.serializeAddress(
            root,
            "multiMintBeacon",
            _resolve(key_, "multiMintBeacon", value_, deployments_.multiMintBeacon)
        );

        vm.serializeString(root, "extensionNames", deployments_.extensionNames);

        // NOTE: we only want to write the deployments if it's not a dry run,
        // i.e. the transaction is actually broadcast.
        if (!vm.isContext(VmSafe.ForgeContext.ScriptDryRun)) {
            vm.writeJson(
                vm.serializeAddress(root, "extensionAddresses", deployments_.extensionAddresses),
                _deployOutputPath(chainId_)
            );
        }
    }

    /// @dev Returns `value_` when the write targets `field_`, otherwise the address already on record.
    function _resolve(
        string memory key_,
        string memory field_,
        address value_,
        address current_
    ) private pure returns (address) {
        return keccak256(bytes(key_)) == keccak256(bytes(field_)) ? value_ : current_;
    }

    function _readDeployment(uint256 chainId_) internal view returns (Deployments memory deployments_) {
        string memory path = _deployOutputPath(chainId_);

        if (!vm.isFile(path)) return _emptyDeployment();

        string memory json = vm.readFile(path);

        deployments_.extensionAddresses = vm.keyExistsJson(json, ".extensionAddresses")
            ? vm.parseJsonAddressArray(json, ".extensionAddresses")
            : new address[](0);

        deployments_.extensionNames = vm.keyExistsJson(json, ".extensionNames")
            ? vm.parseJsonStringArray(json, ".extensionNames")
            : new string[](0);

        require(
            deployments_.extensionNames.length == deployments_.extensionAddresses.length,
            "deployment record: extension names/addresses length mismatch"
        );

        deployments_.extensionFactory = _readAddress(json, ".extensionFactory");
        deployments_.issuerGateway = _readAddress(json, ".issuerGateway");
        deployments_.layerZeroBridgeAdapter = _readAddress(json, ".layerZeroBridgeAdapter");
        deployments_.multiMintBeacon = _readAddress(json, ".multiMintBeacon");
        deployments_.portal = _readAddress(json, ".portal");
        deployments_.pyusdx = _readAddress(json, ".pyusdx");
        deployments_.pyusdxPortalOFTWrapper = _readAddress(json, ".pyusdxPortalOFTWrapper");
        deployments_.swapFacility = _readAddress(json, ".swapFacility");
        deployments_.yieldToOneBeacon = _readAddress(json, ".yieldToOneBeacon");
    }

    /// @dev Missing keys read as address(0) so records written before a field existed still load.
    function _readAddress(string memory json_, string memory key_) private view returns (address) {
        return vm.keyExistsJson(json_, key_) ? vm.parseJsonAddress(json_, key_) : address(0);
    }

    function _getPYUSDX() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.pyusdx == address(0)) {
            return vm.envAddress("PYUSDX");
        } else {
            return deployments_.pyusdx;
        }
    }

    function _getIssuerGateway() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.issuerGateway == address(0)) {
            return vm.envAddress("ISSUER_GATEWAY");
        } else {
            return deployments_.issuerGateway;
        }
    }

    function _getSwapFacility() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.swapFacility == address(0)) {
            return vm.envAddress("SWAP_FACILITY");
        } else {
            return deployments_.swapFacility;
        }
    }

    function _getFactory() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.extensionFactory == address(0)) {
            return vm.envAddress("EXTENSION_FACTORY");
        } else {
            return deployments_.extensionFactory;
        }
    }

    function _getLayerZeroBridgeAdapter() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.layerZeroBridgeAdapter == address(0)) {
            return vm.envAddress("LAYER_ZERO_BRIDGE_ADAPTER");
        } else {
            return deployments_.layerZeroBridgeAdapter;
        }
    }

    function _getPortal() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.portal == address(0)) {
            return vm.envAddress("PORTAL");
        } else {
            return deployments_.portal;
        }
    }

    function _getPYUSDXPortalOFTWrapper() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.pyusdxPortalOFTWrapper == address(0)) {
            return vm.envAddress("PYUSDX_PORTAL_OFT_WRAPPER");
        } else {
            return deployments_.pyusdxPortalOFTWrapper;
        }
    }

    /// @dev The YieldToOne `ExtensionBeacon` proxy — the upgrade lever shared by every YieldToOne
    ///      extension, not an extension proxy itself.
    function _getYieldToOneBeacon() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.yieldToOneBeacon == address(0)) {
            return vm.envAddress("YIELD_TO_ONE_BEACON");
        } else {
            return deployments_.yieldToOneBeacon;
        }
    }

    /// @dev The MultiMint `ExtensionBeacon` proxy — the upgrade lever shared by every MultiMint
    ///      extension, not an extension proxy itself.
    function _getMultiMintBeacon() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.multiMintBeacon == address(0)) {
            return vm.envAddress("MULTI_MINT_BEACON");
        } else {
            return deployments_.multiMintBeacon;
        }
    }

    /* ============ Protocol Config Loading ============ */

    /// @dev Overridable for the same reason as `_deployOutputDir`: `PROTOCOL_CONFIG` is a
    ///      process-global that forge shares across concurrently running suites, so a test that
    ///      wrote it would change what every other suite reads. Tests point their own scripts at a
    ///      scratch config instead.
    function _protocolConfigPath(uint256 chainId) internal view virtual returns (string memory) {
        string memory overridePath = vm.envOr("PROTOCOL_CONFIG", string(""));
        if (bytes(overridePath).length != 0) return overridePath;

        return string.concat(vm.projectRoot(), "/deploymentConfigs/", vm.toString(chainId), "/protocol.json");
    }

    /// @dev Split out of `_readProtocolConfig` so the role-migration scripts can parse their own
    ///      migration-only blocks out of the same file without re-implementing the lookup or the
    ///      missing-file message.
    function _readProtocolConfigFile(uint256 chainId) internal view returns (string memory) {
        string memory path = _protocolConfigPath(chainId);
        require(
            vm.isFile(path),
            string.concat(
                "missing protocol config file (see deploymentConfigs/README.md#deployment-configuration): ",
                path
            )
        );

        console.log("Config file:", path);

        return vm.readFile(path);
    }

    function _readProtocolConfig(uint256 chainId) internal view returns (ProtocolConfig memory) {
        return _parseProtocolConfig(_readProtocolConfigFile(chainId), chainId);
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

    /* ============ Protocol Config Validation ============ */

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

    /// @dev Every rate limit `DeployAll` sets is enabled, and `RateLimiter.setRateLimit` reverts with
    ///      `InvalidRateLimitConfig` on a zero capacity — catch it here rather than mid-deploy. A
    ///      refill above the capacity refills a full bucket in under a second, which is never intended.
    function _validateRateLimit(string memory label, uint128 capacity, uint128 refillPerSecond) internal pure {
        require(capacity != 0, string.concat("zero ", label, ".capacity: an enabled rate limit needs capacity"));
        require(refillPerSecond <= capacity, string.concat(label, ".refillPerSecond exceeds capacity"));
    }
}
