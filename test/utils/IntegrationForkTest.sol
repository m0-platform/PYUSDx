// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { Config } from "../../script/Config.sol";
import { DeployBase } from "../../script/deploy/DeployBase.s.sol";

import { ExtensionBeacon } from "../../src/platform/ExtensionBeacon.sol";
import { IssuerGateway } from "../../src/core/IssuerGateway.sol";
import { PYUSDX } from "../../src/PYUSDX.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { Portal } from "../../src/portal/Portal.sol";
import { LayerZeroBridgeAdapter } from "../../src/portal/bridgeAdapters/layerZero/LayerZeroBridgeAdapter.sol";

import { BaseForkTest } from "./BaseForkTest.sol";

/// @notice Exposes DeployBase._deployCore() externally to avoid forge-std diamond inheritance in tests.
contract CoreDeployer is DeployBase {
    function deployCore(
        PYUSDXConfig memory pyusdxConfig_,
        IssuerGatewayConfig memory issuerGatewayConfig_,
        SwapFacilityConfig memory swapFacilityConfig_,
        FactoryConfig memory factoryConfig_,
        PortalConfig memory portalConfig_,
        LayerZeroBridgeAdapterConfig memory layerZeroBridgeAdapterConfig_
    ) external returns (CoreDeployments memory) {
        return
            _deployCore(
                address(this),
                pyusdxConfig_,
                issuerGatewayConfig_,
                swapFacilityConfig_,
                factoryConfig_,
                portalConfig_,
                layerZeroBridgeAdapterConfig_
            );
    }
}

/// @title IntegrationForkTest
/// @notice Base test that deploys the full PYUSDX stack via DeployBase deploy scripts
/// @dev Uses CREATE3 via CreateX factory (available on mainnet forks).
///      Uses composition with CoreDeployer to avoid forge-std diamond inheritance
///      between lib/forge-std (scripts) and lib/evm-m-extensions/lib/forge-std (tests).
abstract contract IntegrationForkTest is BaseForkTest {
    PYUSDX public pyusdx;
    IssuerGateway public issuerGateway;
    SwapFacility public swapFacility;
    ExtensionFactory public factory;
    ExtensionBeacon public yieldToOneBeacon;
    ExtensionBeacon public multiMintBeacon;
    Portal public portal;
    LayerZeroBridgeAdapter public layerZeroBridgeAdapter;

    DeployBase.CoreDeployments internal _coreDeployments;
    CoreDeployer public coreDeployer;

    uint32 public constant MINT_DELAY = 1; // 1 second for testing
    uint32 public constant MINT_TTL = 3600; // 1 hour

    /// @dev LayerZero V2 Endpoint deployed on Ethereum mainnet.
    address public constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    address public fallbackRecipient = makeAddr("fallbackRecipient");

    function setUp() public virtual override {
        super.setUp();
        _deployCoreStack();
    }

    function _deployCoreStack() internal {
        coreDeployer = new CoreDeployer();

        DeployBase.CoreDeployments memory deployments_ = coreDeployer.deployCore(
            Config.PYUSDXConfig({
                name: "PayPal USD Yield",
                symbol: "PYUSDX",
                admin: admin,
                pauser: pauser,
                freezeManager: freezeManager,
                forcedTransferManager: forcedTransferManager,
                earnerManager: earnerManager,
                rateManager: rateManager
            }),
            Config.IssuerGatewayConfig({
                admin: admin,
                operator: operator,
                executor: executor,
                mintDelay: MINT_DELAY,
                mintTTL: MINT_TTL,
                rateLimitCapacity: type(uint128).max,
                rateLimitRefillPerSecond: 0
            }),
            Config.SwapFacilityConfig({ admin: admin, pauser: pauser }),
            Config.FactoryConfig({ admin: admin, factoryManager: factoryManager }),
            Config.PortalConfig({
                admin: admin,
                pauser: pauser,
                operator: operator,
                fallbackRecipient: fallbackRecipient,
                rateLimitCapacity: type(uint128).max,
                rateLimitRefillPerSecond: 0
            }),
            Config.LayerZeroBridgeAdapterConfig({ lzEndpoint: LZ_ENDPOINT, admin: admin, operator: operator })
        );

        pyusdx = PYUSDX(deployments_.pyusdxProxy);
        issuerGateway = IssuerGateway(deployments_.issuerGatewayProxy);
        swapFacility = SwapFacility(deployments_.swapFacilityProxy);
        factory = ExtensionFactory(deployments_.factoryProxy);
        yieldToOneBeacon = ExtensionBeacon(deployments_.yieldToOneBeaconProxy);
        multiMintBeacon = ExtensionBeacon(deployments_.multiMintBeaconProxy);
        portal = Portal(deployments_.portalProxy);
        layerZeroBridgeAdapter = LayerZeroBridgeAdapter(deployments_.layerZeroBridgeAdapterProxy);
        _coreDeployments = deployments_;
    }

    /// @dev Helper to mint PYUSDX through the time-delay mechanism
    function _mintPYUSDX(address recipient_, uint256 amount_) internal {
        vm.prank(operator);
        uint48 mintId = issuerGateway.proposeMint(amount_, recipient_);

        vm.warp(block.timestamp + MINT_DELAY);

        vm.prank(executor);
        issuerGateway.mint(mintId);
    }
}
