// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

// JSON fixtures use the quoting selected by Prettier to avoid escaped property names.
/* solhint-disable quotes */

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { DeployAll } from "../../../script/deploy/DeployAll.s.sol";
import { DeployAllHarness } from "../../harness/DeployAllHarness.sol";

/// @title  DeployAllConfigTests
/// @notice Covers the protocol configuration DeployAll reads from
///         `deploymentConfigs/<chainid>/protocol.json` (INT-467): the example template stays in sync
///         with the schema, every checked-in chain config parses, and invalid configuration is
///         rejected before anything is broadcast.
contract DeployAllConfigTests is Test {
    /// @dev The chainId recorded in `deploymentConfigs/example-protocol.json`.
    uint256 internal constant EXAMPLE_CHAIN_ID = 31337;

    DeployAllHarness internal harness;

    function setUp() external {
        harness = new DeployAllHarness();
    }

    /* ============ Helpers ============ */

    /// @dev Every chain with a checked-in `deploymentConfigs/<chainid>/protocol.json`.
    function _chainIds() internal pure returns (uint256[8] memory) {
        return [uint256(1), 143, 8453, 42161, 10143, 84532, 421614, 11155111];
    }

    function _exampleJson() internal view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/deploymentConfigs/example-protocol.json"));
    }

    function _exampleConfig() internal view returns (DeployAll.ProtocolConfig memory) {
        return harness.parseProtocolConfig(_exampleJson(), EXAMPLE_CHAIN_ID);
    }

    /* ============ Template Tests ============ */

    /// @notice Keeps `deploymentConfigs/example-protocol.json` in sync with the schema the script
    ///         expects. Each sentinel address is distinct, so a mis-wired JSON key fails here.
    function test_parseConfig_exampleTemplate() external view {
        DeployAll.ProtocolConfig memory config = _exampleConfig();

        assertEq(config.pyusdx.name, "PYUSDx");
        assertEq(config.pyusdx.symbol, "PYUSDx");
        assertEq(config.pyusdx.admin, address(1));
        assertEq(config.pyusdx.pauser, address(2));
        assertEq(config.pyusdx.freezeManager, address(3));
        assertEq(config.pyusdx.forcedTransferManager, address(4));
        assertEq(config.pyusdx.earnerManager, address(5));
        assertEq(config.pyusdx.rateManager, address(6));
        assertEq(config.pyusdx.earnerManagerRateLimitCapacity, 5_000_000e6);
        assertEq(config.pyusdx.earnerManagerRateLimitRefillPerSecond, 2_500e6);

        assertEq(config.issuerGateway.admin, address(7));
        assertEq(config.issuerGateway.operator, address(8));
        assertEq(config.issuerGateway.executor, address(9));
        assertEq(config.issuerGateway.mintDelay, 300);
        assertEq(config.issuerGateway.mintTTL, 10_800);
        assertEq(config.issuerGateway.rateLimitCapacity, 25_000_000e6);
        assertEq(config.issuerGateway.rateLimitRefillPerSecond, 12_500e6);

        assertEq(config.swapFacility.admin, address(10));
        assertEq(config.swapFacility.pauser, address(11));

        assertEq(config.extensionFactory.admin, address(12));
        assertEq(config.extensionFactory.factoryManager, address(13));

        assertEq(config.portal.admin, address(14));
        assertEq(config.portal.pauser, address(15));
        assertEq(config.portal.operator, address(16));
        assertEq(config.portal.fallbackRecipient, address(17));
        assertEq(config.portal.rateLimitCapacity, 10_000_000e6);
        assertEq(config.portal.rateLimitRefillPerSecond, 5_000e6);

        assertEq(config.layerZeroBridgeAdapter.lzEndpoint, address(18));
        assertEq(config.layerZeroBridgeAdapter.admin, address(19));
        assertEq(config.layerZeroBridgeAdapter.operator, address(20));
    }

    /* ============ Checked-in Chain Config Tests ============ */

    /// @notice Every chain config in the repo must parse and validate. A config that only fails at
    ///         deploy time is a config that fails with a funded deployer and a half-deployed stack.
    function test_readConfig_everyCheckedInChainConfigIsValid() external view {
        uint256[8] memory chainIds = _chainIds();

        for (uint256 i; i < chainIds.length; ++i) {
            uint256 chainId = chainIds[i];

            assertTrue(
                vm.isFile(harness.protocolConfigPath(chainId)),
                string.concat("missing protocol config for chain ", vm.toString(chainId))
            );

            // Reverts on a bad chainId guard, a missing key, or a validation failure.
            harness.readProtocolConfig(chainId);
        }
    }

    function test_configPath_defaultsToPerChainFile() external view {
        assertEq(
            harness.protocolConfigPath(8453),
            string.concat(vm.projectRoot(), "/deploymentConfigs/8453/protocol.json")
        );
    }

    function test_readConfig_revertsOnMissingFile() external {
        uint256 unknownChainId = 999_999_999;

        vm.expectRevert(
            bytes(
                string.concat(
                    "missing protocol config file (see deploymentConfigs/README.md#deployment-configuration): ",
                    harness.protocolConfigPath(unknownChainId)
                )
            )
        );

        harness.readProtocolConfig(unknownChainId);
    }

    /* ============ Chain Guard Tests ============ */

    /// @notice Regression: a copy-pasted config must not deploy against the wrong chain.
    function test_parseConfig_revertsOnChainIdMismatch() external {
        vm.expectRevert(bytes("config chainId does not match the target chain"));
        harness.parseProtocolConfig(_exampleJson(), EXAMPLE_CHAIN_ID + 1);
    }

    function test_parseConfig_revertsOnChainIdMismatchForCheckedInConfig() external {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/deploymentConfigs/8453/protocol.json"));

        vm.expectRevert(bytes("config chainId does not match the target chain"));
        harness.parseProtocolConfig(json, 1);
    }

    /* ============ Numeric Bound Tests ============ */

    function test_parseConfig_revertsWhenRateLimitCapacityExceedsUint128() external {
        string memory json = _withRawValue(
            '"capacity": 5000000000000',
            '"capacity": 340282366920938463463374607431768211456'
        );

        vm.expectRevert(bytes(".pyusdx.earnerManagerRateLimit.capacity exceeds uint128"));
        harness.parseProtocolConfig(json, EXAMPLE_CHAIN_ID);
    }

    function test_parseConfig_revertsWhenMintTTLExceedsUint32() external {
        string memory json = _withRawValue('"mintTTL": 10800', '"mintTTL": 4294967296');

        vm.expectRevert(bytes(".issuerGateway.mintTTL exceeds uint32"));
        harness.parseProtocolConfig(json, EXAMPLE_CHAIN_ID);
    }

    function test_parseConfig_acceptsQuotedNumbers() external view {
        string memory json = _withRawValue('"capacity": 5000000000000', '"capacity": "5000000000000"');

        DeployAll.ProtocolConfig memory config = harness.parseProtocolConfig(json, EXAMPLE_CHAIN_ID);

        assertEq(config.pyusdx.earnerManagerRateLimitCapacity, 5_000_000e6);
    }

    /* ============ Validation Tests ============ */

    function test_validateConfig_acceptsTheExampleTemplate() external view {
        harness.validateProtocolConfig(_exampleConfig());
    }

    function test_validateConfig_revertsOnEmptyPYUSDXName() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.pyusdx.name = "";

        vm.expectRevert(bytes("zero pyusdx.name"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnEmptyPYUSDXSymbol() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.pyusdx.symbol = "";

        vm.expectRevert(bytes("zero pyusdx.symbol"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroPYUSDXAdmin() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.pyusdx.admin = address(0);

        vm.expectRevert(bytes("zero pyusdx.admin"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroPYUSDXRateManager() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.pyusdx.rateManager = address(0);

        vm.expectRevert(bytes("zero pyusdx.rateManager"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroPYUSDXEarnerManager() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.pyusdx.earnerManager = address(0);

        vm.expectRevert(bytes("zero pyusdx.earnerManager"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroIssuerGatewayOperator() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.issuerGateway.operator = address(0);

        vm.expectRevert(bytes("zero issuerGateway.operator"));
        harness.validateProtocolConfig(config);
    }

    /// @notice `IssuerGateway._setMintTTL` reverts on a zero TTL, so reject it up front.
    function test_validateConfig_revertsOnZeroMintTTL() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.issuerGateway.mintTTL = 0;

        vm.expectRevert(bytes("zero issuerGateway.mintTTL"));
        harness.validateProtocolConfig(config);
    }

    /// @notice A zero mint delay is a legitimate configuration (instant mints).
    function test_validateConfig_allowsZeroMintDelay() external view {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.issuerGateway.mintDelay = 0;

        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroSwapFacilityPauser() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.swapFacility.pauser = address(0);

        vm.expectRevert(bytes("zero swapFacility.pauser"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroFactoryManager() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.extensionFactory.factoryManager = address(0);

        vm.expectRevert(bytes("zero extensionFactory.factoryManager"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroPortalFallbackRecipient() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.portal.fallbackRecipient = address(0);

        vm.expectRevert(bytes("zero portal.fallbackRecipient"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroLayerZeroEndpoint() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.layerZeroBridgeAdapter.lzEndpoint = address(0);

        vm.expectRevert(bytes("zero layerZeroBridgeAdapter.endpoint"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroLayerZeroOperator() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.layerZeroBridgeAdapter.operator = address(0);

        vm.expectRevert(bytes("zero layerZeroBridgeAdapter.operator"));
        harness.validateProtocolConfig(config);
    }

    /* ============ Rate Limit Bound Tests ============ */

    /// @notice Regression: `RateLimiter.setRateLimit` reverts with `InvalidRateLimitConfig` on a zero
    ///         capacity, and DeployAll enables all three limits. Catching it here fails the run before
    ///         a single contract is deployed rather than after PYUSDX and the Portal are already live.
    function test_validateConfig_revertsOnZeroPortalRateLimitCapacity() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.portal.rateLimitCapacity = 0;

        vm.expectRevert(bytes("zero portal.rateLimit.capacity: an enabled rate limit needs capacity"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroIssuerGatewayRateLimitCapacity() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.issuerGateway.rateLimitCapacity = 0;

        vm.expectRevert(bytes("zero issuerGateway.rateLimit.capacity: an enabled rate limit needs capacity"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsOnZeroEarnerManagerRateLimitCapacity() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.pyusdx.earnerManagerRateLimitCapacity = 0;

        vm.expectRevert(bytes("zero pyusdx.earnerManagerRateLimit.capacity: an enabled rate limit needs capacity"));
        harness.validateProtocolConfig(config);
    }

    function test_validateConfig_revertsWhenRefillExceedsCapacity() external {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.portal.rateLimitRefillPerSecond = config.portal.rateLimitCapacity + 1;

        vm.expectRevert(bytes("portal.rateLimit.refillPerSecond exceeds capacity"));
        harness.validateProtocolConfig(config);
    }

    /// @notice A refill equal to the capacity is the fastest sane bucket: full refill in one second.
    function test_validateConfig_allowsRefillEqualToCapacity() external view {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.portal.rateLimitRefillPerSecond = config.portal.rateLimitCapacity;

        harness.validateProtocolConfig(config);
    }

    /// @notice A zero refill is a legitimate configuration: a one-shot bucket that never refills.
    function test_validateConfig_allowsZeroRefill() external view {
        DeployAll.ProtocolConfig memory config = _exampleConfig();
        config.portal.rateLimitRefillPerSecond = 0;

        harness.validateProtocolConfig(config);
    }

    /* ============ Internal ============ */

    /// @dev Rewrites the first occurrence of `from` in the example template. Used to build a config
    ///      whose JSON is malformed in exactly one way.
    function _withRawValue(string memory from, string memory to) internal view returns (string memory) {
        return vm.replace(_exampleJson(), from, to);
    }
}
