// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { PYUSDXFaucet } from "../../src/periphery/PYUSDXFaucet.sol";

import { ScriptBase } from "../ScriptBase.s.sol";

contract DeployPYUSDXFaucet is ScriptBase {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        address pyusdx = _getPYUSDX();

        console.log("Deployer:    ", deployer);
        console.log("PYUSDx:      ", pyusdx);

        vm.startBroadcast(deployer);

        PYUSDXFaucet faucet = new PYUSDXFaucet(pyusdx);

        vm.stopBroadcast();

        console.log("PYUSDXFaucet:", address(faucet));
    }
}
