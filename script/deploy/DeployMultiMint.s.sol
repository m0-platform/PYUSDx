// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";

import { DeployBase } from "./DeployBase.s.sol";

contract DeployMultiMint is DeployBase {
    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        string memory extensionName = vm.envString("EXTENSION_NAME");
        address factory = _getFactory();

        IExtensionFactory.MultiMintParams memory params = IExtensionFactory.MultiMintParams({
            name: vm.envString("EXTENSION_TOKEN_NAME"),
            symbol: vm.envString("EXTENSION_TOKEN_SYMBOL"),
            yieldRecipient: vm.envAddress("YIELD_RECIPIENT"),
            admin: vm.envAddress("ADMIN"),
            assetCapManager: vm.envAddress("ASSET_CAP_MANAGER"),
            freezeManager: vm.envAddress("FREEZE_MANAGER"),
            pauser: vm.envAddress("PAUSER"),
            yieldRecipientManager: vm.envAddress("YIELD_RECIPIENT_MANAGER"),
            versionManager: vm.envAddress("VERSION_MANAGER")
        });

        vm.startBroadcast(deployer);

        (address proxy, address implementation) = ExtensionFactory(factory).deployMultiMint(extensionName, params);

        vm.stopBroadcast();

        console.log("MultiMint Implementation:", implementation);
        console.log("MultiMint Proxy:         ", proxy);

        _writeDeployment(block.chainid, _getExtensionName(), proxy);

        console.log("");
        console.log("NOTE: Extension is NOT yet approved in SwapFacility.");
        console.log("      A FACTORY_MANAGER_ROLE holder must call:");
        console.log("      ExtensionFactory.setExtensionType(<proxy>, MULTI_MINT)");
        console.log("      before swaps against this extension can succeed.");
    }
}
