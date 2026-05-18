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
                config.operator,
                config.executor,
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
            portalConfig,
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
        PortalConfig memory portalConfig,
        CoreDeployments memory deployment
    ) internal {
        // Phase 1: PYUSDX + IssuerGateway + role bootstrap. Extracted into its own
        // function so its locals release before the SwapFacility/Factory phase below
        // (otherwise this function exceeds Solidity's stack-depth limit).
        _deployPYUSDXAndIssuerGateway(deployer, pyusdxConfig, issuerGatewayConfig, portalConfig, deployment);

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

        // 8. Deploy two separate ExtensionBeacons behind Transparent Upgradeable Proxies
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

        // 9. Deploy Factory (implementation needs actual PYUSDX + SwapFacility + both beacon proxies)
        //    Constructor validates swapFacility.pyusdx(), so SwapFacility must be deployed first
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
        PortalConfig memory portalConfig,
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

        // 4. Configure rate limits and transfer roles to target holders.
        //    Portal is granted ISSUER_ROLE + rate limit at its predicted CREATE3 address,
        //    while the deployer still holds DEFAULT_ADMIN_ROLE / RATE_LIMIT_MANAGER_ROLE.
        //    Portal needs both to mint on receiveMessage and burn on sendToken (cross-chain).
        _bootstrapPYUSDXRoles(
            deployer,
            deployment.pyusdxProxy,
            _buildIssuerBootstrap(
                deployer,
                deployment.issuerGatewayProxy,
                pyusdxConfig.earnerManager,
                issuerGatewayConfig,
                portalConfig
            ),
            targetAdmin,
            targetRateManager
        );
    }

    /// @dev Extracted into its own function to keep _deployPYUSDXAndIssuerGateway
    ///      under the legacy pipeline's stack-depth limit.
    function _buildIssuerBootstrap(
        address deployer,
        address issuerGatewayProxy,
        address earnerManager,
        IssuerGatewayConfig memory issuerGatewayConfig,
        PortalConfig memory portalConfig
    ) internal view returns (IssuerBootstrap memory) {
        return
            IssuerBootstrap({
                issuerGatewayProxy: issuerGatewayProxy,
                portalProxy: _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDXPortal")),
                earnerManager: earnerManager,
                issuerGatewayCapacity: issuerGatewayConfig.rateLimitCapacity,
                issuerGatewayRefill: issuerGatewayConfig.rateLimitRefillPerSecond,
                portalCapacity: portalConfig.rateLimitCapacity,
                portalRefill: portalConfig.rateLimitRefillPerSecond
            });
    }

    /// @dev Bundle of issuers + their rate-limit caps that the deployer configures on PYUSDX
    ///      before renouncing its transient admin/rate-manager roles. Grouped into a struct
    ///      to keep the bootstrap function under Solidity's stack-depth limit.
    struct IssuerBootstrap {
        address issuerGatewayProxy;
        address portalProxy; // predicted CREATE3 address — Portal not yet deployed
        address earnerManager;
        uint128 issuerGatewayCapacity;
        uint128 issuerGatewayRefill;
        uint128 portalCapacity;
        uint128 portalRefill;
    }

    /// @dev Configures rate limits, grants ISSUER_ROLE to the Portal so it can mint/burn
    ///      for cross-chain transfers, and transfers admin/rate-manager roles from the
    ///      deployer to the target holders, then renounces the deployer's roles.
    ///      Granting Portal at its predicted CREATE3 address (before it's deployed) is fine —
    ///      AccessControl just stores in a mapping, and the rate-limit bucket is keyed by
    ///      address regardless of deployment status.
    function _bootstrapPYUSDXRoles(
        address deployer,
        address pyusdxProxy,
        IssuerBootstrap memory issuers,
        address targetAdmin,
        address targetRateManager
    ) internal {
        // Configure rate limit for the IssuerGateway (deployer holds RATE_LIMIT_MANAGER_ROLE)
        IRateLimiter(pyusdxProxy).setRateLimit(
            issuers.issuerGatewayProxy,
            issuers.issuerGatewayCapacity,
            issuers.issuerGatewayRefill,
            true
        );

        // Configure rate limit for the Portal — sendToken/receiveMessage flow through PYUSDX burn/mint.
        // Without this, mint reverts with RateLimitNotConfigured(portal) and the destination
        // chain executor's simulation reverts before delivering the cross-chain message.
        IRateLimiter(pyusdxProxy).setRateLimit(issuers.portalProxy, issuers.portalCapacity, issuers.portalRefill, true);

        // Configure rate limit for the earnerManager — distributeReward() flows through _mint.
        // Allows ~$10M/day in PYUSDX yield distributions (PYUSDX has 6 decimals).
        // Capacity = one day of mint headroom; refill replenishes the bucket every 24h.
        uint128 earnerDailyCap = 10_000_000e6;
        IRateLimiter(pyusdxProxy).setRateLimit(
            issuers.earnerManager,
            earnerDailyCap,
            earnerDailyCap / uint128(1 days),
            true
        );

        // Grant ISSUER_ROLE to Portal so it can burn (sendToken) and mint (receiveMessage)
        // for cross-chain transfers. Listed in roles.md alongside IssuerGateway as the only
        // two contracts that should hold ISSUER_ROLE on PYUSDX.
        IAccessControl(pyusdxProxy).grantRole(PYUSDX(pyusdxProxy).ISSUER_ROLE(), issuers.portalProxy);

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
