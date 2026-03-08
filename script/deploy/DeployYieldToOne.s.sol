// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { console } from "../../lib/forge-std/src/console.sol";

import { PYUSDXExtensionFactory } from "../../src/platform/PYUSDXExtensionFactory.sol";

import { DeployBase } from "./DeployBase.s.sol";

contract DeployYieldToOne is DeployBase {
    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        YieldToOneConfig memory config = _loadYieldToOneConfig();
        address factory = _getFactory();

        vm.startBroadcast(deployer);

        (address proxy, address proxyAdmin, address implementation) = PYUSDXExtensionFactory(factory).deployYieldToOne(
            config.name,
            config.symbol,
            config.yieldRecipient,
            config.admin,
            config.freezeManager,
            config.yieldRecipientManager,
            config.pauser
        );

        vm.stopBroadcast();

        console.log("YieldToOne Implementation:", implementation);
        console.log("YieldToOne Proxy:         ", proxy);
        console.log("YieldToOne ProxyAdmin:    ", proxyAdmin);

        _writeDeployment(block.chainid, _getExtensionName(), proxy);
    }

    function _loadYieldToOneConfig() private view returns (YieldToOneConfig memory config) {
        config.name = vm.envString("EXTENSION_NAME");
        config.symbol = vm.envString("EXTENSION_SYMBOL");
        config.yieldRecipient = vm.envAddress("YIELD_RECIPIENT");
        config.admin = vm.envAddress("ADMIN");
        config.freezeManager = vm.envAddress("FREEZE_MANAGER");
        config.yieldRecipientManager = vm.envAddress("YIELD_RECIPIENT_MANAGER");
        config.pauser = vm.envAddress("PAUSER");
    }
}
