// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { TypeConverter } from "../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { Portal } from "../../../../src/portal/Portal.sol";
import { PayloadType } from "../../../../src/portal/libraries/PayloadEncoder.sol";

import { MockERC20 } from "../../../mock/MockERC20.sol";
import { MockPYUSDXExtension } from "../../../mock/MockPYUSDXExtension.sol";
import { MockSwapFacility } from "../../../mock/MockSwapFacility.sol";
import { MockBridgeAdapter } from "../../../mock/MockBridgeAdapter.sol";

abstract contract PortalUnitTestBase is Test {
    using TypeConverter for *;

    uint32 internal constant CHAIN_ID_1 = 1;
    uint32 internal constant CHAIN_ID_2 = 2;

    uint256 internal constant TOKEN_TRANSFER_GAS_LIMIT = 300_000;

    Portal internal implementation;
    Portal internal portal;

    MockERC20 internal pyusdx;
    MockPYUSDXExtension internal extension;
    MockSwapFacility internal swapFacility;
    MockBridgeAdapter internal bridgeAdapter;

    bytes32 internal peerPYUSDX = makeAddr("PYUSDX Chain 2").toBytes32();
    bytes32 internal peerExtension = makeAddr("PYUSDX Extension Chain 2").toBytes32();
    bytes32 internal peerBridgeAdapter = makeAddr("BridgeAdapter Chain 2").toBytes32();

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal pauser = makeAddr("pauser");
    address internal user = makeAddr("user");

    function setUp() public virtual {
        vm.chainId(CHAIN_ID_1);

        pyusdx = new MockERC20("PYUSDX", "PYUSDX", 6);
        swapFacility = new MockSwapFacility(address(pyusdx));
        extension = new MockPYUSDXExtension(address(pyusdx), address(swapFacility));
        bridgeAdapter = new MockBridgeAdapter();

        // Deploy implementation
        implementation = new Portal(address(pyusdx), address(swapFacility));

        // Deploy Transparent proxy
        bytes memory initializeData = abi.encodeCall(Portal.initialize, (admin, pauser, operator));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            initializeData
        );
        portal = Portal(address(proxy));

        bridgeAdapter.setPortal(address(portal));

        vm.startPrank(operator);

        // Configure
        portal.setDefaultBridgeAdapter(CHAIN_ID_2, address(bridgeAdapter));
        portal.setPayloadGasLimit(CHAIN_ID_2, TOKEN_TRANSFER_GAS_LIMIT);

        vm.stopPrank();

        // Fund accounts
        vm.deal(admin, 1 ether);
        vm.deal(operator, 1 ether);
        vm.deal(pauser, 1 ether);
        vm.deal(user, 1 ether);

        // Mock fetching peer bridge adapter
        vm.mockCall(
            address(bridgeAdapter),
            abi.encodeCall(MockBridgeAdapter.getPeer, (CHAIN_ID_2)),
            abi.encode(peerBridgeAdapter)
        );
    }

    function _getMessageId() internal returns (bytes32) {
        uint256 nonce = portal.getNonce();
        return keccak256(abi.encode(CHAIN_ID_1, CHAIN_ID_2, nonce++));
    }
}
