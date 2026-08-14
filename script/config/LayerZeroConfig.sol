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
        if (chainId == Chains.MONAD) return 30390;
        if (chainId == Chains.SEPOLIA) return 40161;
        if (chainId == Chains.ARBITRUM_SEPOLIA) return 40231;
        // The live `monad2-testnet` EID, not the deprecated `monad-testnet` 40204.
        if (chainId == Chains.MONAD_TESTNET) return 40442;

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
        if (chainId == Chains.MONAD) return 0x282b3386571f7f794450d5789911a9804FA346b4;
        if (chainId == Chains.SEPOLIA) return 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193;
        if (chainId == Chains.ARBITRUM_SEPOLIA) return 0x53f488E93b4f1b60E8E83aa374dBe1780A1EE8a8;
        if (chainId == Chains.MONAD_TESTNET) return 0xa78A78a13074eD93aD447a26Ec57121f29E8feC2;

        revert Chains.UnsupportedChain(chainId);
    }

    /// @notice Returns the Google Cloud DVN address for a chain.
    function getGoogleDVN(uint32 chainId) internal pure returns (address) {
        if (chainId == Chains.ETHEREUM) return 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;
        if (chainId == Chains.ARBITRUM) return 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;

        revert Chains.UnsupportedChain(chainId);
    }

    /// @notice Returns the Nethermind DVN address for a chain.
    /// @dev    Stands in for Google as the second required DVN on Monad routes: Google does not run a
    ///         DVN on Monad, Nethermind does on all three of Ethereum, Arbitrum and Monad.
    function getNethermindDVN(uint32 chainId) internal pure returns (address) {
        if (chainId == Chains.ETHEREUM) return 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;
        if (chainId == Chains.ARBITRUM) return 0xa7b5189bcA84Cd304D8553977c7C614329750d99;
        if (chainId == Chains.MONAD) return 0xaCDe1f22EEAb249d3ca6Ba8805C8fEe9f52a16e7;

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

    /// @dev Source-chain block confirmations for Monad. Matches LayerZero's live on-chain default.
    uint64 internal constant _MONAD_CONFIRMATIONS = 4;

    /// @dev Source-chain block confirmations per side of the Sepolia <-> Arbitrum Sepolia testnet route.
    ///      Mirrors the mainnet Ethereum=15 / Arbitrum=20 split.
    uint64 internal constant _SEPOLIA_CONFIRMATIONS = 15;
    uint64 internal constant _ARBITRUM_SEPOLIA_CONFIRMATIONS = 20;

    /// @dev Source-chain block confirmations for Monad testnet. Matches LayerZero's live on-chain default.
    uint64 internal constant _MONAD_TESTNET_CONFIRMATIONS = 2;

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

    /// @dev Populates the per-route ULN config registry for every supported route. The registry is
    ///      chain-agnostic: all routes are loaded regardless of the active chain, and the script
    ///      selects the live route via `block.chainid` at the call site.
    function _initUlnConfigs() private {
        _initMainnetUlnConfigs();
        _initMonadUlnConfigs();
        _initTestnetUlnConfigs();
        _initMonadTestnetUlnConfigs();
    }

    /// @dev Populates the per-route ULN config registry for Ethereum <-> Arbitrum, pinning the
    ///      LayerZero default security stack: required DVNs = [LayerZero Labs, Google], no optional
    ///      DVNs. Confirmations match the on-chain defaults (Ethereum source = 15, Arbitrum source = 20).
    function _initMainnetUlnConfigs() private {
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

    /// @dev Populates the per-route ULN config registry for Monad <-> Ethereum and Monad <-> Arbitrum.
    ///      Google runs no DVN on Monad, so the required set is [LayerZero Labs, Nethermind] on every
    ///      side rather than the [LayerZero Labs, Google] pair used on Ethereum <-> Arbitrum.
    ///      Confirmations match each chain's on-chain default (Ethereum = 15, Arbitrum = 20, Monad = 4).
    function _initMonadUlnConfigs() private {
        address[] memory noOptional = new address[](0);

        // Monad side (LayerZeroBridgeAdapter on Monad).
        address[] memory monadRequired = new address[](2);
        monadRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.MONAD);
        monadRequired[1] = LayerZeroConfig.getNethermindDVN(Chains.MONAD);

        // Monad -> Ethereum send: source = Monad.
        _setSendUlnConfig(Chains.MONAD, Chains.ETHEREUM, _MONAD_CONFIRMATIONS, monadRequired, noOptional, 0);
        // Ethereum -> Monad receive: source = Ethereum.
        _setReceiveUlnConfig(Chains.MONAD, Chains.ETHEREUM, _ETHEREUM_CONFIRMATIONS, monadRequired, noOptional, 0);

        // Monad -> Arbitrum send: source = Monad.
        _setSendUlnConfig(Chains.MONAD, Chains.ARBITRUM, _MONAD_CONFIRMATIONS, monadRequired, noOptional, 0);
        // Arbitrum -> Monad receive: source = Arbitrum.
        _setReceiveUlnConfig(Chains.MONAD, Chains.ARBITRUM, _ARBITRUM_CONFIRMATIONS, monadRequired, noOptional, 0);

        // Ethereum side (LayerZeroBridgeAdapter on Ethereum).
        address[] memory ethRequired = new address[](2);
        ethRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.ETHEREUM);
        ethRequired[1] = LayerZeroConfig.getNethermindDVN(Chains.ETHEREUM);

        // Ethereum -> Monad send: source = Ethereum.
        _setSendUlnConfig(Chains.ETHEREUM, Chains.MONAD, _ETHEREUM_CONFIRMATIONS, ethRequired, noOptional, 0);
        // Monad -> Ethereum receive: source = Monad.
        _setReceiveUlnConfig(Chains.ETHEREUM, Chains.MONAD, _MONAD_CONFIRMATIONS, ethRequired, noOptional, 0);

        // Arbitrum side (LayerZeroBridgeAdapter on Arbitrum).
        address[] memory arbRequired = new address[](2);
        arbRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.ARBITRUM);
        arbRequired[1] = LayerZeroConfig.getNethermindDVN(Chains.ARBITRUM);

        // Arbitrum -> Monad send: source = Arbitrum.
        _setSendUlnConfig(Chains.ARBITRUM, Chains.MONAD, _ARBITRUM_CONFIRMATIONS, arbRequired, noOptional, 0);
        // Monad -> Arbitrum receive: source = Monad.
        _setReceiveUlnConfig(Chains.ARBITRUM, Chains.MONAD, _MONAD_CONFIRMATIONS, arbRequired, noOptional, 0);
    }

    /// @dev Populates the per-route ULN config registry for the Sepolia <-> Arbitrum Sepolia testnet
    ///      route. Arbitrum Sepolia has no Google DVN, so the required set is [LayerZero Labs] only on
    ///      both sides. Confirmations mirror the mainnet split (Sepolia source = 15, Arbitrum Sepolia
    ///      source = 20).
    function _initTestnetUlnConfigs() private {
        address[] memory noOptional = new address[](0);

        // Sepolia side (LayerZeroBridgeAdapter on Sepolia).
        address[] memory sepoliaRequired = new address[](1);
        sepoliaRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.SEPOLIA);

        // Sepolia -> Arbitrum Sepolia send: source = Sepolia.
        _setSendUlnConfig(
            Chains.SEPOLIA,
            Chains.ARBITRUM_SEPOLIA,
            _SEPOLIA_CONFIRMATIONS,
            sepoliaRequired,
            noOptional,
            0
        );

        // Arbitrum Sepolia -> Sepolia receive: source = Arbitrum Sepolia.
        _setReceiveUlnConfig(
            Chains.SEPOLIA,
            Chains.ARBITRUM_SEPOLIA,
            _ARBITRUM_SEPOLIA_CONFIRMATIONS,
            sepoliaRequired,
            noOptional,
            0
        );

        // Arbitrum Sepolia side (LayerZeroBridgeAdapter on Arbitrum Sepolia).
        address[] memory arbSepoliaRequired = new address[](1);
        arbSepoliaRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.ARBITRUM_SEPOLIA);

        // Arbitrum Sepolia -> Sepolia send: source = Arbitrum Sepolia.
        _setSendUlnConfig(
            Chains.ARBITRUM_SEPOLIA,
            Chains.SEPOLIA,
            _ARBITRUM_SEPOLIA_CONFIRMATIONS,
            arbSepoliaRequired,
            noOptional,
            0
        );

        // Sepolia -> Arbitrum Sepolia receive: source = Sepolia.
        _setReceiveUlnConfig(
            Chains.ARBITRUM_SEPOLIA,
            Chains.SEPOLIA,
            _SEPOLIA_CONFIRMATIONS,
            arbSepoliaRequired,
            noOptional,
            0
        );
    }

    /// @dev Populates the per-route ULN config registry for the Sepolia <-> Monad testnet route.
    ///      Monad testnet has no Google DVN, so the required set is [LayerZero Labs] only on both
    ///      sides, matching the Sepolia <-> Arbitrum Sepolia route. Confirmations use each chain's
    ///      on-chain default (Sepolia = 15, Monad testnet = 2).
    function _initMonadTestnetUlnConfigs() private {
        address[] memory noOptional = new address[](0);

        // Monad testnet side (LayerZeroBridgeAdapter on Monad testnet).
        address[] memory monadRequired = new address[](1);
        monadRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.MONAD_TESTNET);

        // Monad testnet -> Sepolia send: source = Monad testnet.
        _setSendUlnConfig(
            Chains.MONAD_TESTNET,
            Chains.SEPOLIA,
            _MONAD_TESTNET_CONFIRMATIONS,
            monadRequired,
            noOptional,
            0
        );

        // Sepolia -> Monad testnet receive: source = Sepolia.
        _setReceiveUlnConfig(
            Chains.MONAD_TESTNET,
            Chains.SEPOLIA,
            _SEPOLIA_CONFIRMATIONS,
            monadRequired,
            noOptional,
            0
        );

        // Sepolia side (LayerZeroBridgeAdapter on Sepolia).
        address[] memory sepoliaRequired = new address[](1);
        sepoliaRequired[0] = LayerZeroConfig.getLayerZeroLabsDVN(Chains.SEPOLIA);

        // Sepolia -> Monad testnet send: source = Sepolia.
        _setSendUlnConfig(Chains.SEPOLIA, Chains.MONAD_TESTNET, _SEPOLIA_CONFIRMATIONS, sepoliaRequired, noOptional, 0);

        // Monad testnet -> Sepolia receive: source = Monad testnet.
        _setReceiveUlnConfig(
            Chains.SEPOLIA,
            Chains.MONAD_TESTNET,
            _MONAD_TESTNET_CONFIRMATIONS,
            sepoliaRequired,
            noOptional,
            0
        );
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
