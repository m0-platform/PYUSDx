// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { LayerZeroBridgeAdapter } from "../../../../../src/portal/bridgeAdapters/layerZero/LayerZeroBridgeAdapter.sol";
import { IBridgeAdapter } from "../../../../../src/portal/interfaces/IBridgeAdapter.sol";
import { ILayerZeroBridgeAdapter } from "../../../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroBridgeAdapter.sol";

import { LayerZeroBridgeAdapterUnitTestBase } from "./LayerZeroBridgeAdapterUnitTestBase.sol";

contract ConstructorUnitTest is LayerZeroBridgeAdapterUnitTestBase {
    function test_constructor_initialState() external view {
        assertEq(implementation.portal(), address(portal));
        assertEq(implementation.endpoint(), address(lzEndpoint));
    }

    function test_constructor_zeroPortal() external {
        vm.expectRevert(IBridgeAdapter.ZeroPortal.selector);
        new LayerZeroBridgeAdapter(address(lzEndpoint), address(0));
    }

    function test_constructor_zeroEndpoint() external {
        vm.expectRevert(ILayerZeroBridgeAdapter.ZeroEndpoint.selector);
        new LayerZeroBridgeAdapter(address(0), address(portal));
    }
}
