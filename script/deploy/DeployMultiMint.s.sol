// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { console } from "../../lib/forge-std/src/console.sol";

import { PYUSDXExtensionFactory } from "../../src/deploy/PYUSDXExtensionFactory.sol";

import { DeployBase } from "./DeployBase.s.sol";

contract DeployMultiMint is DeployBase {
    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        MultiMintConfig memory config = _loadMultiMintConfig();
        address factory = _getFactory();

        vm.startBroadcast(deployer);

        (address proxy, address proxyAdmin, address implementation) = PYUSDXExtensionFactory(factory).deployMultiMint(
            config.name,
            config.symbol,
            config.yieldRecipient,
            config.admin,
            config.assetCapManager,
            config.freezeManager,
            config.pauser,
            config.yieldRecipientManager
        );

        vm.stopBroadcast();

        console.log("MultiMint Implementation:", implementation);
        console.log("MultiMint Proxy:         ", proxy);
        console.log("MultiMint ProxyAdmin:    ", proxyAdmin);

        _writeDeployment(block.chainid, _getExtensionName(), proxy);
    }

    function _loadMultiMintConfig() private view returns (MultiMintConfig memory config) {
        config.name = vm.envString("EXTENSION_NAME");
        config.symbol = vm.envString("EXTENSION_SYMBOL");
        config.yieldRecipient = vm.envAddress("YIELD_RECIPIENT");
        config.admin = vm.envAddress("ADMIN");
        config.assetCapManager = vm.envAddress("ASSET_CAP_MANAGER");
        config.freezeManager = vm.envAddress("FREEZE_MANAGER");
        config.pauser = vm.envAddress("PAUSER");
        config.yieldRecipientManager = vm.envAddress("YIELD_RECIPIENT_MANAGER");
    }
}
