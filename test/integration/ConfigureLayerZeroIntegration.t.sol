// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Chains } from "../../script/config/Chains.sol";
import { LayerZeroConfig, UlnConfig } from "../../script/config/LayerZeroConfig.sol";
import { ILayerZeroEndpointV2Like } from "../../script/interfaces/ILayerZeroEndpointV2Like.sol";
import { Transaction, TransactionHelper } from "../../script/libraries/TransactionHelper.sol";

import { ConfigureLayerZeroHarness } from "../harness/ConfigureLayerZeroHarness.sol";
import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @dev Minimal subset of the LayerZero V2 ULN302 message library used to read back applied config.
interface IUln302Like {
    function getUlnConfig(address oapp, uint32 remoteEid) external view returns (UlnConfig memory);
}

/// @title  ConfigureLayerZeroIntegrationTests
/// @notice Executes the ULN `setConfig` transactions against the real LayerZero endpoint + ULN302
///         libraries on a mainnet fork (signed by the adapter's delegate), then reads the config back
///         to prove the encoding and DVN/confirmation values are applied exactly as intended.
contract ConfigureLayerZeroIntegrationTests is IntegrationForkTest {
    uint32 internal constant _ARBITRUM_EID = 30110;
    uint32 internal constant _MONAD_EID = 30390;
    uint32 internal constant _BASE_EID = 30184;

    ConfigureLayerZeroHarness internal configurer;

    function setUp() public override {
        super.setUp();
        configurer = new ConfigureLayerZeroHarness();
    }

    function _arbitrumPeer() internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = Chains.ARBITRUM;
    }

    function _monadPeer() internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = Chains.MONAD;
    }

    function _basePeer() internal pure returns (uint32[] memory peers) {
        peers = new uint32[](1);
        peers[0] = Chains.BASE;
    }

    function _applyConfig() internal {
        _applyConfig(_arbitrumPeer());
    }

    function _applyConfig(uint32[] memory peers) internal {
        // The adapter sets the operator as its LayerZero delegate at initialization, so the operator
        // is authorized to call endpoint.setConfig.
        Transaction[] memory transactions = configurer.buildTransactions(
            Chains.ETHEREUM,
            address(layerZeroBridgeAdapter),
            peers
        );

        for (uint256 i; i < transactions.length; ++i) {
            vm.prank(operator);
            TransactionHelper.execute(transactions[i]);
        }
    }

    function test_configureLayerZero_appliesSendUlnConfig() public {
        _applyConfig();

        address adapter = address(layerZeroBridgeAdapter);
        address endpoint = layerZeroBridgeAdapter.endpoint();
        address sendLib = ILayerZeroEndpointV2Like(endpoint).getSendLibrary(adapter, _ARBITRUM_EID);

        UlnConfig memory applied = IUln302Like(sendLib).getUlnConfig(adapter, _ARBITRUM_EID);

        assertEq(applied.confirmations, 15); // source = Ethereum
        _assertAppliedDVNStack(applied, Chains.ETHEREUM);
    }

    function test_configureLayerZero_appliesReceiveUlnConfig() public {
        _applyConfig();

        address adapter = address(layerZeroBridgeAdapter);
        address endpoint = layerZeroBridgeAdapter.endpoint();
        (address receiveLib, ) = ILayerZeroEndpointV2Like(endpoint).getReceiveLibrary(adapter, _ARBITRUM_EID);

        UlnConfig memory applied = IUln302Like(receiveLib).getUlnConfig(adapter, _ARBITRUM_EID);

        assertEq(applied.confirmations, 20); // source = Arbitrum
        _assertAppliedDVNStack(applied, Chains.ETHEREUM);
    }

    /// @dev Asserts the applied (effective) LayerZero-default DVN stack read back from ULN302:
    ///      required = [LayerZero Labs, Google] (sorted ascending), no optional DVNs.
    function _assertAppliedDVNStack(UlnConfig memory applied, uint32 dvnChain) internal view {
        assertEq(applied.requiredDVNCount, 2);
        // Effective config: NIL_DVN_COUNT (255) we set is normalized by ULN302 to "no optional DVNs".
        assertEq(applied.optionalDVNCount, 0);
        assertEq(applied.optionalDVNThreshold, 0);
        assertEq(applied.optionalDVNs.length, 0);
        assertEq(applied.requiredDVNs.length, 2);
        // ULN302 returns required DVNs sorted ascending; LayerZero Labs (0x589d..) < Google (0xD56e..).
        assertEq(applied.requiredDVNs[0], LayerZeroConfig.getLayerZeroLabsDVN(dvnChain));
        assertEq(applied.requiredDVNs[1], LayerZeroConfig.getGoogleDVN(dvnChain));
    }

    /* ============ Monad route ============ */

    function test_configureLayerZero_appliesMonadSendUlnConfig() public {
        _applyConfig(_monadPeer());

        address adapter = address(layerZeroBridgeAdapter);
        address endpoint = layerZeroBridgeAdapter.endpoint();
        address sendLib = ILayerZeroEndpointV2Like(endpoint).getSendLibrary(adapter, _MONAD_EID);

        UlnConfig memory applied = IUln302Like(sendLib).getUlnConfig(adapter, _MONAD_EID);

        assertEq(applied.confirmations, 15); // source = Ethereum
        _assertAppliedNethermindDVNStack(applied, Chains.ETHEREUM);
    }

    function test_configureLayerZero_appliesMonadReceiveUlnConfig() public {
        _applyConfig(_monadPeer());

        address adapter = address(layerZeroBridgeAdapter);
        address endpoint = layerZeroBridgeAdapter.endpoint();
        (address receiveLib, ) = ILayerZeroEndpointV2Like(endpoint).getReceiveLibrary(adapter, _MONAD_EID);

        UlnConfig memory applied = IUln302Like(receiveLib).getUlnConfig(adapter, _MONAD_EID);

        assertEq(applied.confirmations, 4); // source = Monad
        _assertAppliedNethermindDVNStack(applied, Chains.ETHEREUM);
    }

    /// @dev Asserts the applied (effective) Monad DVN stack read back from ULN302: required =
    ///      [LayerZero Labs, Nethermind] (sorted ascending), no optional DVNs. Nethermind stands in
    ///      for Google, which runs no DVN on Monad.
    function _assertAppliedNethermindDVNStack(UlnConfig memory applied, uint32 dvnChain) internal view {
        assertEq(applied.requiredDVNCount, 2);
        // Effective config: NIL_DVN_COUNT (255) we set is normalized by ULN302 to "no optional DVNs".
        assertEq(applied.optionalDVNCount, 0);
        assertEq(applied.optionalDVNThreshold, 0);
        assertEq(applied.optionalDVNs.length, 0);
        assertEq(applied.requiredDVNs.length, 2);
        // ULN302 returns required DVNs sorted ascending; LayerZero Labs (0x589d..) < Nethermind (0xa59B..).
        assertEq(applied.requiredDVNs[0], LayerZeroConfig.getLayerZeroLabsDVN(dvnChain));
        assertEq(applied.requiredDVNs[1], LayerZeroConfig.getNethermindDVN(dvnChain));
    }

    /* ============ Base route ============ */

    function test_configureLayerZero_appliesBaseSendUlnConfig() public {
        _applyConfig(_basePeer());

        address adapter = address(layerZeroBridgeAdapter);
        address endpoint = layerZeroBridgeAdapter.endpoint();
        address sendLib = ILayerZeroEndpointV2Like(endpoint).getSendLibrary(adapter, _BASE_EID);

        UlnConfig memory applied = IUln302Like(sendLib).getUlnConfig(adapter, _BASE_EID);

        assertEq(applied.confirmations, 15); // source = Ethereum
        _assertAppliedDVNStack(applied, Chains.ETHEREUM);
    }

    function test_configureLayerZero_appliesBaseReceiveUlnConfig() public {
        _applyConfig(_basePeer());

        address adapter = address(layerZeroBridgeAdapter);
        address endpoint = layerZeroBridgeAdapter.endpoint();
        (address receiveLib, ) = ILayerZeroEndpointV2Like(endpoint).getReceiveLibrary(adapter, _BASE_EID);

        UlnConfig memory applied = IUln302Like(receiveLib).getUlnConfig(adapter, _BASE_EID);

        assertEq(applied.confirmations, 10); // source = Base
        _assertAppliedDVNStack(applied, Chains.ETHEREUM);
    }
}
