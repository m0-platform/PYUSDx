// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Chains } from "./Chains.sol";

/// @notice LayerZero V2 ULN (Ultra Light Node) security configuration for a route.
struct UlnConfig {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
}

/// @dev ULN config type identifier in the LayerZero V2 messagelib.
uint32 constant CONFIG_TYPE_ULN = 2;

/// @notice Thrown when a script needs the `LayerZeroBridgeAdapter` on the active chain but the
///         deployment record carries a zero address.
error LayerZeroBridgeAdapterNotDeployed(uint32 chainId);

/// @title  LayerZeroConfig
/// @notice Static LayerZero V2 lookups: endpoint IDs, endpoint addresses, and DVN addresses per chain.
/// @dev    https://docs.layerzero.network/v2/deployments/deployed-contracts?stages=mainnet
///         DVN addresses snapshotted from the LayerZero metadata API (the non-lzRead messaging DVNs):
///         https://metadata.layerzero-api.com/v1/metadata/dvns
library LayerZeroConfig {
    /// @notice Returns the LayerZero V2 Endpoint ID (EID) for a chain.
    function getLayerZeroEndpointId(uint32 chainId) internal pure returns (uint32) {
        if (chainId == Chains.ETHEREUM) return 30101;
        if (chainId == Chains.ARBITRUM) return 30110;

        revert Chains.UnsupportedChain(chainId);
    }

    /// @notice Returns the LayerZero V2 Endpoint address for a chain.
    function getEndpoint(uint32 chainId) internal pure returns (address) {
        if (chainId == Chains.ETHEREUM) return 0x1a44076050125825900e736c501f859c50fE728c;
        if (chainId == Chains.ARBITRUM) return 0x1a44076050125825900e736c501f859c50fE728c;

        revert Chains.UnsupportedChain(chainId);
    }

    /// @notice Returns the LayerZero Labs DVN address for a chain.
    function getLayerZeroLabsDVN(uint32 chainId) internal pure returns (address) {
        if (chainId == Chains.ETHEREUM) return 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
        if (chainId == Chains.ARBITRUM) return 0x2f55C492897526677C5B68fb199ea31E2c126416;

        revert Chains.UnsupportedChain(chainId);
    }

    /// @notice Returns the Google Cloud DVN address for a chain.
    function getGoogleDVN(uint32 chainId) internal pure returns (address) {
        if (chainId == Chains.ETHEREUM) return 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;
        if (chainId == Chains.ARBITRUM) return 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;

        revert Chains.UnsupportedChain(chainId);
    }
}

