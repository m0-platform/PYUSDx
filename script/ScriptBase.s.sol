// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Config } from "./Config.sol";

import { Script } from "../lib/forge-std/src/Script.sol";

contract ScriptBase is Script, Config {
    struct Deployments {
        address[] extensionAddresses;
        string[] extensionNames;
        address extensionFactory;
        address issuerGateway;
        address layerZeroBridgeAdapter;
        address portal;
        address pyusdx;
        address swapFacility;
    }

    function _getExtensionName() internal view returns (string memory) {
        return vm.envString("EXTENSION_NAME");
    }

    function _setExtensionDeployment(
        Deployments memory deployments_,
        string memory key_,
        address value_
    ) internal pure returns (Deployments memory) {
        bool append = true;
        for (uint256 i = 0; i < deployments_.extensionNames.length; i++) {
            if (keccak256(bytes(deployments_.extensionNames[i])) == keccak256(bytes(key_))) {
                deployments_.extensionNames[i] = key_;
                deployments_.extensionAddresses[i] = value_;
                append = false;
                break;
            }
        }

        if (append) {
            string[] memory nameReplacements = new string[](deployments_.extensionNames.length + 1);
            address[] memory addressReplacements = new address[](deployments_.extensionNames.length + 1);

            for (uint256 i = 0; i < deployments_.extensionNames.length; i++) {
                nameReplacements[i] = deployments_.extensionNames[i];
                addressReplacements[i] = deployments_.extensionAddresses[i];
            }

            nameReplacements[nameReplacements.length - 1] = key_;
            addressReplacements[addressReplacements.length - 1] = value_;

            deployments_.extensionNames = nameReplacements;
            deployments_.extensionAddresses = addressReplacements;
        }

        return deployments_;
    }

    function _deployOutputPath(uint256 chainId_) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", vm.toString(chainId_), ".json");
    }

    function _writeDeployment(uint256 chainId_, string memory key_, address value_) internal {
        string memory root = "";

        Deployments memory deployments_ = vm.isFile(_deployOutputPath(chainId_))
            ? _readDeployment(chainId_)
            : Deployments(
                new address[](0),
                new string[](0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            );

        if (
            keccak256(bytes(key_)) != keccak256(bytes("pyusdx")) &&
            keccak256(bytes(key_)) != keccak256(bytes("issuerGateway")) &&
            keccak256(bytes(key_)) != keccak256(bytes("swapFacility")) &&
            keccak256(bytes(key_)) != keccak256(bytes("extensionFactory")) &&
            keccak256(bytes(key_)) != keccak256(bytes("layerZeroBridgeAdapter")) &&
            keccak256(bytes(key_)) != keccak256(bytes("portal"))
        ) {
            deployments_ = _setExtensionDeployment(deployments_, key_, value_);
        }

        vm.serializeAddress(
            root,
            "pyusdx",
            keccak256(bytes(key_)) == keccak256("pyusdx") ? value_ : deployments_.pyusdx
        );

        vm.serializeAddress(
            root,
            "issuerGateway",
            keccak256(bytes(key_)) == keccak256("issuerGateway") ? value_ : deployments_.issuerGateway
        );

        vm.serializeAddress(
            root,
            "swapFacility",
            keccak256(bytes(key_)) == keccak256("swapFacility") ? value_ : deployments_.swapFacility
        );

        vm.serializeAddress(
            root,
            "extensionFactory",
            keccak256(bytes(key_)) == keccak256("extensionFactory") ? value_ : deployments_.extensionFactory
        );

        vm.serializeAddress(
            root,
            "layerZeroBridgeAdapter",
            keccak256(bytes(key_)) == keccak256("layerZeroBridgeAdapter") ? value_ : deployments_.layerZeroBridgeAdapter
        );

        vm.serializeAddress(
            root,
            "portal",
            keccak256(bytes(key_)) == keccak256("portal") ? value_ : deployments_.portal
        );

        vm.serializeString(root, "extensionNames", deployments_.extensionNames);

        vm.writeJson(
            vm.serializeAddress(root, "extensionAddresses", deployments_.extensionAddresses),
            _deployOutputPath(chainId_)
        );
    }

    function _readDeployment(uint256 chainId_) internal view returns (Deployments memory) {
        if (!vm.isFile(_deployOutputPath(chainId_))) {
            return
                Deployments(
                    new address[](0),
                    new string[](0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0)
                );
        }

        bytes memory data = vm.parseJson(vm.readFile(_deployOutputPath(chainId_)));

        return abi.decode(data, (Deployments));
    }

    function _getPYUSDX() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.pyusdx == address(0)) {
            return vm.envAddress("PYUSDX");
        } else {
            return deployments_.pyusdx;
        }
    }

    function _getIssuerGateway() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.issuerGateway == address(0)) {
            return vm.envAddress("ISSUER_GATEWAY");
        } else {
            return deployments_.issuerGateway;
        }
    }

    function _getSwapFacility() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.swapFacility == address(0)) {
            return vm.envAddress("SWAP_FACILITY");
        } else {
            return deployments_.swapFacility;
        }
    }

    function _getFactory() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.extensionFactory == address(0)) {
            return vm.envAddress("EXTENSION_FACTORY");
        } else {
            return deployments_.extensionFactory;
        }
    }

    function _getLayerZeroBridgeAdapter() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.layerZeroBridgeAdapter == address(0)) {
            return vm.envAddress("LAYER_ZERO_BRIDGE_ADAPTER");
        } else {
            return deployments_.layerZeroBridgeAdapter;
        }
    }

    function _getPortal() internal view returns (address) {
        Deployments memory deployments_ = _readDeployment(block.chainid);
        if (deployments_.portal == address(0)) {
            return vm.envAddress("PORTAL");
        } else {
            return deployments_.portal;
        }
    }
}
