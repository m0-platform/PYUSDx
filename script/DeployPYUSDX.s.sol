// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { PYUSDX } from "../src/PYUSDX.sol";

/**
 * @title DeployPYUSDX
 * @notice Deployment script for PYUSDX token contract
 *
 * Deployment Process:
 * 1. Deploy PYUSDX implementation contract
 * 2. Deploy ERC1967 proxy pointing to implementation
 * 3. Initialize proxy with constructor parameters
 *
 * Constructor Parameters:
 * - _minterGateway: Address of the Minter Gateway contract (must be non-zero)
 * - _pyusd: Address of the PYUSD token contract (must be non-zero)
 *
 * Post-Deployment Setup:
 * 1. Grant roles to appropriate addresses:
 *    - RATE_MANAGER_ROLE: Can set yield rates
 *    - EARNER_MANAGER_ROLE: Can manage earner whitelist and fee settings
 *    - FREEZE_MANAGER_ROLE: Can freeze/unfreeze accounts
 *    - FORCED_TRANSFER_MANAGER_ROLE: Can force transfer from frozen accounts
 *    - PAUSER_ROLE: Can pause/unpause the contract
 * 2. Set initial yield rate (optional, starts at 0)
 * 3. Approve earners via EARNER_MANAGER_ROLE
 *
 * Storage Layout:
 * - Uses ERC-7201 namespaced storage pattern
 * - Storage slot: 0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500
 * - Namespace: "M0.storage.PYUSDX"
 *
 * Upgrade Safety:
 * - Implementation can be upgraded by updating proxy
 * - Storage layout must be preserved across upgrades
 * - For storage changes, use new namespace (e.g., "M0.storage.PYUSDX.v2")
 *
 * Initial State:
 * - Name: "PYUSDX"
 * - Symbol: "PYUSDX"
 * - Decimals: 6 (matches PYUSD)
 * - Initial Index: 1e12 (PRECISION)
 * - Initial Rate: 0 (no yield until set)
 * - Paused: false
 */
contract DeployPYUSDX is Script {
    PYUSDX public implementation;
    ERC1967Proxy public proxy;
    PYUSDX public pyusdx;

    // Address of the Minter Gateway contract
    address constant MINTER_GATEWAY = 0x0000000000000000000000000000000000000000; // UPDATE BEFORE DEPLOYMENT

    // Address of the PYUSD token contract
    address constant PYUSD = 0x0000000000000000000000000000000000000000; // UPDATE BEFORE DEPLOYMENT

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying PYUSDX with:");
        console.log("  Deployer:", deployer);
        console.log("  Minter Gateway:", MINTER_GATEWAY);
        console.log("  PYUSD:", PYUSD);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation contract
        implementation = new PYUSDX(MINTER_GATEWAY, PYUSD);
        console.log("Implementation deployed:", address(implementation));

        // Deploy proxy with initialize call
        bytes memory initData = abi.encodeWithSelector(
            PYUSDX.initialize.selector,
            deployer // DEFAULT_ADMIN_ROLE
        );

        proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed:", address(proxy));

        vm.stopBroadcast();

        // Get PYUSDX interface from proxy
        pyusdx = PYUSDX(address(proxy));

        // Verify deployment
        _verifyDeployment();

        // Output role addresses for granting
        _outputRoles();
    }

    function _verifyDeployment() internal view {
        console.log("\n=== Verification ===");
        console.log("Name:", pyusdx.name());
        console.log("Symbol:", pyusdx.symbol());
        console.log("Decimals:", pyusdx.decimals());
        console.log("Initial Index:", pyusdx.currentIndex());
        console.log("Initial Rate:", pyusdx.rate());
        console.log("Total Supply:", pyusdx.totalSupply());
        console.log("Paused:", pyusdx.paused());
    }

    function _outputRoles() internal view {
        bytes32 rateManagerRole = pyusdx.RATE_MANAGER_ROLE();
        bytes32 earnerManagerRole = pyusdx.EARNER_MANAGER_ROLE();
        bytes32 freezeManagerRole = pyusdx.FREEZE_MANAGER_ROLE();
        bytes32 forcedTransferManagerRole = pyusdx.FORCED_TRANSFER_MANAGER_ROLE();
        bytes32 pauserRole = pyusdx.PAUSER_ROLE();

        console.log("\n=== Role Hashes ===");
        console.log("RATE_MANAGER_ROLE:", vm.toString(rateManagerRole));
        console.log("EARNER_MANAGER_ROLE:", vm.toString(earnerManagerRole));
        console.log("FREEZE_MANAGER_ROLE:", vm.toString(freezeManagerRole));
        console.log("FORCED_TRANSFER_MANAGER_ROLE:", vm.toString(forcedTransferManagerRole));
        console.log("PAUSER_ROLE:", vm.toString(pauserRole));
    }
}
