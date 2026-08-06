// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { IMultiMint } from "../../src/platform/projects/interfaces/IMultiMint.sol";

import { ScriptBase } from "../ScriptBase.s.sol";

/// @title  ConfigureMultiMintAssetCap
/// @notice Sets (registers/updates/disables) the asset cap for a collateral type on a MultiMint extension.
/// @dev    Setting a non-zero cap registers `ASSET` as an allowed collateral backing the MultiMint token
///         (`isAllowedAsset` becomes true) and enables `wrap`/`replaceAsset` for it. Setting the cap to 0
///         disables both for that asset; existing backing remains unwrappable to PYUSDX.
///         The signer (PRIVATE_KEY) MUST hold ASSET_CAP_MANAGER_ROLE on the MultiMint extension.
///
///         The MultiMint address is resolved from deployments/<chainid>.json by EXTENSION_NAME, or
///         overridden directly via the MULTI_MINT env var. `ASSET_CAP` is denominated in `ASSET`'s decimals.
contract ConfigureMultiMintAssetCap is ScriptBase {
    function run() public {
        address caller = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        address multiMint = _getMultiMint();
        address asset = vm.envAddress("ASSET");
        uint256 cap = vm.envUint("ASSET_CAP");

        console.log("MultiMint: ", multiMint);
        console.log("Asset:     ", asset);
        console.log("Cap:       ", cap);
        console.log("Caller:    ", caller);

        vm.startBroadcast(caller);

        IMultiMint(multiMint).setAssetCap(asset, cap);

        vm.stopBroadcast();

        console.log("isAllowedAsset:", IMultiMint(multiMint).isAllowedAsset(asset));
        console.log("assetCap:      ", IMultiMint(multiMint).assetCap(asset));
        console.log("assetDecimals: ", IMultiMint(multiMint).assetDecimals(asset));
    }

    /// @dev    Resolves the MultiMint extension address, preferring the MULTI_MINT env override and
    ///         otherwise looking it up by EXTENSION_NAME in deployments/<chainid>.json.
    /// @return The MultiMint extension proxy address.
    function _getMultiMint() internal view returns (address) {
        address override_ = vm.envOr("MULTI_MINT", address(0));
        if (override_ != address(0)) return override_;

        string memory name = vm.envString("EXTENSION_NAME");
        Deployments memory deployments_ = _readDeployment(block.chainid);

        for (uint256 i; i < deployments_.extensionNames.length; ++i) {
            if (keccak256(bytes(deployments_.extensionNames[i])) == keccak256(bytes(name))) {
                return deployments_.extensionAddresses[i];
            }
        }

        revert("MultiMint not found: set MULTI_MINT or a deployed EXTENSION_NAME");
    }
}
