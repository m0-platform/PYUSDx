// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { ILayerZeroBridgeAdapter } from "../../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroBridgeAdapter.sol";

import { ILayerZeroEndpointV2Like, SetConfigParam } from "../../../script/interfaces/ILayerZeroEndpointV2Like.sol";
import { Chains } from "../../../script/config/Chains.sol";
import {
    CONFIG_TYPE_ULN,
    LayerZeroBridgeAdapterNotDeployed,
    LayerZeroConfig,
    UlnConfig
} from "../../../script/config/LayerZeroConfig.sol";
import { Transaction } from "../../../script/libraries/TransactionHelper.sol";

import { ConfigureLayerZeroHarness } from "../../harness/ConfigureLayerZeroHarness.sol";

contract ConfigureLayerZeroTest is Test {
    uint32 internal constant _ARBITRUM_EID = 30110;

    ConfigureLayerZeroHarness internal harness;

    address internal adapter = makeAddr("adapter");
    address internal endpoint = makeAddr("endpoint");
    address internal sendLib = makeAddr("sendLib");
    address internal receiveLib = makeAddr("receiveLib");

    function setUp() external {
        harness = new ConfigureLayerZeroHarness();

        vm.mockCall(adapter, abi.encodeCall(ILayerZeroBridgeAdapter.endpoint, ()), abi.encode(endpoint));
        vm.mockCall(
            endpoint,
            abi.encodeCall(ILayerZeroEndpointV2Like.getSendLibrary, (adapter, _ARBITRUM_EID)),
            abi.encode(sendLib)
        );
        vm.mockCall(
            endpoint,
            abi.encodeCall(ILayerZeroEndpointV2Like.getReceiveLibrary, (adapter, _ARBITRUM_EID)),
            abi.encode(receiveLib, false)
        );
    }

    function _arbitrumPeer() internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = Chains.ARBITRUM;
    }

    /* ============ getSendUlnConfig / getReceiveUlnConfig ============ */

    function test_sendUlnConfig_ethereumToArbitrum() external view {
        UlnConfig memory config = harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM);

        assertEq(config.confirmations, 15); // source = Ethereum
        _assertDefaultDVNStack(config, Chains.ETHEREUM);
    }

    function test_receiveUlnConfig_usesRemoteSourceConfirmations() external view {
        UlnConfig memory config = harness.receiveUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM);

        assertEq(config.confirmations, 20); // source = Arbitrum
        _assertDefaultDVNStack(config, Chains.ETHEREUM);
    }

    /// @dev Asserts the LayerZero-default DVN stack: required = [LayerZero Labs, Google] (sorted
    ///      ascending), and no optional DVNs (expressed via NIL_DVN_COUNT).
    function _assertDefaultDVNStack(UlnConfig memory config, uint32 dvnChain) internal view {
        assertEq(config.requiredDVNCount, 2);
        assertEq(config.optionalDVNCount, 255); // NIL_DVN_COUNT — no optional DVNs
        assertEq(config.optionalDVNThreshold, 0);
        assertEq(config.optionalDVNs.length, 0);
        // Required DVNs sorted ascending; LayerZero Labs (0x589d..) < Google (0xD56e..).
        assertEq(config.requiredDVNs.length, 2);
        assertEq(config.requiredDVNs[0], LayerZeroConfig.getLayerZeroLabsDVN(dvnChain));
        assertEq(config.requiredDVNs[1], LayerZeroConfig.getGoogleDVN(dvnChain));
    }

    /* ============ _buildTransactions ============ */

    function test_buildTransactions_buildsSendAndReceiveSetConfig() external view {
        Transaction[] memory txs = harness.buildTransactions(Chains.ETHEREUM, adapter, _arbitrumPeer());

        assertEq(txs.length, 2);

        SetConfigParam[] memory sendParams = new SetConfigParam[](1);
        sendParams[0] = SetConfigParam({
            eid: _ARBITRUM_EID,
            configType: CONFIG_TYPE_ULN,
            config: abi.encode(harness.sendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM))
        });

        assertEq(txs[0].target, endpoint);
        assertEq(txs[0].data, abi.encodeCall(ILayerZeroEndpointV2Like.setConfig, (adapter, sendLib, sendParams)));

        SetConfigParam[] memory receiveParams = new SetConfigParam[](1);
        receiveParams[0] = SetConfigParam({
            eid: _ARBITRUM_EID,
            configType: CONFIG_TYPE_ULN,
            config: abi.encode(harness.receiveUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM))
        });

        assertEq(txs[1].target, endpoint);
        assertEq(txs[1].data, abi.encodeCall(ILayerZeroEndpointV2Like.setConfig, (adapter, receiveLib, receiveParams)));
    }

    function test_buildTransactions_revertsIfAdapterNotDeployed() external {
        vm.expectRevert(abi.encodeWithSelector(LayerZeroBridgeAdapterNotDeployed.selector, Chains.ETHEREUM));

        harness.buildTransactions(Chains.ETHEREUM, address(0), _arbitrumPeer());
    }
}
