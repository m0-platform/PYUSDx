// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

// The config fixtures are JSON, written with the quoting Prettier selects for Solidity strings.
/* solhint-disable quotes */

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Config } from "../../script/Config.sol";
import { DeployBase } from "../../script/deploy/DeployBase.s.sol";
import { MigrationIncomplete, NothingExecutable } from "../../script/migrate/MigrateRolesBase.sol";
import { SafeMultisigRequired } from "../../script/migrate/ProposeMigrateRoles.s.sol";

import { ILayerZeroEndpointV2 } from "../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { IRateLimiter } from "../../src/abstract/interfaces/IRateLimiter.sol";

import { DeploymentRecordHarness } from "../harness/DeploymentRecordHarness.sol";
import {
    MigrateRolesEntrypointHarness,
    ProposeMigrateRolesEntrypointHarness,
    VerifyRolesEntrypointHarness
} from "../harness/MigrateRolesEntrypointHarness.sol";
import { CoreDeployer, IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @notice The role holders a `protocol.json` names, as one value so the fixture writer stays short.
struct Holders {
    address admin;
    address earnerManager;
    address fallbackRecipient;
    address lzOperator;
    address wrapperAdmin;
    address wrapperOperator;
    address outgoing;
}

/// @title  MigrateRolesEntrypointTests
/// @notice Drives the three migration entry points themselves -- `MigrateRoles.run()`,
///         `VerifyRoles.run()` and `ProposeMigrateRoles.run()` -- against a real core suite and a
///         real PortalOFTWrapper on a mainnet fork, with the desired holders coming from an actual
///         `protocol.json` written to disk and an actual deployment record.
/// @dev    The full acceptance narrative in one path: deploy with defaults, verify passes, edit the
///         JSON, verify now fails, migrate as each current holder in turn, verify passes, and a
///         rerun changes nothing.
///
///         Only the config-path and record-directory seams are redirected, through the same
///         `virtual` hooks production leaves for that. Everything else -- the loader, the plan, the
///         staging, `vm.rememberKey`/`vm.startBroadcast`, the Safe serialization -- is the
///         production code path. Signers are generated keys; no key or webhook is read from the
///         environment and nothing touches the network.
contract MigrateRolesEntrypointTests is IntegrationForkTest {
    uint128 internal constant _EARNER_CAPACITY = 5_000_000_000_000;
    uint128 internal constant _EARNER_REFILL = 2_500_000_000;
    uint128 internal constant _ISSUER_CAPACITY = 9_000_000_000_000;

    address internal _outgoing;
    uint256 internal _outgoingKey;

    address internal _incoming;
    uint256 internal _incomingKey;

    address internal _stranger;
    uint256 internal _strangerKey;

    address internal _newEarnerManager = makeAddr("entrypointEarnerManager");
    address internal _newFallbackRecipient = makeAddr("entrypointFallbackRecipient");

    CoreDeployer internal _deployer;
    DeployBase.CoreDeployments internal _stack;
    address internal _wrapper;

    MigrateRolesEntrypointHarness internal _migrate;
    VerifyRolesEntrypointHarness internal _verify;
    ProposeMigrateRolesEntrypointHarness internal _propose;

    function setUp() public override {
        super.setUp();

        (_outgoing, _outgoingKey) = makeAddrAndKey("outgoingHolder");
        (_incoming, _incomingKey) = makeAddrAndKey("incomingHolder");
        (_stranger, _strangerKey) = makeAddrAndKey("stranger");

        _deployStack();

        _migrate = new MigrateRolesEntrypointHarness();
        _verify = new VerifyRolesEntrypointHarness();
        _propose = new ProposeMigrateRolesEntrypointHarness();
    }

    /* ============ config loading ============ */

    function test_run_revertsOnConfigForAnotherChain() external {
        _prepare("wrongChain");
        _writeConfigForChain(_configPath("wrongChain"), block.chainid + 1, _desiredHolders());

        vm.expectRevert(bytes("config chainId does not match the target chain"));
        _verify.run();
    }

    function test_run_revertsOnZeroDesiredHolder() external {
        _prepare("zeroHolder");

        Holders memory holders = _desiredHolders();
        holders.admin = address(0);

        _writeConfig(_configPath("zeroHolder"), holders);

        vm.expectRevert(bytes("zero pyusdx.admin"));
        _verify.run();
    }

    /// @notice Proves `PROTOCOL_CONFIG` itself is what points the entry points at a config file.
    /// @dev    Reads the variable and never writes it, then skips when it is unset. A test that wrote
    ///         it would change the path `DeployAllConfigTests` resolves in a concurrently running
    ///         suite, which is why every other test here uses the harness seam instead. Run this one
    ///         on its own, with the variable pointing at the one scratch file it owns:
    ///
    ///           PROTOCOL_CONFIG=$PWD/out/test-deployments/MigrateRolesEntrypoints/env/protocol.json \
    ///             forge test --match-test test_verifyRoles_readsTheConfigPathFromTheEnvironment
    ///
    ///         That path is required, not merely suggested: the test writes the file the variable
    ///         names, so pointing it anywhere else -- a real chain config, or whatever a developer
    ///         happens to have exported -- would overwrite it. Any other value fails here, before
    ///         anything is written.
    function test_verifyRoles_readsTheConfigPathFromTheEnvironment() external {
        string memory path = vm.envOr("PROTOCOL_CONFIG", string(""));

        vm.skip(bytes(path).length == 0);

        assertEq(
            path,
            _configPath("env"),
            "PROTOCOL_CONFIG must be this test's own scratch file; it refuses to write anywhere else"
        );

        _writeRecord(_scratchDir("env"));

        // Config path left empty on the harness, so the production `PROTOCOL_CONFIG` lookup runs.
        _verify.useScratchPaths("", _scratchDir("env"));

        _writeConfigForChain(path, block.chainid, _deployedHolders());

        _verify.run();

        // Same variable, different contents: the file it names is what decides the outcome.
        _writeConfigForChain(path, block.chainid, _desiredHolders());

        vm.expectPartialRevert(MigrationIncomplete.selector);
        _verify.run();
    }

    /* ============ verify ============ */

    function test_verifyRoles_passesOnTheDeploymentDefaults() external {
        _prepare("defaults");

        // The chain is exactly what the config asks for, so there is nothing outstanding.
        _verify.run();
    }

    function test_verifyRoles_failsWhileWorkIsOutstanding() external {
        _prepare("incomplete");
        _writeConfig(_configPath("incomplete"), _desiredHolders());

        vm.expectPartialRevert(MigrationIncomplete.selector);
        _verify.run();
    }

    /* ============ migrate ============ */

    /// @notice The acceptance path, end to end through the entry points and an on-disk config.
    function test_migrateRoles_defaultsThenEditedJsonThenVerifyThenNoOpRerun() external {
        _prepare("acceptance");

        _verify.run();

        _writeConfig(_configPath("acceptance"), _desiredHolders());

        vm.expectPartialRevert(MigrationIncomplete.selector);
        _verify.run();

        _migrateAs(_outgoingKey);
        _migrateAs(_incomingKey);

        _verify.run();

        _assertMigrated();

        // A rerun after completion sends nothing and leaves the chain untouched.
        bytes32 fingerprint = _fingerprint();

        _migrateAs(_outgoingKey);
        _migrateAs(_incomingKey);

        assertEq(_fingerprint(), fingerprint);

        _verify.run();
    }

    function test_migrateRoles_revertsForASignerThatCanSendNothing() external {
        _prepare("stranger");
        _writeConfig(_configPath("stranger"), _desiredHolders());

        _migrate.useSignerKey(_strangerKey);

        vm.expectPartialRevert(NothingExecutable.selector);
        _migrate.run();
    }

    /* ============ propose ============ */

    function test_proposeMigrateRoles_revertsWithoutASafe() external {
        _prepare("noSafe");
        _writeConfig(_configPath("noSafe"), _desiredHolders());

        _propose.useSafe(address(0));

        vm.expectRevert(SafeMultisigRequired.selector);
        _propose.run();
    }

    /// @notice The Safe export is the same migration as a direct run, and it follows the Safe.
    /// @dev    The comparison is genuinely independent: the batch leaves the process as a Safe
    ///         Transaction Builder JSON, is read back off disk, replayed call by call as the Safe,
    ///         and the resulting chain state is compared against a direct `MigrateRoles` run from
    ///         the identical pre-state. Nothing is compared against the plan that produced it.
    ///
    ///         One test rather than two, because both need `safe/<chainid>-migrate-roles.json` and
    ///         forge does not roll the filesystem back between tests.
    function test_proposeMigrateRoles_exportReplaysToTheSameStateAsADirectRun() external {
        _prepare("parity");
        _writeConfig(_configPath("parity"), _desiredHolders());

        uint256 preState = vm.snapshotState();

        _migrateAs(_outgoingKey);

        bytes32 direct = _fingerprint();

        vm.revertToState(preState);

        // The plan is built for the Safe that will execute it, which here is the current holder. No
        // proposer key is configured anywhere: an offline export needs none.
        _propose.useSafe(_outgoing);
        _propose.run();

        (address[] memory targets, bytes[] memory payloads) = _readExportedBatch();

        assertGt(targets.length, 0);

        // Point the same plan at a Safe holding none of the outgoing authority and it can batch
        // nothing -- the executing Safe decides the batch, not whoever proposes it. The export
        // already on disk is untouched, so it still belongs to the first Safe.
        _propose.useSafe(_incoming);

        vm.expectPartialRevert(NothingExecutable.selector);
        _propose.run();

        (address[] memory stillOnDisk, ) = _readExportedBatch();

        assertEq(stillOnDisk.length, targets.length);

        for (uint256 i; i < targets.length; ++i) {
            vm.prank(_outgoing);
            (bool ok, ) = targets[i].call(payloads[i]);
            assertTrue(ok);
        }

        assertEq(_fingerprint(), direct);

        _removeExportedBatch();
    }

    /* ============ helpers ============ */

    /// @dev Deploys the suite every role holder starts on, plus the wrapper, exactly as production
    ///      does: the core suite first, then `DeployPortalOFTWrapper`'s underlying deploy.
    function _deployStack() internal {
        _deployer = new CoreDeployer();

        _stack = _deployer.deployCore(
            Config.PYUSDXConfig({
                name: "PayPal USD Yield",
                symbol: "PYUSDX",
                admin: _outgoing,
                pauser: _outgoing,
                freezeManager: _outgoing,
                forcedTransferManager: _outgoing,
                earnerManager: _outgoing,
                rateManager: _outgoing,
                earnerManagerRateLimitCapacity: _EARNER_CAPACITY,
                earnerManagerRateLimitRefillPerSecond: _EARNER_REFILL
            }),
            Config.IssuerGatewayConfig({
                admin: _outgoing,
                operator: _outgoing,
                executor: _outgoing,
                mintDelay: MINT_DELAY,
                mintTTL: MINT_TTL,
                rateLimitCapacity: _ISSUER_CAPACITY,
                rateLimitRefillPerSecond: 0
            }),
            Config.SwapFacilityConfig({ admin: _outgoing, pauser: _outgoing }),
            Config.FactoryConfig({ admin: _outgoing, factoryManager: _outgoing }),
            Config.PortalConfig({
                admin: _outgoing,
                pauser: _outgoing,
                operator: _outgoing,
                fallbackRecipient: fallbackRecipient,
                rateLimitCapacity: _ISSUER_CAPACITY,
                rateLimitRefillPerSecond: 0
            }),
            Config.LayerZeroBridgeAdapterConfig({ lzEndpoint: LZ_ENDPOINT, admin: _outgoing, operator: _outgoing })
        );

        (_wrapper, , ) = _deployer.deployPortalOFTWrapper(
            _stack.portalProxy,
            _stack.pyusdxProxy,
            _stack.layerZeroBridgeAdapterProxy,
            "PYUSDX",
            Config.PortalOFTWrapperConfig({ admin: _outgoing, operator: _outgoing })
        );
    }

    /// @dev Writes the deployment record and the deploy-defaults config for one test, then points
    ///      all three entry points at them. Per test, because forge rolls back EVM state between
    ///      tests but not the filesystem.
    function _prepare(string memory testName) internal {
        string memory dir = _scratchDir(testName);

        _writeRecord(dir);
        _writeConfig(_configPath(testName), _deployedHolders());

        _migrate.useScratchPaths(_configPath(testName), dir);
        _verify.useScratchPaths(_configPath(testName), dir);
        _propose.useScratchPaths(_configPath(testName), dir);

        _migrate.useSignerKey(_outgoingKey);
        _propose.useSafe(_outgoing);
    }

    /// @dev Writes the deployment record through the production writer, into a scratch directory.
    function _writeRecord(string memory dir) internal {
        DeploymentRecordHarness record = new DeploymentRecordHarness(dir);

        record.writeDeployment(block.chainid, "pyusdx", _stack.pyusdxProxy);
        record.writeDeployment(block.chainid, "issuerGateway", _stack.issuerGatewayProxy);
        record.writeDeployment(block.chainid, "swapFacility", _stack.swapFacilityProxy);
        record.writeDeployment(block.chainid, "extensionFactory", _stack.factoryProxy);
        record.writeDeployment(block.chainid, "yieldToOneBeacon", _stack.yieldToOneBeaconProxy);
        record.writeDeployment(block.chainid, "multiMintBeacon", _stack.multiMintBeaconProxy);
        record.writeDeployment(block.chainid, "portal", _stack.portalProxy);
        record.writeDeployment(block.chainid, "layerZeroBridgeAdapter", _stack.layerZeroBridgeAdapterProxy);
        record.writeDeployment(block.chainid, "pyusdxPortalOFTWrapper", _wrapper);
    }

    function _scratchDir(string memory testName) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/out/test-deployments/MigrateRolesEntrypoints/", testName);
    }

    function _configPath(string memory testName) internal view returns (string memory) {
        return string.concat(_scratchDir(testName), "/protocol.json");
    }

    function _deployedHolders() internal view returns (Holders memory) {
        return
            Holders({
                admin: _outgoing,
                earnerManager: _outgoing,
                fallbackRecipient: fallbackRecipient,
                lzOperator: _outgoing,
                wrapperAdmin: _outgoing,
                wrapperOperator: _outgoing,
                outgoing: _outgoing
            });
    }

    function _desiredHolders() internal view returns (Holders memory) {
        return
            Holders({
                admin: _incoming,
                earnerManager: _newEarnerManager,
                fallbackRecipient: _newFallbackRecipient,
                lzOperator: _incoming,
                wrapperAdmin: _incoming,
                wrapperOperator: _incoming,
                outgoing: _outgoing
            });
    }

    function _writeConfig(string memory path, Holders memory holders) internal {
        _writeConfigForChain(path, block.chainid, holders);
    }

    /// @dev A real `protocol.json`, in the schema `deploymentConfigs/README.md` documents, written to
    ///      disk for the script to read and parse.
    function _writeConfigForChain(string memory path, uint256 chainId, Holders memory holders) internal {
        string memory admin = vm.toString(holders.admin);
        string memory capacity = vm.toString(uint256(_EARNER_CAPACITY));
        string memory issuerCapacity = vm.toString(uint256(_ISSUER_CAPACITY));

        string memory json = string.concat(
            '{"chainId":',
            vm.toString(chainId),
            ',"pyusdx":{"name":"PayPal USD Yield","symbol":"PYUSDX","admin":"',
            admin,
            '","pauser":"',
            admin,
            '","freezeManager":"',
            admin,
            '","forcedTransferManager":"',
            admin,
            '","earnerManager":"',
            vm.toString(holders.earnerManager),
            '","rateManager":"',
            admin,
            '","earnerManagerRateLimit":{"capacity":',
            capacity,
            ',"refillPerSecond":',
            vm.toString(uint256(_EARNER_REFILL)),
            "}}"
        );

        json = string.concat(
            json,
            ',"issuerGateway":{"admin":"',
            admin,
            '","operator":"',
            admin,
            '","executor":"',
            admin,
            '","mintDelay":',
            vm.toString(uint256(MINT_DELAY)),
            ',"mintTTL":',
            vm.toString(uint256(MINT_TTL)),
            ',"rateLimit":{"capacity":',
            issuerCapacity,
            ',"refillPerSecond":0}}',
            ',"swapFacility":{"admin":"',
            admin,
            '","pauser":"',
            admin,
            '"},"extensionFactory":{"admin":"',
            admin,
            '","factoryManager":"',
            admin,
            '"}'
        );

        json = string.concat(
            json,
            ',"portal":{"admin":"',
            admin,
            '","pauser":"',
            admin,
            '","operator":"',
            admin,
            '","fallbackRecipient":"',
            vm.toString(holders.fallbackRecipient),
            '","rateLimit":{"capacity":',
            issuerCapacity,
            ',"refillPerSecond":0}}',
            ',"layerZeroBridgeAdapter":{"endpoint":"',
            vm.toString(LZ_ENDPOINT),
            '","admin":"',
            admin,
            '","operator":"',
            vm.toString(holders.lzOperator),
            '"}'
        );

        json = string.concat(
            json,
            ',"portalOFTWrapper":{"admin":"',
            vm.toString(holders.wrapperAdmin),
            '","operator":"',
            vm.toString(holders.wrapperOperator),
            '"},"migration":{"outgoingHolders":["',
            vm.toString(holders.outgoing),
            '"]}}'
        );

        vm.writeFile(path, json);
    }

    /// @dev Runs the real broadcast entry point as the given key.
    function _migrateAs(uint256 signerKey) internal {
        _migrate.useSignerKey(signerKey);
        _migrate.run();
    }

    /// @dev Reads the batch back the way a signer's tooling would: off disk, out of the Transaction
    ///      Builder JSON, with no reference to the plan that produced it.
    function _readExportedBatch() internal view returns (address[] memory targets, bytes[] memory payloads) {
        string memory json = vm.readFile(_exportPath());

        uint256 count;

        while (vm.keyExistsJson(json, _transactionKey(count, "to"))) {
            ++count;
        }

        targets = new address[](count);
        payloads = new bytes[](count);

        for (uint256 i; i < count; ++i) {
            targets[i] = vm.parseJsonAddress(json, _transactionKey(i, "to"));
            payloads[i] = vm.parseJsonBytes(json, _transactionKey(i, "data"));
        }
    }

    function _transactionKey(uint256 index, string memory field) internal pure returns (string memory) {
        return string.concat(".transactions[", vm.toString(index), "].", field);
    }

    function _exportPath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/safe/", vm.toString(block.chainid), "-migrate-roles.json");
    }

    function _removeExportedBatch() internal {
        if (vm.isFile(_exportPath())) vm.removeFile(_exportPath());
    }

    /// @dev Every value the migration is responsible for, as one word. Two runs that leave the same
    ///      fingerprint left the chain in the same state.
    function _fingerprint() internal view returns (bytes32) {
        (uint128 capacity, uint128 refill) = IRateLimiter(_stack.pyusdxProxy).getRateLimitConfig(_newEarnerManager);
        (uint128 staleCapacity, uint128 staleRefill) = IRateLimiter(_stack.pyusdxProxy).getRateLimitConfig(_outgoing);

        return
            keccak256(
                abi.encode(
                    _roleFingerprint(),
                    _proxyOwnerFingerprint(),
                    IPYUSDXReads(_stack.pyusdxProxy).earnerManager(),
                    IPortalReads(_stack.portalProxy).fallbackRecipient(),
                    ILayerZeroEndpointV2(LZ_ENDPOINT).delegates(_stack.layerZeroBridgeAdapterProxy),
                    capacity,
                    refill,
                    staleCapacity,
                    staleRefill
                )
            );
    }

    function _roleFingerprint() internal view returns (bytes32) {
        bytes32 pauserRole = IPYUSDXReads(_stack.pyusdxProxy).PAUSER_ROLE();
        bytes32 rateRole = IPYUSDXReads(_stack.pyusdxProxy).RATE_LIMIT_MANAGER_ROLE();
        bytes32 issuerRole = IPYUSDXReads(_stack.pyusdxProxy).ISSUER_ROLE();
        bytes32 wrapperOperatorRole = IWrapperReads(_wrapper).OPERATOR_ROLE();

        return
            keccak256(
                abi.encode(
                    _hasRole(_stack.pyusdxProxy, 0x00, _incoming),
                    _hasRole(_stack.pyusdxProxy, 0x00, _outgoing),
                    _hasRole(_stack.pyusdxProxy, pauserRole, _incoming),
                    _hasRole(_stack.pyusdxProxy, pauserRole, _outgoing),
                    _hasRole(_stack.pyusdxProxy, rateRole, _incoming),
                    _hasRole(_stack.pyusdxProxy, rateRole, _outgoing),
                    _hasRole(_stack.pyusdxProxy, issuerRole, _stack.issuerGatewayProxy),
                    _hasRole(_stack.pyusdxProxy, issuerRole, _stack.portalProxy),
                    _hasRole(_wrapper, 0x00, _incoming),
                    _hasRole(_wrapper, 0x00, _outgoing),
                    _hasRole(_wrapper, wrapperOperatorRole, _incoming),
                    _hasRole(_wrapper, wrapperOperatorRole, _outgoing),
                    _hasRole(_stack.layerZeroBridgeAdapterProxy, 0x00, _incoming),
                    _hasRole(_stack.layerZeroBridgeAdapterProxy, 0x00, _outgoing)
                )
            );
    }

    function _proxyOwnerFingerprint() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _proxyOwner(_stack.pyusdxProxy),
                    _proxyOwner(_stack.portalProxy),
                    _proxyOwner(_stack.yieldToOneBeaconProxy),
                    _proxyOwner(_stack.multiMintBeaconProxy),
                    _proxyOwner(_wrapper)
                )
            );
    }

    /// @dev The end state the acceptance path must reach, spelled out rather than hashed.
    function _assertMigrated() internal view {
        bytes32 wrapperOperatorRole = IWrapperReads(_wrapper).OPERATOR_ROLE();

        assertTrue(_hasRole(_stack.pyusdxProxy, 0x00, _incoming));
        assertFalse(_hasRole(_stack.pyusdxProxy, 0x00, _outgoing));

        assertTrue(_hasRole(_wrapper, 0x00, _incoming));
        assertTrue(_hasRole(_wrapper, wrapperOperatorRole, _incoming));
        assertFalse(_hasRole(_wrapper, 0x00, _outgoing));
        assertFalse(_hasRole(_wrapper, wrapperOperatorRole, _outgoing));

        assertEq(_proxyOwner(_wrapper), _incoming);
        assertEq(_proxyOwner(_stack.pyusdxProxy), _incoming);

        assertEq(IPYUSDXReads(_stack.pyusdxProxy).earnerManager(), _newEarnerManager);
        assertEq(IPortalReads(_stack.portalProxy).fallbackRecipient(), _newFallbackRecipient);
        assertEq(ILayerZeroEndpointV2(LZ_ENDPOINT).delegates(_stack.layerZeroBridgeAdapterProxy), _incoming);

        // Untouched throughout: issuance must survive the handover.
        bytes32 issuerRole = IPYUSDXReads(_stack.pyusdxProxy).ISSUER_ROLE();

        assertTrue(_hasRole(_stack.pyusdxProxy, issuerRole, _stack.issuerGatewayProxy));
        assertTrue(_hasRole(_stack.pyusdxProxy, issuerRole, _stack.portalProxy));
    }

    function _hasRole(address target, bytes32 role, address account) internal view returns (bool) {
        return IAccessControl(target).hasRole(role, account);
    }

    function _proxyOwner(address proxy) internal view returns (address) {
        return IOwnableReads(_adminOf(proxy)).owner();
    }

    function _adminOf(address proxy) internal view returns (address) {
        // ERC-1967 admin slot, the same one `Upgrades.getAdminAddress` reads.
        return
            address(
                uint160(uint256(vm.load(proxy, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)))
            );
    }
}

/// @dev Minimal read surfaces, to keep the test off the production contract types whose forge-std
///      version differs from the test tree's.
interface IPYUSDXReads {
    function ISSUER_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function RATE_LIMIT_MANAGER_ROLE() external view returns (bytes32);

    function earnerManager() external view returns (address);
}

interface IPortalReads {
    function fallbackRecipient() external view returns (address);
}

interface IWrapperReads {
    function OPERATOR_ROLE() external view returns (bytes32);
}

interface IOwnableReads {
    function owner() external view returns (address);
}
