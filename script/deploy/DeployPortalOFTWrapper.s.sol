// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { IERC20Metadata } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { DeployBase } from "./DeployBase.s.sol";

contract DeployPortalOFTWrapper is DeployBase {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        console.log("Deployer:                        ", deployer);

        address portal = _getPortal();
        address layerZeroBridgeAdapter = _getLayerZeroBridgeAdapter();

        // The token the wrapper represents: a PYUSDX Extension set via PORTAL_OFT_WRAPPER_TOKEN,
        // or PYUSDX itself (from deployments/<chainid>.json, falling back to the PYUSDX env var)
        // when the variable is unset or empty. Read as a string and parsed explicitly so a
        // malformed address reverts instead of silently deploying the PYUSDX wrapper.
        address pyusdx = _getPYUSDX();
        string memory tokenValue = vm.envOr("PORTAL_OFT_WRAPPER_TOKEN", string(""));
        address token = bytes(tokenValue).length == 0 ? pyusdx : vm.parseAddress(tokenValue);
        string memory tokenSymbol = IERC20Metadata(token).symbol();

        PortalOFTWrapperConfig memory config = PortalOFTWrapperConfig({
            admin: vm.envAddress("PORTAL_OFT_WRAPPER_ADMIN"),
            operator: vm.envAddress("PORTAL_OFT_WRAPPER_OPERATOR")
        });

        vm.startBroadcast(deployer);

        (address proxy, address proxyAdmin, address implementation) = _deployPortalOFTWrapper(
            deployer,
            portal,
            token,
            layerZeroBridgeAdapter,
            tokenSymbol,
            config
        );

        vm.stopBroadcast();

        console.log("================================================================================");
        console.log("PortalOFTWrapper Token:          ", token);
        console.log("PortalOFTWrapper Proxy:          ", proxy);
        console.log("PortalOFTWrapper ProxyAdmin:     ", proxyAdmin);
        console.log("PortalOFTWrapper Implementation: ", implementation);
        console.log("PortalOFTWrapper Admin:          ", config.admin);
        console.log("PortalOFTWrapper Operator:       ", config.operator);
        console.log("================================================================================");

        _writeDeployment(
            block.chainid,
            token == pyusdx ? "pyusdxPortalOFTWrapper" : string.concat(tokenSymbol, "PortalOFTWrapper"),
            proxy
        );
    }
}
