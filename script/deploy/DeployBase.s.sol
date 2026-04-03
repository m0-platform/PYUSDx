// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { DeployHelpers } from "../../lib/evm-m-extensions/lib/common/script/deploy/DeployHelpers.sol";

import { Upgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IssuerGateway } from "../../src/core/IssuerGateway.sol";
import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";
import { VersionedBeacon } from "../../src/platform/VersionedBeacon.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { YieldToOne } from "../../src/platform/projects/YieldToOne.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";

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
        address factoryProxy;
        address factoryProxyAdmin;
        address factoryImplementation;
        address versionedBeacon;
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

    function _deployVersionedBeacon(
        address factoryProxy,
        address pyusdxProxy,
        address swapFacilityProxy,
        address admin,
        address versionManager,
        address pauseManager,
        address freezeManager
    ) internal returns (address) {
        return
            address(
                new VersionedBeacon(
                    factoryProxy,
                    pyusdxProxy,
                    swapFacilityProxy,
                    admin,
                    versionManager,
                    pauseManager,
                    freezeManager
                )
            );
    }

    function _deployFactory(
        address deployer,
        address pyusdxProxy,
        address swapFacilityProxy,
        address versionedBeacon,
        address yieldToOneImpl,
        address multiMintImpl,
        FactoryConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        // NOTE: SwapFacility must already be deployed since constructor calls ISwapFacility(swapFacility).pyusdx()
        implementation = address(new ExtensionFactory(pyusdxProxy, swapFacilityProxy, versionedBeacon));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(
                ExtensionFactory.initialize.selector,
                config.admin,
                config.factoryManager,
                yieldToOneImpl,
                multiMintImpl
            ),
            _computeSalt(deployer, "PYUSDXExtensionFactory")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    /* ============ Core Stack Orchestrator ============ */

    function _deployCore(
        address deployer,
        PYUSDXConfig memory pyusdxConfig,
        IssuerGatewayConfig memory issuerGatewayConfig,
        SwapFacilityConfig memory swapFacilityConfig,
        FactoryConfig memory factoryConfig
    ) internal returns (CoreDeployments memory deployment) {
        // 1. Pre-compute CREATE3 addresses for all 4 proxies
        address predictedPYUSDX = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDX"));
        address predictedIssuerGateway = _getCreate3Address(deployer, _computeSalt(deployer, "IssuerGateway"));
        address predictedSwapFacility = _getCreate3Address(deployer, _computeSalt(deployer, "SwapFacility"));
        address predictedFactory = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDXExtensionFactory"));

        console.log("Predicted PYUSDX proxy:            ", predictedPYUSDX);
        console.log("Predicted IssuerGateway proxy:     ", predictedIssuerGateway);
        console.log("Predicted SwapFacility proxy:      ", predictedSwapFacility);
        console.log("Predicted Factory proxy:           ", predictedFactory);

        // 2. Deploy PYUSDX (implementation needs pre-computed IssuerGateway proxy address)
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

        // 4. Deploy SwapFacility (implementation needs actual PYUSDX proxy + pre-computed Factory proxy)
        (
            deployment.swapFacilityProxy,
            deployment.swapFacilityProxyAdmin,
            deployment.swapFacilityImplementation
        ) = _deploySwapFacility(deployer, deployment.pyusdxProxy, predictedFactory, swapFacilityConfig);

        require(deployment.swapFacilityProxy == predictedSwapFacility, "SwapFacility proxy address mismatch");

        // 5. Deploy extension implementations
        address yieldToOneImpl = address(new YieldToOne(deployment.pyusdxProxy, deployment.swapFacilityProxy));
        address multiMintImpl = address(new MultiMint(deployment.pyusdxProxy, deployment.swapFacilityProxy));

        // 6. Deploy VersionedBeacon (uses pre-computed factory address, not a proxy itself)
        deployment.versionedBeacon = _deployVersionedBeacon(
            predictedFactory,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            factoryConfig.admin,
            factoryConfig.versionManager,
            factoryConfig.pauseManager,
            factoryConfig.freezeManager
        );

        console.log("VersionedBeacon:                  ", deployment.versionedBeacon);

        // 7. Deploy Factory (implementation needs actual PYUSDX + SwapFacility proxies + beacon)
        //    Constructor validates swapFacility.pyusdx(), so SwapFacility must be deployed first
        (deployment.factoryProxy, deployment.factoryProxyAdmin, deployment.factoryImplementation) = _deployFactory(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            deployment.versionedBeacon,
            yieldToOneImpl,
            multiMintImpl,
            factoryConfig
        );

        require(deployment.factoryProxy == predictedFactory, "Factory proxy address mismatch");
    }
}
