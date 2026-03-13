// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { BaseIntegrationTest } from "./BaseIntegrationTest.sol";

/// @title BaseForkTest
/// @notice Base test contract for mainnet fork tests with real token support
/// @dev Fork tests only run when MAINNET_RPC_URL is set. Use `make fork` to run.
abstract contract BaseForkTest is BaseIntegrationTest {
    // Mainnet token addresses
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant PYUSD = IERC20(0x6c3ea9036406852006290770BEdFcAbA0e23A0e8);

    // Whale addresses for acquiring test funds
    address internal constant USDC_WHALE = 0xEe7aE85f2Fe2239E27D9c1E23fFFe168D63b4055; // Binance Hot Wallet 34
    address internal constant PYUSD_WHALE = 0x6Cd57B9a87C96421cfd7bc2B2f940C7e89cac4b5;

    uint256 internal mainnetFork;

    function setUp() public virtual override {
        mainnetFork = vm.createSelectFork("mainnet");
        super.setUp();
    }

    /// @dev Deal USDC to an address by transferring from whale
    function _dealUSDC(address to, uint256 amount) internal {
        vm.prank(USDC_WHALE);
        USDC.transfer(to, amount);
    }

    /// @dev Deal PYUSD to an address by transferring from whale
    function _dealPYUSD(address to, uint256 amount) internal {
        vm.prank(PYUSD_WHALE);
        PYUSD.transfer(to, amount);
    }
}
