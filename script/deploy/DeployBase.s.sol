// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { DeployHelpers } from "../../lib/evm-m-extensions/lib/common/script/deploy/DeployHelpers.sol";

import { Upgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IssuerGateway } from "../../src/core/IssuerGateway.sol";
import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";
import { IRateLimiter } from "../../src/abstract/interfaces/IRateLimiter.sol";
import { ExtensionBeacon } from "../../src/platform/ExtensionBeacon.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { Portal } from "../../src/portal/Portal.sol";
import { LayerZeroBridgeAdapter } from "../../src/portal/bridgeAdapters/layerZero/LayerZeroBridgeAdapter.sol";
import { PortalOFTWrapper } from "../../src/portal/oft/PortalOFTWrapper.sol";

import { ScriptBase } from "../ScriptBase.s.sol";

contract DeployBase is DeployHelpers, ScriptBase {
    struct CoreDeployments {
        address pyusdxProxy;
        address pyusdxProxyAdmin;
        address pyusdxImplementation;
        address issuerGatewayProxy;
        address issuerGatewayProxyAdmin;
        address issuerGatewayImplementation;
        address swapFacilityProxy;
        address swapFacilityProxyAdmin;
        address swapFacilityImplementation;
        address portalProxy;
        address portalProxyAdmin;
        address portalImplementation;
        address layerZeroBridgeAdapterProxy;
        address layerZeroBridgeAdapterProxyAdmin;
        address layerZeroBridgeAdapterImplementation;
        address yieldToOneBeaconProxy;
        address yieldToOneBeaconProxyAdmin;
        address yieldToOneBeaconImplementation;
        address multiMintBeaconProxy;
        address multiMintBeaconProxyAdmin;
        address multiMintBeaconImplementation;
        address factoryProxy;
        address factoryProxyAdmin;
        address factoryImplementation;
    }

    /* ============ Individual Deploy Functions ============ */

    function _deployPYUSDX(
        address deployer,
        address proxyInitialOwner,
        address admin,
        address rateLimitManager,
        address issuerGatewayProxy,
        PYUSDXConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new PYUSDX());

        proxy = _deployCreate3TransparentProxy(
            implementation,
            proxyInitialOwner,
            abi.encodeCall(
                PYUSDX.initialize,
                (
                    IPYUSDX.InitializeParams({
                        name: config.name,
                        symbol: config.symbol,
                        admin: admin,
                        pauser: config.pauser,
                        freezeManager: config.freezeManager,
                        forcedTransferManager: config.forcedTransferManager,
                        earnerManager: config.earnerManager,
                        rateLimitManager: rateLimitManager,
                        issuer: issuerGatewayProxy
                    })
                )
            ),
            _computeSalt(deployer, "PYUSDX")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployIssuerGateway(
        address deployer,
        address pyusdxProxy,
        IssuerGatewayConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new IssuerGateway(pyusdxProxy));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(
                IssuerGateway.initialize.selector,
                config.admin,
                config.operator,
                config.executor,
                config.mintDelay,
                config.mintTTL
            ),
            _computeSalt(deployer, "PYUSDXIssuerGateway")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deploySwapFacility(
        address deployer,
        address pyusdxProxy,
        address factoryProxy,
        SwapFacilityConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new SwapFacility(pyusdxProxy, factoryProxy));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(SwapFacility.initialize.selector, config.admin, config.pauser),
            _computeSalt(deployer, "PYUSDXSwapFacility")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployFactory(
        address deployer,
        address pyusdxProxy,
        address swapFacilityProxy,
        address yieldToOneBeaconProxy,
        address multiMintBeaconProxy,
        FactoryConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(
            new ExtensionFactory(pyusdxProxy, swapFacilityProxy, yieldToOneBeaconProxy, multiMintBeaconProxy)
        );

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(ExtensionFactory.initialize.selector, config.admin, config.factoryManager),
            _computeSalt(deployer, "PYUSDXExtensionFactory")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployBeacon(
        address deployer,
        address pyusdxProxy,
        address swapFacilityProxy,
        address initialImpl,
        string memory saltSuffix,
        FactoryConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new ExtensionBeacon(pyusdxProxy, swapFacilityProxy));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(
                ExtensionBeacon.initialize.selector,
                config.admin,
                config.factoryManager,
                initialImpl
            ),
            _computeSalt(deployer, saltSuffix)
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployPortal(
        address deployer,
        address pyusdxProxy,
        address swapFacilityProxy,
        PortalConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new Portal(pyusdxProxy, swapFacilityProxy));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(
                Portal.initialize.selector,
                config.admin,
                config.pauser,
                config.operator,
                config.fallbackRecipient
            ),
            _computeSalt(deployer, "PYUSDXPortal")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployLayerZeroBridgeAdapter(
        address deployer,
        address portalProxy,
        LayerZeroBridgeAdapterConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new LayerZeroBridgeAdapter(config.lzEndpoint, portalProxy));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(LayerZeroBridgeAdapter.initialize.selector, config.admin, config.operator),
            _computeSalt(deployer, "PYUSDXLayerZeroBridgeAdapter")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployPortalOFTWrapper(
        address deployer,
        address portalProxy,
        address token,
        address layerZeroBridgeAdapterProxy,
        string memory saltSuffix,
        PortalOFTWrapperConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new PortalOFTWrapper(portalProxy, token, layerZeroBridgeAdapterProxy));

        // One wrapper instance exists per token, so the salt carries a per-token suffix.
        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(PortalOFTWrapper.initialize.selector, config.admin, config.operator),
            _computeSalt(deployer, string.concat("PYUSDXPortalOFTWrapper", saltSuffix))
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    /* ============ Core Deployment Orchestrator ============ */

    function _deployCore(
        address deployer,
        PYUSDXConfig memory pyusdxConfig,
        IssuerGatewayConfig memory issuerGatewayConfig,
        SwapFacilityConfig memory swapFacilityConfig,
        FactoryConfig memory factoryConfig,
        PortalConfig memory portalConfig,
        LayerZeroBridgeAdapterConfig memory layerZeroBridgeAdapterConfig
    ) internal returns (CoreDeployments memory deployment) {
        (address targetAdmin, address targetRateManager) = _deployCoreContracts(
            deployer,
            pyusdxConfig,
            issuerGatewayConfig,
            swapFacilityConfig,
            factoryConfig,
            deployment
        );

        _deployPortalStack(deployer, portalConfig, layerZeroBridgeAdapterConfig, deployment);

        _configurePYUSDXRoles(
            deployer,
            deployment.pyusdxProxy,
            IssuerSetup({
                issuerGatewayProxy: deployment.issuerGatewayProxy,
                portalProxy: deployment.portalProxy,
                earnerManager: pyusdxConfig.earnerManager,
                issuerGatewayCapacity: issuerGatewayConfig.rateLimitCapacity,
                issuerGatewayRefill: issuerGatewayConfig.rateLimitRefillPerSecond,
                portalCapacity: portalConfig.rateLimitCapacity,
                portalRefill: portalConfig.rateLimitRefillPerSecond,
                earnerManagerCapacity: pyusdxConfig.earnerManagerRateLimitCapacity,
                earnerManagerRefill: pyusdxConfig.earnerManagerRateLimitRefillPerSecond
            }),
            targetAdmin,
            targetRateManager
        );
    }

    function _deployCoreContracts(
        address deployer,
        PYUSDXConfig memory pyusdxConfig,
        IssuerGatewayConfig memory issuerGatewayConfig,
        SwapFacilityConfig memory swapFacilityConfig,
        FactoryConfig memory factoryConfig,
        CoreDeployments memory deployment
    ) internal returns (address targetAdmin, address targetRateManager) {
        (targetAdmin, targetRateManager) = _deployPYUSDXAndIssuerGateway(
            deployer,
            pyusdxConfig,
            issuerGatewayConfig,
            deployment
        );

        address predictedSwapFacility = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDXSwapFacility"));
        address predictedFactory = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDXExtensionFactory"));

        console.log("Predicted SwapFacility proxy:      ", predictedSwapFacility);
        console.log("Predicted Factory proxy:           ", predictedFactory);

        (
            deployment.swapFacilityProxy,
            deployment.swapFacilityProxyAdmin,
            deployment.swapFacilityImplementation
        ) = _deploySwapFacility(deployer, deployment.pyusdxProxy, predictedFactory, swapFacilityConfig);

        require(deployment.swapFacilityProxy == predictedSwapFacility, "SwapFacility proxy address mismatch");

        address yieldToOneImpl = address(new YieldToOne(deployment.pyusdxProxy, deployment.swapFacilityProxy));
        address multiMintImpl = address(new MultiMint(deployment.pyusdxProxy, deployment.swapFacilityProxy));

        (
            deployment.yieldToOneBeaconProxy,
            deployment.yieldToOneBeaconProxyAdmin,
            deployment.yieldToOneBeaconImplementation
        ) = _deployBeacon(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            yieldToOneImpl,
            "PYUSDXYieldToOneBeacon",
            factoryConfig
        );

        (
            deployment.multiMintBeaconProxy,
            deployment.multiMintBeaconProxyAdmin,
            deployment.multiMintBeaconImplementation
        ) = _deployBeacon(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            multiMintImpl,
            "PYUSDXMultiMintBeacon",
            factoryConfig
        );

        // NOTE: SwapFacility must already exist — constructor validates it
        (deployment.factoryProxy, deployment.factoryProxyAdmin, deployment.factoryImplementation) = _deployFactory(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            deployment.yieldToOneBeaconProxy,
            deployment.multiMintBeaconProxy,
            factoryConfig
        );

        require(deployment.factoryProxy == predictedFactory, "Factory proxy address mismatch");
    }

    function _deployPYUSDXAndIssuerGateway(
        address deployer,
        PYUSDXConfig memory pyusdxConfig,
        IssuerGatewayConfig memory issuerGatewayConfig,
        CoreDeployments memory deployment
    ) internal returns (address targetAdmin, address targetRateManager) {
        address predictedPYUSDX = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDX"));
        address predictedIssuerGateway = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDXIssuerGateway"));

        console.log("Predicted PYUSDX proxy:            ", predictedPYUSDX);
        console.log("Predicted IssuerGateway proxy:     ", predictedIssuerGateway);

        // The deployer holds DEFAULT_ADMIN_ROLE and RATE_LIMIT_MANAGER_ROLE during the deploy process
        // to grant the various roles and rate limits, then renounces them at the end.
        // `pyusdxConfig.admin` and `pyusdxConfig.rateManager` are the final holders of these roles.
        targetAdmin = pyusdxConfig.admin;
        targetRateManager = pyusdxConfig.rateManager;

        (deployment.pyusdxProxy, deployment.pyusdxProxyAdmin, deployment.pyusdxImplementation) = _deployPYUSDX(
            deployer,
            pyusdxConfig.admin,
            deployer,
            deployer,
            predictedIssuerGateway,
            pyusdxConfig
        );

        require(deployment.pyusdxProxy == predictedPYUSDX, "PYUSDX proxy address mismatch");

        (
            deployment.issuerGatewayProxy,
            deployment.issuerGatewayProxyAdmin,
            deployment.issuerGatewayImplementation
        ) = _deployIssuerGateway(deployer, deployment.pyusdxProxy, issuerGatewayConfig);

        require(deployment.issuerGatewayProxy == predictedIssuerGateway, "IssuerGateway proxy address mismatch");
    }

    /// @dev Addresses + rate-limit parameters for issuers configured during deployment.
    struct IssuerSetup {
        address issuerGatewayProxy;
        address portalProxy;
        address earnerManager;
        uint128 issuerGatewayCapacity;
        uint128 issuerGatewayRefill;
        uint128 portalCapacity;
        uint128 portalRefill;
        uint128 earnerManagerCapacity;
        uint128 earnerManagerRefill;
    }

    /// @dev Configures rate limits, grants ISSUER_ROLE to the Portal, transfers admin
    ///      and rate-manager roles to their target holders, and renounces the deployer's
    ///      transient roles.
    function _configurePYUSDXRoles(
        address deployer,
        address pyusdxProxy,
        IssuerSetup memory issuers,
        address targetAdmin,
        address targetRateManager
    ) internal {
        IRateLimiter(pyusdxProxy).setRateLimit(
            issuers.issuerGatewayProxy,
            issuers.issuerGatewayCapacity,
            issuers.issuerGatewayRefill,
            true
        );

        IRateLimiter(pyusdxProxy).setRateLimit(issuers.portalProxy, issuers.portalCapacity, issuers.portalRefill, true);

        IRateLimiter(pyusdxProxy).setRateLimit(
            issuers.earnerManager,
            issuers.earnerManagerCapacity,
            issuers.earnerManagerRefill,
            true
        );

        IAccessControl(pyusdxProxy).grantRole(PYUSDX(pyusdxProxy).ISSUER_ROLE(), issuers.portalProxy);

        bytes32 rateLimitManagerRole = IRateLimiter(pyusdxProxy).RATE_LIMIT_MANAGER_ROLE();
        bytes32 defaultAdminRole = 0x00;

        // The deployer already holds both roles from initialization.
        // Only transfer a role to its target holder when that holder is not the deployer:
        // grant it to the target, then renounce the deployer's copy.
        // The rate-manager block runs first so the deployer retains DEFAULT_ADMIN_ROLE through both grants.
        if (deployer != targetRateManager) {
            IAccessControl(pyusdxProxy).grantRole(rateLimitManagerRole, targetRateManager);
            IAccessControl(pyusdxProxy).renounceRole(rateLimitManagerRole, deployer);
        }

        if (deployer != targetAdmin) {
            IAccessControl(pyusdxProxy).grantRole(defaultAdminRole, targetAdmin);
            IAccessControl(pyusdxProxy).renounceRole(defaultAdminRole, deployer);
        }
    }

    function _deployPortalStack(
        address deployer,
        PortalConfig memory portalConfig,
        LayerZeroBridgeAdapterConfig memory layerZeroBridgeAdapterConfig,
        CoreDeployments memory deployment
    ) internal {
        address predictedPortal = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDXPortal"));
        address predictedLayerZeroBridgeAdapter = _getCreate3Address(
            deployer,
            _computeSalt(deployer, "PYUSDXLayerZeroBridgeAdapter")
        );

        console.log("Predicted Portal proxy:            ", predictedPortal);
        console.log("Predicted LayerZeroBridgeAdapter:  ", predictedLayerZeroBridgeAdapter);

        (deployment.portalProxy, deployment.portalProxyAdmin, deployment.portalImplementation) = _deployPortal(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            portalConfig
        );

        require(deployment.portalProxy == predictedPortal, "Portal proxy address mismatch");

        (
            deployment.layerZeroBridgeAdapterProxy,
            deployment.layerZeroBridgeAdapterProxyAdmin,
            deployment.layerZeroBridgeAdapterImplementation
        ) = _deployLayerZeroBridgeAdapter(deployer, deployment.portalProxy, layerZeroBridgeAdapterConfig);

        require(
            deployment.layerZeroBridgeAdapterProxy == predictedLayerZeroBridgeAdapter,
            "LayerZeroBridgeAdapter proxy address mismatch"
        );
    }
}
