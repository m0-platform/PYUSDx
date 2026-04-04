// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";

import { DeployBase } from "./DeployBase.s.sol";

contract DeployYieldToOne is DeployBase {
    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        string memory extensionName = vm.envString("EXTENSION_NAME");
        address factory = _getFactory();

        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: vm.envString("EXTENSION_TOKEN_NAME"),
            symbol: vm.envString("EXTENSION_TOKEN_SYMBOL"),
            yieldRecipient: vm.envAddress("YIELD_RECIPIENT"),
            admin: vm.envAddress("ADMIN"),
            freezeManager: vm.envAddress("FREEZE_MANAGER"),
            pauser: vm.envAddress("PAUSER"),
            yieldRecipientManager: vm.envAddress("YIELD_RECIPIENT_MANAGER")
        });

        vm.startBroadcast(deployer);

        (address proxy, address proxyAdmin, address implementation) = ExtensionFactory(factory).deployYieldToOne(
            extensionName,
            params
        );

        vm.stopBroadcast();

        console.log("YieldToOne Implementation:", implementation);
        console.log("YieldToOne Proxy:         ", proxy);
        console.log("YieldToOne ProxyAdmin:    ", proxyAdmin);

        _writeDeployment(block.chainid, _getExtensionName(), proxy);
    }
}
