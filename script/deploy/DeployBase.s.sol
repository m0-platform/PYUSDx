// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { console } from "../../lib/forge-std/src/console.sol";

import { DeployHelpers } from "../../lib/evm-m-extensions/lib/common/script/deploy/DeployHelpers.sol";

import { Upgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MinterGateway } from "../../src/MinterGateway.sol";
import { PYUSDX } from "../../src/PYUSDX.sol";
import { PYUSDXExtensionFactory } from "../../src/deploy/PYUSDXExtensionFactory.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";

import { ScriptBase } from "../ScriptBase.s.sol";

contract DeployBase is DeployHelpers, ScriptBase {
    struct CoreDeployments {
        address pyusdxProxy;
        address pyusdxProxyAdmin;
        address pyusdxImplementation;
        address minterGatewayProxy;
        address minterGatewayProxyAdmin;
        address minterGatewayImplementation;
        address swapFacilityProxy;
        address swapFacilityProxyAdmin;
        address swapFacilityImplementation;
        address factoryProxy;
        address factoryProxyAdmin;
        address factoryImplementation;
    }

    /* ============ Individual Deploy Functions ============ */

    function _deployPYUSDX(
        address deployer,
        address minterGatewayProxy,
        PYUSDXConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new PYUSDX(minterGatewayProxy));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(
                PYUSDX.initialize.selector,
                config.name,
                config.symbol,
                config.admin,
                config.pauser,
                config.freezeManager,
                config.forcedTransferManager,
                config.earnerManager,
                config.rateManager
            ),
            _computeSalt(deployer, "PYUSDX")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployMinterGateway(
        address deployer,
        address pyusdxProxy,
        MinterGatewayConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        implementation = address(new MinterGateway(pyusdxProxy));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(
                MinterGateway.initialize.selector,
                config.admin,
                config.minter,
                config.mintDelay,
                config.mintTTL
            ),
            _computeSalt(deployer, "MinterGateway")
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
        FactoryConfig memory config
    ) internal returns (address proxy, address proxyAdmin, address implementation) {
        // NOTE: SwapFacility must already be deployed since constructor calls ISwapFacility(swapFacility).pyusdx()
        implementation = address(new PYUSDXExtensionFactory(pyusdxProxy, swapFacilityProxy));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(PYUSDXExtensionFactory.initialize.selector, config.admin, config.factoryManager),
            _computeSalt(deployer, "PYUSDXExtensionFactory")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    /* ============ Core Stack Orchestrator ============ */

    function _deployCore(
        address deployer,
        PYUSDXConfig memory pyusdxConfig,
        MinterGatewayConfig memory minterGatewayConfig,
        SwapFacilityConfig memory swapFacilityConfig,
        FactoryConfig memory factoryConfig
    ) internal returns (CoreDeployments memory deployment) {
        // 1. Pre-compute CREATE3 addresses for all 4 proxies
        address predictedPYUSDX = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDX"));
        address predictedMinterGateway = _getCreate3Address(deployer, _computeSalt(deployer, "MinterGateway"));
        address predictedSwapFacility = _getCreate3Address(deployer, _computeSalt(deployer, "SwapFacility"));
        address predictedFactory = _getCreate3Address(deployer, _computeSalt(deployer, "PYUSDXExtensionFactory"));

        console.log("Predicted PYUSDX proxy:            ", predictedPYUSDX);
        console.log("Predicted MinterGateway proxy:     ", predictedMinterGateway);
        console.log("Predicted SwapFacility proxy:      ", predictedSwapFacility);
        console.log("Predicted Factory proxy:           ", predictedFactory);

        // 2. Deploy PYUSDX (implementation needs pre-computed MinterGateway proxy address)
        (deployment.pyusdxProxy, deployment.pyusdxProxyAdmin, deployment.pyusdxImplementation) = _deployPYUSDX(
            deployer,
            predictedMinterGateway,
            pyusdxConfig
        );

        require(deployment.pyusdxProxy == predictedPYUSDX, "PYUSDX proxy address mismatch");

        // 3. Deploy MinterGateway (implementation needs actual PYUSDX proxy address)
        (
            deployment.minterGatewayProxy,
            deployment.minterGatewayProxyAdmin,
            deployment.minterGatewayImplementation
        ) = _deployMinterGateway(deployer, deployment.pyusdxProxy, minterGatewayConfig);

        require(deployment.minterGatewayProxy == predictedMinterGateway, "MinterGateway proxy address mismatch");

        // 4. Deploy SwapFacility (implementation needs actual PYUSDX proxy + pre-computed Factory proxy)
        (
            deployment.swapFacilityProxy,
            deployment.swapFacilityProxyAdmin,
            deployment.swapFacilityImplementation
        ) = _deploySwapFacility(deployer, deployment.pyusdxProxy, predictedFactory, swapFacilityConfig);

        require(deployment.swapFacilityProxy == predictedSwapFacility, "SwapFacility proxy address mismatch");

        // 5. Deploy Factory (implementation needs actual PYUSDX + SwapFacility proxies)
        //    Constructor validates swapFacility.pyusdx(), so SwapFacility must be deployed first
        (deployment.factoryProxy, deployment.factoryProxyAdmin, deployment.factoryImplementation) = _deployFactory(
            deployer,
            deployment.pyusdxProxy,
            deployment.swapFacilityProxy,
            factoryConfig
        );

        require(deployment.factoryProxy == predictedFactory, "Factory proxy address mismatch");
    }
}
