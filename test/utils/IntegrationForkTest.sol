// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { Config } from "../../script/Config.sol";
import { DeployBase } from "../../script/deploy/DeployBase.s.sol";

import { MinterGateway } from "../../src/core/MinterGateway.sol";
import { PYUSDX } from "../../src/PYUSDX.sol";
import { ExtensionFactory } from "../../src/platform/ExtensionFactory.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";

import { BaseForkTest } from "./BaseForkTest.sol";

/// @notice Exposes DeployBase._deployCore() externally to avoid forge-std diamond inheritance in tests.
contract CoreDeployer is DeployBase {
    function deployCore(
        PYUSDXConfig memory pyusdxConfig_,
        MinterGatewayConfig memory minterGatewayConfig_,
        SwapFacilityConfig memory swapFacilityConfig_,
        FactoryConfig memory factoryConfig_
    ) external returns (CoreDeployments memory) {
        return _deployCore(address(this), pyusdxConfig_, minterGatewayConfig_, swapFacilityConfig_, factoryConfig_);
    }
}

/// @title IntegrationForkTest
/// @notice Base test that deploys the full PYUSDX stack via DeployBase deploy scripts
/// @dev Uses CREATE3 via CreateX factory (available on mainnet forks).
///      Uses composition with CoreDeployer to avoid forge-std diamond inheritance
///      between lib/forge-std (scripts) and lib/evm-m-extensions/lib/forge-std (tests).
abstract contract IntegrationForkTest is BaseForkTest {
    PYUSDX public pyusdx;
    MinterGateway public minterGateway;
    SwapFacility public swapFacility;
    ExtensionFactory public factory;

    DeployBase.CoreDeployments internal _coreDeployments;

    uint32 public constant MINT_DELAY = 1; // 1 second for testing
    uint32 public constant MINT_TTL = 3600; // 1 hour

    function setUp() public virtual override {
        super.setUp();
        _deployCoreStack();
    }

    function _deployCoreStack() internal {
        CoreDeployer coreDeployer_ = new CoreDeployer();

        DeployBase.CoreDeployments memory deployments_ = coreDeployer_.deployCore(
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
            Config.MinterGatewayConfig({ admin: admin, minter: minter, mintDelay: MINT_DELAY, mintTTL: MINT_TTL }),
            Config.SwapFacilityConfig({ admin: admin, pauser: pauser }),
            Config.FactoryConfig({ admin: admin, factoryManager: factoryManager })
        );

        pyusdx = PYUSDX(deployments_.pyusdxProxy);
        minterGateway = MinterGateway(deployments_.minterGatewayProxy);
        swapFacility = SwapFacility(deployments_.swapFacilityProxy);
        factory = ExtensionFactory(deployments_.factoryProxy);
        _coreDeployments = deployments_;
    }

    /// @dev Helper to mint PYUSDX through the time-delay mechanism
    function _mintPYUSDX(address recipient_, uint256 amount_) internal {
        vm.prank(minter);
        uint48 mintId_ = minterGateway.proposeMint(amount_, recipient_);

        vm.warp(block.timestamp + MINT_DELAY);

        minterGateway.mint(mintId_);
    }
}
