// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { DeployBase } from "./DeployBase.s.sol";

contract DeployAll is DeployBase {
    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        PYUSDXConfig memory pyusdxConfig = _loadPYUSDXConfig();
        MinterGatewayConfig memory minterConfig = _loadMinterGatewayConfig();
        SwapFacilityConfig memory swapConfig = _loadSwapFacilityConfig();
        FactoryConfig memory factoryConfig = _loadFactoryConfig();

        vm.startBroadcast(deployer);

        CoreDeployments memory deployment = _deployCore(
            deployer,
            pyusdxConfig,
            minterConfig,
            swapConfig,
            factoryConfig
        );

        vm.stopBroadcast();

        console.log("================================================================================");
        console.log("PYUSDX Proxy:                     ", deployment.pyusdxProxy);
        console.log("PYUSDX ProxyAdmin:                ", deployment.pyusdxProxyAdmin);
        console.log("PYUSDX Implementation:            ", deployment.pyusdxImplementation);
        console.log("MinterGateway Proxy:              ", deployment.minterGatewayProxy);
        console.log("MinterGateway ProxyAdmin:         ", deployment.minterGatewayProxyAdmin);
        console.log("MinterGateway Implementation:     ", deployment.minterGatewayImplementation);
        console.log("SwapFacility Proxy:               ", deployment.swapFacilityProxy);
        console.log("SwapFacility ProxyAdmin:          ", deployment.swapFacilityProxyAdmin);
        console.log("SwapFacility Implementation:      ", deployment.swapFacilityImplementation);
        console.log("Factory Proxy:                    ", deployment.factoryProxy);
        console.log("Factory ProxyAdmin:               ", deployment.factoryProxyAdmin);
        console.log("Factory Implementation:           ", deployment.factoryImplementation);
        console.log("================================================================================");

        _writeDeployment(block.chainid, "pyusdx", deployment.pyusdxProxy);
        _writeDeployment(block.chainid, "minterGateway", deployment.minterGatewayProxy);
        _writeDeployment(block.chainid, "swapFacility", deployment.swapFacilityProxy);
        _writeDeployment(block.chainid, "extensionFactory", deployment.factoryProxy);
    }

    function _loadPYUSDXConfig() private view returns (PYUSDXConfig memory config) {
        config.name = vm.envString("PYUSDX_NAME");
        config.symbol = vm.envString("PYUSDX_SYMBOL");
        config.admin = vm.envAddress("PYUSDX_ADMIN");
        config.pauser = vm.envAddress("PYUSDX_PAUSER");
        config.freezeManager = vm.envAddress("PYUSDX_FREEZE_MANAGER");
        config.forcedTransferManager = vm.envAddress("PYUSDX_FORCED_TRANSFER_MANAGER");
        config.earnerManager = vm.envAddress("PYUSDX_EARNER_MANAGER");
        config.rateManager = vm.envAddress("PYUSDX_RATE_MANAGER");
    }

    function _loadMinterGatewayConfig() private view returns (MinterGatewayConfig memory config) {
        config.admin = vm.envAddress("MINTER_GATEWAY_ADMIN");
        config.minter = vm.envAddress("MINTER_GATEWAY_MINTER");
        config.mintDelay = uint32(vm.envUint("MINTER_GATEWAY_MINT_DELAY"));
        config.mintTTL = uint32(vm.envUint("MINTER_GATEWAY_MINT_TTL"));
    }

    function _loadSwapFacilityConfig() private view returns (SwapFacilityConfig memory config) {
        config.admin = vm.envAddress("SWAP_FACILITY_ADMIN");
        config.pauser = vm.envAddress("SWAP_FACILITY_PAUSER");
    }

    function _loadFactoryConfig() private view returns (FactoryConfig memory config) {
        config.admin = vm.envAddress("FACTORY_ADMIN");
        config.factoryManager = vm.envAddress("FACTORY_MANAGER");
    }
}
