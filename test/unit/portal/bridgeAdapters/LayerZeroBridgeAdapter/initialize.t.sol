// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { ERC1967Proxy } from "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { LayerZeroBridgeAdapter } from "../../../../../src/portal/bridgeAdapters/layerZero/LayerZeroBridgeAdapter.sol";
import { IBridgeAdapter } from "../../../../../src/portal/interfaces/IBridgeAdapter.sol";

import { LayerZeroBridgeAdapterUnitTestBase } from "./LayerZeroBridgeAdapterUnitTestBase.sol";

contract InitializeUnitTest is LayerZeroBridgeAdapterUnitTestBase {
    function test_initialize_initialState() external view {
        assertTrue(adapter.hasRole(adapter.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(adapter.hasRole(adapter.OPERATOR_ROLE(), operator));
    }

    function test_initialize_cannotReinitialize() external {
        vm.expectRevert();
        adapter.initialize(admin, operator);
    }

    function test_initialize_zeroAdmin() external {
        LayerZeroBridgeAdapter newImplementation = new LayerZeroBridgeAdapter(address(lzEndpoint), address(portal));

        bytes memory initializeData = abi.encodeCall(LayerZeroBridgeAdapter.initialize, (address(0), operator));

        vm.expectRevert(IBridgeAdapter.ZeroAdmin.selector);
        new ERC1967Proxy(address(newImplementation), initializeData);
    }

    function test_initialize_zeroOperator() external {
        LayerZeroBridgeAdapter newImplementation = new LayerZeroBridgeAdapter(address(lzEndpoint), address(portal));

        bytes memory initializeData = abi.encodeCall(LayerZeroBridgeAdapter.initialize, (admin, address(0)));

        vm.expectRevert(IBridgeAdapter.ZeroOperator.selector);
        new ERC1967Proxy(address(newImplementation), initializeData);
    }
}
