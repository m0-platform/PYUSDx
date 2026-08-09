// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IERC20Metadata } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { IPausable } from "../../lib/evm-m-extensions/src/components/pausable/IPausable.sol";

import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";
import { IMultiMint } from "../../src/platform/projects/interfaces/IMultiMint.sol";
import { IYieldToOne } from "../../src/platform/projects/interfaces/IYieldToOne.sol";
import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

import { DeployBase } from "./DeployBase.s.sol";

/// @title  DeployMultiMint
/// @notice Deploys a MultiMint extension via the ExtensionFactory, sets the initial asset caps in
///         the same run (the deployer transiently holds DEFAULT_ADMIN_ROLE and
///         ASSET_CAP_MANAGER_ROLE, then hands both to their final holders), and verifies the result.
/// @dev    Config is read from `extensions/<chainid>/<EXTENSION_NAME>.json` (schema in
///         extensions/README.md), overridable via EXTENSION_CONFIG.
contract DeployMultiMint is DeployBase {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        string memory extensionName = vm.envString("EXTENSION_NAME");
        address factory = _getFactory();

        MultiMintConfig memory config = _readMultiMintConfig(extensionName);

        vm.startBroadcast(deployer);

        (address proxy, address implementation) = _deployMultiMint(deployer, factory, extensionName, config);

        vm.stopBroadcast();

        // Also runs in forge's pre-broadcast simulation, aborting a mis-wired deploy before any tx is sent.
        _verifyMultiMintDeployment(deployer, factory, proxy, config);

        console.log("MultiMint Implementation:", implementation);
        console.log("MultiMint Proxy:         ", proxy);

        for (uint256 i; i < config.assets.length; ++i) {
            console.log("Asset allowed:", config.assets[i], "cap:", config.assetCaps[i]);
        }

        console.log("");
        console.log("REMINDER: yield accrual requires the PYUSDX earner manager to enroll the extension:");
        console.log("  pyusdx.setAccountInfo(proxy, earnerRateBps, feeRateBps, claimRecipient)");

        _writeDeployment(block.chainid, extensionName, proxy);
    }

    function _multiMintConfigPath(string memory extensionName) internal view returns (string memory) {
        return
            vm.envOr(
                "EXTENSION_CONFIG",
                string.concat(vm.projectRoot(), "/extensions/", vm.toString(block.chainid), "/", extensionName, ".json")
            );
    }

    function _readMultiMintConfig(string memory extensionName) internal view returns (MultiMintConfig memory) {
        string memory path = _multiMintConfigPath(extensionName);
        require(vm.isFile(path), string.concat("missing extension config file (see extensions/README.md): ", path));

        console.log("Config file:", path);

        return _parseMultiMintConfig(vm.readFile(path), extensionName);
    }

    function _parseMultiMintConfig(
        string memory json,
        string memory extensionName
    ) internal view returns (MultiMintConfig memory config) {
        require(
            keccak256(bytes(vm.parseJsonString(json, ".extensionName"))) == keccak256(bytes(extensionName)),
            "config extensionName does not match EXTENSION_NAME"
        );

        config.name = vm.parseJsonString(json, ".tokenName");
        config.symbol = vm.parseJsonString(json, ".tokenSymbol");
        config.admin = vm.parseJsonAddress(json, ".roles.admin");
        config.assetCapManager = vm.parseJsonAddress(json, ".roles.assetCapManager");
        config.freezeManager = vm.parseJsonAddress(json, ".roles.freezeManager");
        config.pauser = vm.parseJsonAddress(json, ".roles.pauser");
        config.versionManager = vm.parseJsonAddress(json, ".roles.versionManager");
        config.yieldRecipient = vm.parseJsonAddress(json, ".roles.yieldRecipient");
        config.yieldRecipientManager = vm.parseJsonAddress(json, ".roles.yieldRecipientManager");

        uint256 assetCount;
        while (vm.keyExistsJson(json, string.concat(".assets[", vm.toString(assetCount), "]"))) {
            ++assetCount;
        }

        config.assets = new address[](assetCount);
        config.assetCaps = new uint256[](assetCount);

        for (uint256 i; i < assetCount; ++i) {
            string memory prefix = string.concat(".assets[", vm.toString(i), "]");
            config.assets[i] = vm.parseJsonAddress(json, string.concat(prefix, ".address"));
            config.assetCaps[i] = vm.parseJsonUint(json, string.concat(prefix, ".cap"));
        }

        config.replaceAssetWhitelist = vm.keyExistsJson(json, ".replaceAssetWhitelist")
            ? vm.parseJsonAddressArray(json, ".replaceAssetWhitelist")
            : new address[](0);

        _validateMultiMintConfig(config);
    }

    function _validateMultiMintConfig(MultiMintConfig memory config) internal pure {
        require(config.admin != address(0), "zero admin address");
        require(config.assetCapManager != address(0), "zero asset cap manager address");
        require(config.freezeManager != address(0), "zero freeze manager address");
        require(config.pauser != address(0), "zero pauser address");
        require(config.versionManager != address(0), "zero version manager address");
        require(config.yieldRecipient != address(0), "zero yield recipient address");
        require(config.yieldRecipientManager != address(0), "zero yield recipient manager address");

        require(config.assets.length != 0, "ASSETS must list at least one collateral asset");
        require(config.assets.length == config.assetCaps.length, "ASSETS and ASSET_CAPS length mismatch");

        for (uint256 i; i < config.assets.length; ++i) {
            require(config.assets[i] != address(0), "zero asset address");
            require(config.assetCaps[i] != 0, "zero asset cap: a zero cap disables the asset");

            for (uint256 j = i + 1; j < config.assets.length; ++j) {
                require(config.assets[i] != config.assets[j], "duplicate asset");
            }
        }
    }

    /// @dev The deployer is initialized as admin and asset cap manager so the caps can be set
    ///      here; both roles are handed to their final holders before returning.
    function _deployMultiMint(
        address deployer,
        address factory,
        string memory extensionName,
        MultiMintConfig memory config
    ) internal returns (address proxy, address implementation) {
        (proxy, implementation) = ExtensionFactory(factory).deployMultiMint(
            extensionName,
            IExtensionFactory.MultiMintParams({
                name: config.name,
                symbol: config.symbol,
                yieldRecipient: config.yieldRecipient,
                admin: deployer,
                assetCapManager: deployer,
                freezeManager: config.freezeManager,
                pauser: config.pauser,
                yieldRecipientManager: config.yieldRecipientManager,
                versionManager: config.versionManager
            })
        );

        for (uint256 i; i < config.assets.length; ++i) {
            IMultiMint(proxy).setAssetCap(config.assets[i], config.assetCaps[i]);
        }

        for (uint256 i; i < config.replaceAssetWhitelist.length; ++i) {
            IMultiMint(proxy).setReplaceAssetWhitelistCaller(config.replaceAssetWhitelist[i], true);
        }

        bytes32 assetCapManagerRole = IMultiMint(proxy).ASSET_CAP_MANAGER_ROLE();
        bytes32 defaultAdminRole = AccessControlUpgradeable(proxy).DEFAULT_ADMIN_ROLE();

        // Asset-cap-manager handoff runs first so the deployer retains DEFAULT_ADMIN_ROLE through both grants.
        if (deployer != config.assetCapManager) {
            IAccessControl(proxy).grantRole(assetCapManagerRole, config.assetCapManager);
            IAccessControl(proxy).renounceRole(assetCapManagerRole, deployer);
        }

        if (deployer != config.admin) {
            IAccessControl(proxy).grantRole(defaultAdminRole, config.admin);
            IAccessControl(proxy).renounceRole(defaultAdminRole, deployer);
        }
    }

    function _verifyMultiMintDeployment(
        address deployer,
        address factory,
        address proxy,
        MultiMintConfig memory config
    ) internal view {
        require(
            ExtensionFactory(factory).getExtensionType(proxy) == IExtensionFactory.ExtensionType.MULTI_MINT,
            "extension not registered as MULTI_MINT on factory"
        );

        address swapFacility = ExtensionFactory(factory).swapFacility();
        require(ISwapFacility(swapFacility).isApprovedExtension(proxy), "extension not approved on SwapFacility");
        require(IExtension(proxy).swapFacility() == swapFacility, "extension wired to wrong SwapFacility");

        require(keccak256(bytes(IERC20Metadata(proxy).name())) == keccak256(bytes(config.name)), "token name mismatch");
        require(
            keccak256(bytes(IERC20Metadata(proxy).symbol())) == keccak256(bytes(config.symbol)),
            "token symbol mismatch"
        );

        for (uint256 i; i < config.assets.length; ++i) {
            require(IMultiMint(proxy).isAllowedAsset(config.assets[i]), "asset not allowed");
            require(IMultiMint(proxy).assetCap(config.assets[i]) == config.assetCaps[i], "asset cap mismatch");
            require(
                IMultiMint(proxy).assetDecimals(config.assets[i]) == IERC20Metadata(config.assets[i]).decimals(),
                "asset decimals not recorded"
            );
        }

        bytes32 assetCapManagerRole = IMultiMint(proxy).ASSET_CAP_MANAGER_ROLE();
        bytes32 defaultAdminRole = AccessControlUpgradeable(proxy).DEFAULT_ADMIN_ROLE();

        require(IAccessControl(proxy).hasRole(defaultAdminRole, config.admin), "admin does not hold role");
        require(
            IAccessControl(proxy).hasRole(assetCapManagerRole, config.assetCapManager),
            "asset cap manager does not hold role"
        );
        require(
            IAccessControl(proxy).hasRole(IFreezable(proxy).FREEZE_MANAGER_ROLE(), config.freezeManager),
            "freeze manager does not hold role"
        );
        require(
            IAccessControl(proxy).hasRole(IPausable(proxy).PAUSER_ROLE(), config.pauser),
            "pauser does not hold role"
        );
        require(
            IAccessControl(proxy).hasRole(
                IYieldToOne(proxy).YIELD_RECIPIENT_MANAGER_ROLE(),
                config.yieldRecipientManager
            ),
            "yield recipient manager does not hold role"
        );
        require(
            IAccessControl(proxy).hasRole(IExtension(proxy).VERSION_MANAGER_ROLE(), config.versionManager),
            "version manager does not hold role"
        );
        require(IYieldToOne(proxy).yieldRecipient() == config.yieldRecipient, "yield recipient mismatch");

        if (deployer != config.admin) {
            require(!IAccessControl(proxy).hasRole(defaultAdminRole, deployer), "deployer still holds admin role");
        }

        if (deployer != config.assetCapManager) {
            require(
                !IAccessControl(proxy).hasRole(assetCapManagerRole, deployer),
                "deployer still holds asset cap manager role"
            );
        }

        if (config.replaceAssetWhitelist.length != 0) {
            require(IMultiMint(proxy).isReplaceAssetWhitelistEnabled(), "replaceAsset whitelist not enabled");

            address[] memory whitelist = IMultiMint(proxy).getReplaceAssetWhitelist();
            require(whitelist.length == config.replaceAssetWhitelist.length, "replaceAsset whitelist length mismatch");

            for (uint256 i; i < config.replaceAssetWhitelist.length; ++i) {
                bool found;
                for (uint256 j; j < whitelist.length; ++j) {
                    if (whitelist[j] == config.replaceAssetWhitelist[i]) {
                        found = true;
                        break;
                    }
                }
                require(found, "replaceAsset whitelist caller not seeded");
            }
        }
    }
}
