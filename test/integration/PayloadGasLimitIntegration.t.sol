// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { TypeConverter } from "../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { LayerZeroBridgeAdapter } from "../../src/portal/bridgeAdapters/layerZero/LayerZeroBridgeAdapter.sol";
import { Origin } from "../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { PayloadEncoder } from "../../src/portal/libraries/PayloadEncoder.sol";

import { Chains } from "../../script/config/Chains.sol";
import { LayerZeroConfig } from "../../script/config/LayerZeroConfig.sol";
import { RouteConfig } from "../../script/config/RouteConfig.sol";
import { Transaction, TransactionHelper } from "../../script/libraries/TransactionHelper.sol";

import { ConfigurePortalHarness } from "../harness/ConfigurePortalHarness.sol";
import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @title  PayloadGasLimitIntegrationTests
/// @notice Validates that the configured `RouteConfig` payload gas limit is sufficient to execute an
///         inbound cross-chain `TokenTransfer` end to end (adapter.lzReceive -> Portal.receiveMessage
///         -> mint / wrap) against the real deployed contracts on a fork.
contract PayloadGasLimitIntegrationTests is IntegrationForkTest {
    using TypeConverter for address;

    uint32 internal constant _ARBITRUM_EID = 30110;
    uint256 internal constant _AMOUNT = 1_000e6;

    ConfigurePortalHarness internal configurer;
    address internal arbitrumPeerAdapter = makeAddr("arbitrumPeerAdapter");
    address internal lzEndpoint;

    function setUp() public override {
        super.setUp();

        configurer = new ConfigurePortalHarness();
        configurer.setPeerAdapter(Chains.ARBITRUM, arbitrumPeerAdapter);
        lzEndpoint = layerZeroBridgeAdapter.endpoint();

        // Wire Arbitrum as a peer so inbound messages from it are accepted (setPeer + setBridgeChainId
        // on the adapter, setSupportedBridgeAdapter on the Portal).
        uint32[] memory peers = new uint32[](1);
        peers[0] = Chains.ARBITRUM;
        Transaction[] memory txs = configurer.configurePeers(address(portal), address(layerZeroBridgeAdapter), peers);
        for (uint256 i; i < txs.length; ++i) {
            vm.prank(operator);
            TransactionHelper.execute(txs[i]);
        }
    }

    /// @dev Builds the calldata for an inbound `lzReceive` carrying a TokenTransfer to `recipient`.
    function _inboundCalldata(
        bytes32 messageId,
        address destinationToken,
        address recipient
    ) internal returns (bytes memory) {
        bytes memory payload = PayloadEncoder.encodeTokenTransfer(
            uint32(block.chainid), // destination chain = the fork (Ethereum)
            address(layerZeroBridgeAdapter).toBytes32(), // destination (target) bridge adapter
            messageId,
            _AMOUNT,
            destinationToken.toBytes32(),
            makeAddr("crossChainSender"),
            recipient.toBytes32()
        );

        Origin memory origin = Origin({ srcEid: _ARBITRUM_EID, sender: arbitrumPeerAdapter.toBytes32(), nonce: 1 });

        return abi.encodeCall(LayerZeroBridgeAdapter.lzReceive, (origin, bytes32(0), payload, address(0), bytes("")));
    }

    /// @dev Delivers an inbound message as the LayerZero endpoint, optionally capping the forwarded gas
    ///      to `gasCap` (0 = uncapped). Returns whether it succeeded and the gas consumed.
    function _deliver(
        bytes32 messageId,
        address destinationToken,
        address recipient,
        uint256 gasCap
    ) internal returns (bool ok, uint256 gasUsed) {
        bytes memory cd = _inboundCalldata(messageId, destinationToken, recipient);

        vm.prank(lzEndpoint);
        uint256 gasBefore = gasleft();
        (ok, ) = gasCap == 0
            ? address(layerZeroBridgeAdapter).call(cd)
            : address(layerZeroBridgeAdapter).call{ gas: gasCap }(cd);
        gasUsed = gasBefore - gasleft();
    }

    function _deployYieldToOne() internal returns (address ytoProxy) {
        IExtensionFactory.YieldToOneParams memory params = IExtensionFactory.YieldToOneParams({
            name: "TestYTO",
            symbol: "TYTO",
            yieldRecipient: yieldRecipient,
            admin: admin,
            freezeManager: freezeManager,
            yieldRecipientManager: yieldRecipientManager,
            pauser: pauser,
            versionManager: versionManager
        });

        vm.prank(admin);
        (ytoProxy, ) = factory.deployYieldToOne("payload-gas-yto", params);

        // Enable earning so the inbound wrap (SwapFacility.swapIn) succeeds rather than falling back.
        vm.prank(earnerManager);
        pyusdx.setAccountInfo(ytoProxy, 500, 0, yieldRecipient);
    }

    /* ============ Direct PYUSDX transfer (current production case) ============ */

    function test_payloadGasLimit_coversDirectPyusdxTransfer() public {
        uint256 gasLimit = RouteConfig.getPayloadGasLimit(Chains.ETHEREUM);

        address recipient = makeAddr("directRecipient");
        (bool ok, uint256 gasUsed) = _deliver(keccak256("direct-measure"), address(pyusdx), recipient, 0);

        assertTrue(ok);
        assertEq(pyusdx.balanceOf(recipient), _AMOUNT);
        emit log_named_uint("lzReceive direct-PYUSDX gas used", gasUsed);
        emit log_named_uint("configured payloadGasLimit ", gasLimit);
        assertLt(gasUsed, gasLimit);

        // Sufficiency at exactly the configured budget (mirrors the executor forwarding payloadGasLimit).
        address cappedRecipient = makeAddr("directRecipientCapped");
        (bool okCapped, ) = _deliver(keccak256("direct-capped"), address(pyusdx), cappedRecipient, gasLimit);

        assertTrue(okCapped, "direct PYUSDX transfer exceeded payloadGasLimit");
        assertEq(pyusdx.balanceOf(cappedRecipient), _AMOUNT);
    }

    /* ============ Extension wrap (heavier path) ============ */

    function test_payloadGasLimit_coversExtensionWrapTransfer() public {
        uint256 gasLimit = RouteConfig.getPayloadGasLimit(Chains.ETHEREUM);
        address yto = _deployYieldToOne();

        address recipient = makeAddr("wrapRecipient");
        (bool ok, uint256 gasUsed) = _deliver(keccak256("wrap-measure"), yto, recipient, 0);

        assertTrue(ok);
        // The wrap succeeded (recipient holds the extension token, not the PYUSDX fallback).
        assertEq(IERC20(yto).balanceOf(recipient), _AMOUNT);
        assertEq(pyusdx.balanceOf(recipient), 0);
        emit log_named_uint("lzReceive extension-wrap gas used", gasUsed);
        emit log_named_uint("configured payloadGasLimit  ", gasLimit);
        assertLt(gasUsed, gasLimit);
    }
}
