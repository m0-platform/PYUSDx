// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TypeConverter } from "common/src/libs/TypeConverter.sol";
import { LayerZeroBridgeAdapter } from "../../../../../src/portal/bridgeAdapters/layerZero/LayerZeroBridgeAdapter.sol";

import { MockLayerZeroEndpoint } from "../../../../mock/MockLayerZeroEndpoint.sol";
import { MockPortal } from "../../../../mock/MockPortal.sol";

abstract contract LayerZeroBridgeAdapterUnitTestBase is Test {
    using TypeConverter for *;

    uint32 internal constant HUB_CHAIN_ID = 1;
    uint32 internal constant SPOKE_CHAIN_ID = 2;
    uint32 internal constant SPOKE_LAYER_ZERO_EID = 30_102; // LayerZero Endpoint ID

    LayerZeroBridgeAdapter internal implementation;
    LayerZeroBridgeAdapter internal adapter;
    MockLayerZeroEndpoint internal lzEndpoint;
    MockPortal internal portal;

    bytes32 internal peerAdapterAddress = makeAddr("spokeAdapter").toBytes32();

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal user = makeAddr("user");

    function setUp() public virtual {
        // Set block.chainid to HUB_CHAIN_ID
        vm.chainId(HUB_CHAIN_ID);

        portal = new MockPortal(address(0));
        lzEndpoint = new MockLayerZeroEndpoint();

        // Deploy implementation
        implementation = new LayerZeroBridgeAdapter(address(lzEndpoint), address(portal));

        // Deploy UUPS proxy
        bytes memory initializeData = abi.encodeCall(LayerZeroBridgeAdapter.initialize, (admin, operator));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initializeData);
        adapter = LayerZeroBridgeAdapter(address(proxy));

        vm.startPrank(operator);
        // Configure peer and chain ID mapping
        adapter.setPeer(SPOKE_CHAIN_ID, peerAdapterAddress);
        adapter.setBridgeChainId(SPOKE_CHAIN_ID, SPOKE_LAYER_ZERO_EID);
        vm.stopPrank();

        // Fund accounts
        vm.deal(admin, 1 ether);
        vm.deal(operator, 1 ether);
        vm.deal(user, 1 ether);
        vm.deal(address(portal), 1 ether);
        vm.deal(address(lzEndpoint), 1 ether);
    }
}
