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
        address beaconProxy;
        address beaconProxyAdmin;
        address beaconImplementation;
        address factoryProxy;
        address factoryProxyAdmin;
        address factoryImplementation;
    }

    /* ============ Individual Deploy Functions ============ */

    function _deployPYUSDX(
        address deployer,
        address issuerGatewayProxy,
        PYUSDXConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new PYUSDX());

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeCall(
                PYUSDX.initialize,
                (
                    IPYUSDX.InitializeParams({
                        name: config.name,
                        symbol: config.symbol,
                        admin: config.admin,
                        pauser: config.pauser,
                        freezeManager: config.freezeManager,
                        forcedTransferManager: config.forcedTransferManager,
                        earnerManager: config.earnerManager,
                        rateLimitManager: config.rateManager,
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
                config.issuer,
                config.minter,
                config.mintDelay,
                config.mintTTL
            ),
            _computeSalt(deployer, "IssuerGateway")
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
            _computeSalt(deployer, "SwapFacility")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployFactory(
        address deployer,
        address pyusdxProxy,
        address swapFacilityProxy,
        address extensionBeaconProxy,
        FactoryConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        // NOTE: SwapFacility must already be deployed since constructor calls ISwapFacility(swapFacility).pyusdx()
        implementation = address(new ExtensionFactory(pyusdxProxy, swapFacilityProxy, extensionBeaconProxy));

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
        address yieldToOneImpl,
        address multiMintImpl,
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
                yieldToOneImpl,
                multiMintImpl
            ),
            _computeSalt(deployer, "ExtensionBeacon")
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

    /* ============ Core Stack Orchestrator ============ */

    function _deployCore(
        address deployer,
        PYUSDXConfig memory pyusdxConfig,
        IssuerGatewayConfig memory issuerGatewayConfig,
        SwapFacilityConfig memory swapFacilityConfig,
        FactoryConfig memory factoryConfig,
        PortalConfig memory portalConfig,
        LayerZeroBridgeAdapterConfig memory layerZeroBridgeAdapterConfig
    ) internal returns (CoreDeployments memory deployment) {
        _deployCoreContracts(
            deployer,
            pyusdxConfig,
            issuerGatewayConfig,
            swapFacilityConfig,
            factoryConfig,
            deployment
        );
        _deployPortalStack(deployer, portalConfig, layerZeroBridgeAdapterConfig, deployment);
    }

    function _deployCoreContracts(
        address deployer,
        PYUSDXConfig memory pyusdxConfig,
        IssuerGatewayConfig memory issuerGatewayConfig,
        SwapFacilityConfig memory swapFacilityConfig,
        FactoryConfig memory factoryConfig,
        CoreDeployments memory deployment
    ) internal {
        // 1. Pre-compute CREATE3 addresses needed for PYUSDX + IssuerGateway phase
        address predictedPYUSDX = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDX"));
        address predictedIssuerGateway = _getCreate3Address(deployer, _computeSalt(deployer, "IssuerGateway"));

        console.log("Predicted PYUSDX proxy:            ", predictedPYUSDX);
        console.log("Predicted IssuerGateway proxy:     ", predictedIssuerGateway);

        // 2. Deploy PYUSDX with deployer as transient admin/rateLimitManager for role bootstrapping
        address targetAdmin = pyusdxConfig.admin;
        address targetRateManager = pyusdxConfig.rateManager;

        pyusdxConfig.admin = deployer;
        pyusdxConfig.rateManager = deployer;

        (deployment.pyusdxProxy, deployment.pyusdxProxyAdmin, deployment.pyusdxImplementation) = _deployPYUSDX(
            deployer,
            predictedIssuerGateway,
            pyusdxConfig
        );

        require(deployment.pyusdxProxy == predictedPYUSDX, "PYUSDX proxy address mismatch");

        // 3. Deploy IssuerGateway (implementation needs actual PYUSDX proxy address)
        (
            deployment.issuerGatewayProxy,
            deployment.issuerGatewayProxyAdmin,
            deployment.issuerGatewayImplementation
        ) = _deployIssuerGateway(deployer, deployment.pyusdxProxy, issuerGatewayConfig);

        require(deployment.issuerGatewayProxy == predictedIssuerGateway, "IssuerGateway proxy address mismatch");

        // 4. Configure rate limits and transfer roles to target holders
        _bootstrapPYUSDXRoles(
            deployer,
            deployment.pyusdxProxy,
            deployment.issuerGatewayProxy,
            pyusdxConfig.earnerManager,
            targetAdmin,
            targetRateManager,
            issuerGatewayConfig
        );

        // 5. Pre-compute remaining CREATE3 addresses
        address predictedSwapFacility = _getCreate3Address(deployer, _computeSalt(deployer, "SwapFacility"));
        address predictedFactory = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDXExtensionFactory"));

        console.log("Predicted SwapFacility proxy:      ", predictedSwapFacility);
        console.log("Predicted Factory proxy:           ", predictedFactory);

        // 6. Deploy SwapFacility (implementation needs actual PYUSDX proxy + pre-computed Factory proxy)
        (
            deployment.swapFacilityProxy,
            deployment.swapFacilityProxyAdmin,
            deployment.swapFacilityImplementation
        ) = _deploySwapFacility(deployer, deployment.pyusdxProxy, predictedFactory, swapFacilityConfig);

        require(deployment.swapFacilityProxy == predictedSwapFacility, "SwapFacility proxy address mismatch");

        // 7. Deploy extension implementations
        address yieldToOneImpl = address(new YieldToOne(deployment.pyusdxProxy, deployment.swapFacilityProxy));
        address multiMintImpl = address(new MultiMint(deployment.pyusdxProxy, deployment.swapFacilityProxy));

        // 8. Deploy ExtensionBeacon behind TUP
        (deployment.beaconProxy, deployment.beaconProxyAdmin, deployment.beaconImplementation) = _deployBeacon(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            yieldToOneImpl,
            multiMintImpl,
            factoryConfig
        );

        // 9. Deploy Factory (implementation needs actual PYUSDX + SwapFacility + beacon proxies)
        //    Constructor validates swapFacility.pyusdx(), so SwapFacility must be deployed first
        (deployment.factoryProxy, deployment.factoryProxyAdmin, deployment.factoryImplementation) = _deployFactory(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            deployment.beaconProxy,
            factoryConfig
        );

        require(deployment.factoryProxy == predictedFactory, "Factory proxy address mismatch");
    }

    /// @dev Configures rate limits and transfers admin/rate-manager roles
    ///      from the deployer to the target holders, then renounces the deployer's roles.
    function _bootstrapPYUSDXRoles(
        address deployer,
        address pyusdxProxy,
        address issuerGatewayProxy,
        address earnerManager,
        address targetAdmin,
        address targetRateManager,
        IssuerGatewayConfig memory issuerGatewayConfig
    ) internal {
        // Configure rate limit for the IssuerGateway (deployer holds RATE_LIMIT_MANAGER_ROLE)
        IRateLimiter(pyusdxProxy).setRateLimit(
            issuerGatewayProxy,
            issuerGatewayConfig.rateLimitCapacity,
            issuerGatewayConfig.rateLimitRefillPerSecond,
            true
        );

        // TODO: figure out the appropriate cap at deployment
        // Configure rate limit for the earnerManager — distributeReward() flows through _mint
        IRateLimiter(pyusdxProxy).setRateLimit(earnerManager, type(uint128).max, 0, true);

        // Transfer roles to target holders
        bytes32 rateLimitManagerRole = IRateLimiter(pyusdxProxy).RATE_LIMIT_MANAGER_ROLE();
        bytes32 defaultAdminRole = 0x00;

        IAccessControl(pyusdxProxy).grantRole(rateLimitManagerRole, targetRateManager);
        IAccessControl(pyusdxProxy).grantRole(defaultAdminRole, targetAdmin);

        // Renounce deployer's transient roles
        IAccessControl(pyusdxProxy).renounceRole(rateLimitManagerRole, deployer);
        IAccessControl(pyusdxProxy).renounceRole(defaultAdminRole, deployer);
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

        // Deploy Portal (implementation needs actual PYUSDX + SwapFacility proxies)
        (deployment.portalProxy, deployment.portalProxyAdmin, deployment.portalImplementation) = _deployPortal(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            portalConfig
        );

        require(deployment.portalProxy == predictedPortal, "Portal proxy address mismatch");

        // Deploy LayerZeroBridgeAdapter (implementation needs actual Portal proxy)
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