/// @title  LayerZeroUlnConfig
/// @notice Per-route ULN config registry for the LayerZeroBridgeAdapter.
/// @dev    Two mappings (send + receive), keyed by (currentChainId, remoteChainId). The current chain
///         is where the config is applied; the remote chain is its peer. Confirmations are source-chain
///         block counts: for a send config the source is the current chain; for a receive config the
///         source is the remote chain.
abstract contract LayerZeroUlnConfig {
    error UnsupportedSendRoute(uint32 currentChainId, uint32 remoteChainId);
    error UnsupportedReceiveRoute(uint32 currentChainId, uint32 remoteChainId);
    error OptionalThresholdExceedsCount(uint8 threshold, uint256 count);
    error NoDVNsConfigured();
    error ZeroDVN();
    error DuplicateDVN(address dvn);

    /// @dev ULN302 treats `requiredDVNCount = 0` (and `optionalDVNCount = 0`) as "use the default
    ///      config's DVN list" — not as "no DVNs". To express "no DVNs of this kind" explicitly, the
    ///      count must be set to `NIL_DVN_COUNT` (= 255). Use it whenever the matching array is empty.
    uint8 internal constant NIL_DVN_COUNT = type(uint8).max;

    /// @dev Source-chain block confirmations per side of the Ethereum <-> Arbitrum route.
    ///      Mirrors the reference's Ethereum=15 / remote=20 split, adapted for Arbitrum.
    uint64 internal constant _ETHEREUM_CONFIRMATIONS = 15;
    uint64 internal constant _ARBITRUM_CONFIRMATIONS = 20;

    mapping(uint32 currentChainId => mapping(uint32 remoteChainId => UlnConfig)) private _sendUlnConfig;
    mapping(uint32 currentChainId => mapping(uint32 remoteChainId => UlnConfig)) private _receiveUlnConfig;

    constructor() {
        _initUlnConfigs();
    }

    function getSendUlnConfig(
        uint32 currentChainId,
        uint32 remoteChainId
    ) internal view returns (UlnConfig memory config) {
        config = _sendUlnConfig[currentChainId][remoteChainId];
        if (config.confirmations == 0) revert UnsupportedSendRoute(currentChainId, remoteChainId);
    }

    function getReceiveUlnConfig(
        uint32 currentChainId,
        uint32 remoteChainId
    ) internal view returns (UlnConfig memory config) {
        config = _receiveUlnConfig[currentChainId][remoteChainId];
        if (config.confirmations == 0) revert UnsupportedReceiveRoute(currentChainId, remoteChainId);
    }

    /// @dev Populates the per-route ULN config registry for Ethereum <-> Arbitrum, pinning the
    ///      LayerZero default security stack: required DVNs = [LayerZero Labs, Google], no optional
    ///      DVNs. Confirmations match the on-chain defaults (Ethereum source = 15, Arbitrum source = 20).
    function _initUlnConfigs() private {
        address[] memory noOptional = new address[](0);

        // Ethereum side (LayerZeroBridgeAdapter on Ethereum).
        address[] memory ethRequired = new address[](2);
        ethRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.ETHEREUM);
        ethRequired[1] = LayerZeroConfig.getGoogleDVN(Chains.ETHEREUM);

        // Ethereum -> Arbitrum send: source = Ethereum.
        _setSendUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM, _ETHEREUM_CONFIRMATIONS, ethRequired, noOptional, 0);
        // Arbitrum -> Ethereum receive: source = Arbitrum.
        _setReceiveUlnConfig(Chains.ETHEREUM, Chains.ARBITRUM, _ARBITRUM_CONFIRMATIONS, ethRequired, noOptional, 0);

        // Arbitrum side (LayerZeroBridgeAdapter on Arbitrum).
        address[] memory arbRequired = new address[](2);
        arbRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.ARBITRUM);
        arbRequired[1] = LayerZeroConfig.getGoogleDVN(Chains.ARBITRUM);

        // Arbitrum -> Ethereum send: source = Arbitrum.
        _setSendUlnConfig(Chains.ARBITRUM, Chains.ETHEREUM, _ARBITRUM_CONFIRMATIONS, arbRequired, noOptional, 0);
        // Ethereum -> Arbitrum receive: source = Ethereum.
        _setReceiveUlnConfig(Chains.ARBITRUM, Chains.ETHEREUM, _ETHEREUM_CONFIRMATIONS, arbRequired, noOptional, 0);
    }

    function _setSendUlnConfig(
        uint32 currentChainId,
        uint32 remoteChainId,
        uint64 confirmations,
        address[] memory requiredDVNs,
        address[] memory optionalDVNs,
        uint8 optionalThreshold
    ) private {
        _sendUlnConfig[currentChainId][remoteChainId] = _buildUlnConfig(
            confirmations,
            requiredDVNs,
            optionalDVNs,
            optionalThreshold
        );
    }

    function _setReceiveUlnConfig(
        uint32 currentChainId,
        uint32 remoteChainId,
        uint64 confirmations,
        address[] memory requiredDVNs,
        address[] memory optionalDVNs,
        uint8 optionalThreshold
    ) private {
        _receiveUlnConfig[currentChainId][remoteChainId] = _buildUlnConfig(
            confirmations,
            requiredDVNs,
            optionalDVNs,
            optionalThreshold
        );
    }

    /// @dev Validates inputs, sorts both DVN arrays ascending (ULN302 requires ascending order),
    ///      and packages them into a `UlnConfig`.
    function _buildUlnConfig(
        uint64 confirmations,
        address[] memory requiredDVNs,
        address[] memory optionalDVNs,
        uint8 optionalThreshold
    ) internal pure returns (UlnConfig memory) {
        if (optionalThreshold > optionalDVNs.length) {
            revert OptionalThresholdExceedsCount(optionalThreshold, optionalDVNs.length);
        }

        if (requiredDVNs.length + optionalDVNs.length == 0) revert NoDVNsConfigured();

        _sortAscending(requiredDVNs);
        _sortAscending(optionalDVNs);
        _assertNoZeroOrDuplicates(requiredDVNs);
        _assertNoZeroOrDuplicates(optionalDVNs);

        return
            UlnConfig({
                confirmations: confirmations,
                requiredDVNCount: requiredDVNs.length == 0 ? NIL_DVN_COUNT : uint8(requiredDVNs.length),
                optionalDVNCount: optionalDVNs.length == 0 ? NIL_DVN_COUNT : uint8(optionalDVNs.length),
                optionalDVNThreshold: optionalThreshold,
                requiredDVNs: requiredDVNs,
                optionalDVNs: optionalDVNs
            });
    }

    function _sortAscending(address[] memory dvns) private pure {
        uint256 n = dvns.length;
        for (uint256 i = 1; i < n; ++i) {
            address key = dvns[i];
            uint256 j = i;
            while (j > 0 && uint160(dvns[j - 1]) > uint160(key)) {
                dvns[j] = dvns[j - 1];
                unchecked {
                    --j;
                }
            }
            dvns[j] = key;
        }
    }

    /// @dev Assumes `dvns` is sorted ascending. Verifies no zero address (sorted ascending puts
    ///      `address(0)` at index 0 if present) and no duplicates (strict ordering rules them out).
    function _assertNoZeroOrDuplicates(address[] memory dvns) private pure {
        if (dvns.length == 0) return;
        if (dvns[0] == address(0)) revert ZeroDVN();

        for (uint256 i = 1; i < dvns.length; ++i) {
            if (uint160(dvns[i - 1]) >= uint160(dvns[i])) revert DuplicateDVN(dvns[i]);
        }
    }
}
