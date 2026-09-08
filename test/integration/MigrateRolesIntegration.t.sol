// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Config } from "../../script/Config.sol";
import { ScriptBase } from "../../script/ScriptBase.s.sol";
import { Transaction } from "../../script/libraries/TransactionHelper.sol";
import {
    MigrationAction,
    MissingDeployment,
    NoOutgoingHolders,
    NotAContract,
    PortalOFTWrapperNotConfigured,
    UnexpectedWiring,
    UnreadableState,
    ZeroOutgoingHolder
} from "../../script/migrate/MigrateRolesBase.sol";

import { ILayerZeroEndpointV2 } from "../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { IRateLimiter } from "../../src/abstract/interfaces/IRateLimiter.sol";
import { DeployBase } from "../../script/deploy/DeployBase.s.sol";

import { MigrateRolesHarness } from "../harness/MigrateRolesHarness.sol";
import { CoreDeployer, IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @title  MigrateRolesIntegrationTests
/// @notice Exercises the config-driven role migration against a real core stack deployed by the
///         production deploy path on a mainnet fork: deploy with defaults, edit the desired holders,
///         migrate, verify, and re-run to a no-op.
/// @dev    The outgoing authority holders are `MigrateRolesHarness` instances rather than EOAs so the
///         batch can be sent by them through `TransactionHelper.execute` exactly as the direct script
///         does. Three distinct holders (admin, rate-limit manager, LayerZero operator) are what makes
///         the multi-holder resume and the delegate-restore deferral observable.
contract MigrateRolesIntegrationTests is IntegrationForkTest {
    MigrateRolesHarness internal _adminHolder;
    MigrateRolesHarness internal _rateHolder;
    MigrateRolesHarness internal _newLzOperator;

    CoreDeployer internal _deployer;
    DeployBase.CoreDeployments internal _stack;
    address internal _wrapper;

    address internal _newAdmin = makeAddr("newAdmin");
    address internal _newPauser = makeAddr("newPauser");
    address internal _newFreezeManager = makeAddr("newFreezeManager");
    address internal _newForcedTransferManager = makeAddr("newForcedTransferManager");
    address internal _newEarnerManager = makeAddr("newEarnerManager");
    address internal _newRateManager = makeAddr("newRateManager");
    address internal _newOperator = makeAddr("newOperator");
    address internal _newExecutor = makeAddr("newExecutor");
    address internal _newFactoryManager = makeAddr("newFactoryManager");
    address internal _newFallbackRecipient = makeAddr("newFallbackRecipient");

    uint128 internal constant _EARNER_CAPACITY = 5_000_000_000_000;
    uint128 internal constant _EARNER_REFILL = 2_500_000_000;

    function setUp() public override {
        super.setUp();

        _adminHolder = new MigrateRolesHarness();
        _rateHolder = new MigrateRolesHarness();
        _newLzOperator = new MigrateRolesHarness();

        _deployer = new CoreDeployer();
        _stack = _deployer.deployCore(
            _outgoingPYUSDXConfig(),
            _outgoingIssuerGatewayConfig(),
            Config.SwapFacilityConfig({ admin: address(_adminHolder), pauser: pauser }),
            Config.FactoryConfig({ admin: address(_adminHolder), factoryManager: factoryManager }),
            _outgoingPortalConfig(),
            Config.LayerZeroBridgeAdapterConfig({
                lzEndpoint: LZ_ENDPOINT,
                admin: address(_adminHolder),
                operator: address(_adminHolder)
            })
        );

        // Deployed exactly as production does it -- a separate step after the core suite, through
        // the same `DeployBase._deployPortalOFTWrapper` the deploy script calls. Mainnet and
        // Arbitrum both record one, so the migration's wrapper branch is not optional there.
        (_wrapper, , ) = _deployer.deployPortalOFTWrapper(
            _stack.portalProxy,
            _stack.pyusdxProxy,
            _stack.layerZeroBridgeAdapterProxy,
            "PYUSDX",
            Config.PortalOFTWrapperConfig({ admin: address(_adminHolder), operator: address(_adminHolder) })
        );
    }

    /* ============ preflight ============ */

    function test_planMigration_missingCoreDeployment() public {
        ScriptBase.Deployments memory record = _record();
        record.swapFacility = address(0);

        vm.expectRevert(abi.encodeWithSelector(MissingDeployment.selector, "swapFacility"));
        _adminHolder.planMigration(record, _desiredConfig(), _migrationConfig(), address(_adminHolder));
    }

    function test_planMigration_missingBeaconDeployment() public {
        ScriptBase.Deployments memory record = _record();
        record.yieldToOneBeacon = address(0);

        vm.expectRevert(abi.encodeWithSelector(MissingDeployment.selector, "yieldToOneBeacon"));
        _adminHolder.planMigration(record, _desiredConfig(), _migrationConfig(), address(_adminHolder));
    }

    function test_planMigration_deploymentWithoutCode() public {
        ScriptBase.Deployments memory record = _record();
        record.portal = makeAddr("notAContract");

        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "portal", record.portal));
        _adminHolder.planMigration(record, _desiredConfig(), _migrationConfig(), address(_adminHolder));
    }

    function test_planMigration_noOutgoingHolders() public {
        Config.MigrationConfig memory migration = _migrationConfig();
        migration.outgoingHolders = new address[](0);

        vm.expectRevert(NoOutgoingHolders.selector);
        _adminHolder.planMigration(_record(), _desiredConfig(), migration, address(_adminHolder));
    }

    function test_planMigration_zeroOutgoingHolder() public {
        Config.MigrationConfig memory migration = _migrationConfig();
        migration.outgoingHolders[1] = address(0);

        vm.expectRevert(abi.encodeWithSelector(ZeroOutgoingHolder.selector, 1));
        _adminHolder.planMigration(_record(), _desiredConfig(), migration, address(_adminHolder));
    }

    function test_planMigration_portalOFTWrapperDeployedWithoutConfig() public {
        Config.MigrationConfig memory migration = _migrationConfig();
        migration.hasPortalOFTWrapper = false;

        vm.expectRevert(abi.encodeWithSelector(PortalOFTWrapperNotConfigured.selector, _wrapper));
        _adminHolder.planMigration(_record(), _desiredConfig(), migration, address(_adminHolder));
    }

    function test_planMigration_portalOFTWrapperAbsentIsSkipped() public view {
        ScriptBase.Deployments memory record = _record();
        record.pyusdxPortalOFTWrapper = address(0);

        MigrationAction[] memory actions = _adminHolder.planMigration(
            record,
            _desiredConfig(),
            _migrationConfig(),
            address(_adminHolder)
        );

        // A chain with no wrapper plans nothing against one, and planning must not revert.
        assertGt(actions.length, 0);
        assertFalse(_plansAnyCallTo(actions, _wrapper));
        assertFalse(_plansAnyCallTo(actions, _adminHolder.proxyAdminOf(_wrapper)));
    }

    function test_planMigration_issuerRoleMissing() public {
        bytes32 issuerRole = _pyusdx().ISSUER_ROLE();

        vm.prank(address(_adminHolder));
        IAccessControl(address(_stack.pyusdxProxy)).revokeRole(issuerRole, address(_stack.portalProxy));

        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedWiring.selector, "pyusdx.ISSUER_ROLE(portal)", address(_stack.portalProxy))
        );
        _adminHolder.planMigration(_record(), _desiredConfig(), _migrationConfig(), address(_adminHolder));
    }

    function test_planMigration_layerZeroEndpointMismatch() public {
        Config.ProtocolConfig memory config = _desiredConfig();
        config.layerZeroBridgeAdapter.lzEndpoint = makeAddr("wrongEndpoint");

        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedWiring.selector,
                "layerZeroBridgeAdapter.endpoint",
                config.layerZeroBridgeAdapter.lzEndpoint
            )
        );
        _adminHolder.planMigration(_record(), config, _migrationConfig(), address(_adminHolder));
    }

    function test_planMigration_unauthorizedExecutorStagesNothing() public {
        address stranger = makeAddr("stranger");

        MigrationAction[] memory actions = _adminHolder.planMigration(
            _record(),
            _desiredConfig(),
            _migrationConfig(),
            stranger
        );

        assertGt(_adminHolder.outstandingCount(actions), 0);
        assertEq(_adminHolder.stagedTransactions(actions).length, 0);
    }

    /* ============ migration ============ */

    function test_migrateRoles_completesFromDeploymentDefaults() public {
        _migrateToCompletion();

        assertEq(_outstanding(), 0);

        assertTrue(_hasRole(_stack.pyusdxProxy, 0x00, _newAdmin));
        assertTrue(_hasRole(_stack.pyusdxProxy, _pyusdx().PAUSER_ROLE(), _newPauser));
        assertTrue(_hasRole(_stack.pyusdxProxy, _pyusdx().FREEZE_MANAGER_ROLE(), _newFreezeManager));
        assertTrue(_hasRole(_stack.pyusdxProxy, _pyusdx().FORCED_TRANSFER_MANAGER_ROLE(), _newForcedTransferManager));
        assertTrue(_hasRole(_stack.pyusdxProxy, _pyusdx().RATE_LIMIT_MANAGER_ROLE(), _newRateManager));

        assertFalse(_hasRole(_stack.pyusdxProxy, 0x00, address(_adminHolder)));
        assertFalse(_hasRole(_stack.pyusdxProxy, _pyusdx().PAUSER_ROLE(), pauser));
        assertFalse(_hasRole(_stack.pyusdxProxy, _pyusdx().RATE_LIMIT_MANAGER_ROLE(), address(_rateHolder)));

        assertEq(_pyusdx().earnerManager(), _newEarnerManager);
        assertEq(_portal().fallbackRecipient(), _newFallbackRecipient);

        (uint128 capacity, uint128 refill) = IRateLimiter(_stack.pyusdxProxy).getRateLimitConfig(_newEarnerManager);
        assertEq(capacity, _EARNER_CAPACITY);
        assertEq(refill, _EARNER_REFILL);

        (uint128 staleCapacity, uint128 staleRefill) = IRateLimiter(_stack.pyusdxProxy).getRateLimitConfig(
            earnerManager
        );
        assertEq(staleCapacity, 0);
        assertEq(staleRefill, 0);

        assertEq(_proxyOwner(_stack.pyusdxProxy), _newAdmin);
        assertEq(_proxyOwner(_stack.yieldToOneBeaconProxy), _newAdmin);
        assertEq(_proxyOwner(_stack.multiMintBeaconProxy), _newAdmin);

        assertEq(
            ILayerZeroEndpointV2(LZ_ENDPOINT).delegates(_stack.layerZeroBridgeAdapterProxy),
            address(_newLzOperator)
        );

        _assertWrapperMigrated();
    }

    /// @dev The wrapper half of the completion test, split out only to keep the stack shallow.
    ///      Covers every obligation the plan carries for it: both roles moved to their configured
    ///      holders, the outgoing holder stripped of both, and upgrade authority transferred.
    function _assertWrapperMigrated() internal view {
        assertTrue(_hasRole(_wrapper, 0x00, _newAdmin));
        assertTrue(_hasRole(_wrapper, _wrapperOperatorRole(), _newOperator));

        assertFalse(_hasRole(_wrapper, 0x00, address(_adminHolder)));
        assertFalse(_hasRole(_wrapper, _wrapperOperatorRole(), address(_adminHolder)));

        assertEq(_proxyOwner(_wrapper), _newAdmin);

        // The wiring preflight asserts against these, so they must still be the recorded suite.
        assertEq(IPortalOFTWrapperLike(_wrapper).portal(), _stack.portalProxy);
        assertEq(IPortalOFTWrapperLike(_wrapper).layerZeroBridgeAdapter(), _stack.layerZeroBridgeAdapterProxy);
    }

    function test_migrateRoles_preservesIssuerRolesAndBuckets() public {
        (uint128 gatewayCapacity, uint128 gatewayRefill) = IRateLimiter(_stack.pyusdxProxy).getRateLimitConfig(
            _stack.issuerGatewayProxy
        );

        _migrateToCompletion();

        assertTrue(_hasRole(_stack.pyusdxProxy, _pyusdx().ISSUER_ROLE(), _stack.issuerGatewayProxy));
        assertTrue(_hasRole(_stack.pyusdxProxy, _pyusdx().ISSUER_ROLE(), _stack.portalProxy));

        (uint128 capacity, uint128 refill) = IRateLimiter(_stack.pyusdxProxy).getRateLimitConfig(
            _stack.issuerGatewayProxy
        );
        assertEq(capacity, gatewayCapacity);
        assertEq(refill, gatewayRefill);
    }

    function test_migrateRoles_rerunAfterCompletionIsNoOp() public {
        _migrateToCompletion();

        assertEq(_stagedFor(address(_adminHolder)).length, 0);
        assertEq(_stagedFor(address(_rateHolder)).length, 0);
        assertEq(_stagedFor(address(_newLzOperator)).length, 0);
        assertEq(_outstanding(), 0);
    }

    function test_migrateRoles_retainsOutgoingHolderThatIsAlsoDesired() public {
        Config.ProtocolConfig memory config = _desiredConfig();
        config.issuerGateway.operator = operator; // `operator` is an outgoing holder and stays the target.

        _runAs(_adminHolder, config);
        _runAs(_rateHolder, config);
        _runAs(_newLzOperator, config);
        _runAs(_adminHolder, config);

        assertTrue(_hasRole(_stack.issuerGatewayProxy, _gateway().OPERATOR_ROLE(), operator));
    }

    /// @dev Regression: the bucket guard is `ISSUER_ROLE` membership, not the two known issuer
    ///      addresses. An issuer granted after deployment that also appears among the outgoing
    ///      holders keeps its bucket, or it would be left able to mint and unable to.
    function test_migrateRoles_preservesBucketOfIssuerGrantedAfterDeployment() public {
        address thirdIssuer = makeAddr("thirdIssuer");

        // Resolved before the prank: a getter call in the argument list would consume it.
        bytes32 issuerRole = _pyusdx().ISSUER_ROLE();

        vm.prank(address(_adminHolder));
        IAccessControl(_stack.pyusdxProxy).grantRole(issuerRole, thirdIssuer);

        vm.prank(address(_rateHolder));
        IRateLimiter(_stack.pyusdxProxy).setRateLimit(thirdIssuer, _EARNER_CAPACITY, _EARNER_REFILL, true);

        Config.MigrationConfig memory migration = _migrationConfig();
        migration.outgoingHolders = _outgoingHoldersPlus(thirdIssuer);

        MigrationAction[] memory actions = _adminHolder.planMigration(
            _record(),
            _desiredConfig(),
            migration,
            address(_rateHolder)
        );

        // The superseded earner manager is retired; the issuer is not even considered.
        assertTrue(_plansCall(actions, _stack.pyusdxProxy, _retireBucketCall(earnerManager)));
        assertFalse(_plansCall(actions, _stack.pyusdxProxy, _retireBucketCall(thirdIssuer)));

        _runAs(_rateHolder, _desiredConfig(), migration);

        (uint128 capacity, uint128 refill) = IRateLimiter(_stack.pyusdxProxy).getRateLimitConfig(thirdIssuer);
        assertEq(capacity, _EARNER_CAPACITY);
        assertEq(refill, _EARNER_REFILL);
    }

    /// @dev Fail closed: an `ISSUER_ROLE` membership that cannot be read is not guessed. Treating
    ///      unknown as "issuer" would drop the retirement obligation and let `verify-roles` pass
    ///      with a superseded bucket still live.
    function test_planMigration_unreadableIssuerMembership() public {
        bytes32 issuerRole = _pyusdx().ISSUER_ROLE();

        vm.mockCallRevert(
            _stack.pyusdxProxy,
            abi.encodeCall(IAccessControl.hasRole, (issuerRole, earnerManager)),
            "unreadable"
        );

        vm.expectRevert(
            abi.encodeWithSelector(UnreadableState.selector, "pyusdx.ISSUER_ROLE(outgoing holder)", _stack.pyusdxProxy)
        );
        _adminHolder.planMigration(_record(), _desiredConfig(), _migrationConfig(), address(_adminHolder));
    }

    /* ============ partial execution and resume ============ */

    function test_migrateRoles_earnerBucketPrecedesEarnerManagerSwitch() public {
        // The admin holder cannot set the new bucket, so the switch it does control must stay deferred.
        _runAs(_adminHolder, _desiredConfig());

        assertEq(_pyusdx().earnerManager(), earnerManager);

        _runAs(_rateHolder, _desiredConfig());

        (uint128 capacity, ) = IRateLimiter(_stack.pyusdxProxy).getRateLimitConfig(_newEarnerManager);
        assertEq(capacity, _EARNER_CAPACITY);

        _runAs(_adminHolder, _desiredConfig());

        assertEq(_pyusdx().earnerManager(), _newEarnerManager);
    }

    function test_migrateRoles_partialRunLeavesRemainingWorkOutstanding() public {
        _runAs(_adminHolder, _desiredConfig());

        assertGt(_outstanding(), 0);
        assertTrue(_hasRole(_stack.pyusdxProxy, _pyusdx().PAUSER_ROLE(), _newPauser));
        assertTrue(_hasRole(_stack.pyusdxProxy, 0x00, address(_adminHolder)));

        _migrateToCompletion();

        assertEq(_outstanding(), 0);
    }

    function test_migrateRoles_layerZeroDelegateRestoreDefersToNewOperator() public {
        _runAs(_adminHolder, _desiredConfig());

        assertEq(ILayerZeroEndpointV2(LZ_ENDPOINT).delegates(_stack.layerZeroBridgeAdapterProxy), address(0));
        assertGt(_outstanding(), 0);

        _runAs(_newLzOperator, _desiredConfig());

        assertEq(
            ILayerZeroEndpointV2(LZ_ENDPOINT).delegates(_stack.layerZeroBridgeAdapterProxy),
            address(_newLzOperator)
        );
    }

    function test_migrateRoles_layerZeroDelegateNotRestorableWhenOperatorUnchanged() public {
        // Desired operator == outgoing operator: a revoke would clear the delegate with nothing left
        // able to restore it, so the plan must refuse rather than emit an unexecutable call.
        Config.ProtocolConfig memory config = _desiredConfig();
        config.layerZeroBridgeAdapter.operator = address(_adminHolder);

        Config.MigrationConfig memory migration = _migrationConfig();

        MigrationAction[] memory actions = _adminHolder.planMigration(
            _record(),
            config,
            migration,
            address(_adminHolder)
        );

        // The operator is unchanged, so no revoke is emitted and therefore no `setDelegate` either:
        // one would be wiped by nothing and re-sent forever. Asserted on the call, not on the
        // unchanged delegate, which would also hold if the plan had merely deferred it.
        assertGt(actions.length, 0);
        assertFalse(
            _plansCall(
                actions,
                _stack.layerZeroBridgeAdapterProxy,
                abi.encodeCall(ILayerZeroBridgeAdapterLike.setDelegate, (address(_adminHolder)))
            )
        );
        assertEq(
            ILayerZeroEndpointV2(LZ_ENDPOINT).delegates(_stack.layerZeroBridgeAdapterProxy),
            address(_adminHolder)
        );
    }

    /* ============ batch semantics ============ */

    /// @dev Two current holders with different authority get different batches from the same plan.
    ///      That the direct and Safe entry points reduce one plan to the same calls is proved where
    ///      it is observable -- `MigrateRolesEntrypoints.t.sol` replays the exported Safe batch and
    ///      compares the resulting chain state against a direct run from the same pre-state.
    function test_stagedTransactions_differByExecutor() public view {
        Transaction[] memory byAdmin = _stagedFor(address(_adminHolder));
        Transaction[] memory byRateManager = _stagedFor(address(_rateHolder));

        assertGt(byAdmin.length, 0);
        assertGt(byRateManager.length, 0);
        assertTrue(byAdmin.length != byRateManager.length);

        // Neither holder is handed work the other must do: the admin never touches a bucket.
        assertFalse(_plansSameCall(byAdmin, _stack.pyusdxProxy, _retireBucketCall(earnerManager)));
        assertTrue(_plansSameCall(byRateManager, _stack.pyusdxProxy, _retireBucketCall(earnerManager)));
    }

    function test_parseMigrationConfig_readsTheExampleConfig() public view {
        Config.MigrationConfig memory migration = _adminHolder.parseMigrationConfig(
            vm.readFile(string.concat(vm.projectRoot(), "/deploymentConfigs/example-protocol.json"))
        );

        assertEq(migration.outgoingHolders.length, 2);
        assertTrue(migration.hasPortalOFTWrapper);
        assertEq(migration.portalOFTWrapper.admin, address(0x15));
        assertEq(migration.portalOFTWrapper.operator, address(0x16));
    }

    /// @dev The checked-in chain configs predate the migration block, so they still deploy but are
    ///      not migration-ready: the scripts must refuse them rather than migrating nothing away.
    function test_parseMigrationConfig_checkedInChainConfigHasNoMigrationBlock() public {
        Config.MigrationConfig memory migration = _adminHolder.parseMigrationConfig(
            vm.readFile(string.concat(vm.projectRoot(), "/deploymentConfigs/1/protocol.json"))
        );

        assertEq(migration.outgoingHolders.length, 0);
        assertFalse(migration.hasPortalOFTWrapper);

        vm.expectRevert(NoOutgoingHolders.selector);
        _adminHolder.planMigration(_record(), _desiredConfig(), migration, address(_adminHolder));
    }

    /// @dev The plan log prints "sendable now / deferred" as the two halves of the outstanding set,
    ///      so "sendable now" must be exactly the batch this executor will send. Regression for a
    ///      count that added in obligations the chain already carried, which reported a completed
    ///      rerun as a plan-sized batch on the line above "nothing broadcast".
    function test_planCounts_sendableNowIsTheBatchAndSumsToOutstanding() public {
        // One round in, so part of the plan is already carried by the chain and part is not.
        _runAs(_adminHolder, _desiredConfig());

        MigrationAction[] memory midRun = _adminHolder.planMigration(
            _record(),
            _desiredConfig(),
            _migrationConfig(),
            address(_rateHolder)
        );

        uint256 outstanding = _adminHolder.outstandingCount(midRun);
        uint256 deferred = _adminHolder.deferredCount(midRun);

        assertGt(outstanding, 0);
        assertGt(deferred, 0);

        // The obligations already carried are what the old count wrongly added to "sendable now".
        assertLt(outstanding, midRun.length);
        assertEq(outstanding - deferred, _adminHolder.stagedTransactions(midRun).length);

        _migrateToCompletion();

        MigrationAction[] memory complete = _adminHolder.planMigration(
            _record(),
            _desiredConfig(),
            _migrationConfig(),
            address(_adminHolder)
        );

        assertGt(complete.length, 0);
        assertEq(_adminHolder.outstandingCount(complete), 0);
        assertEq(_adminHolder.deferredCount(complete), 0);
        assertEq(_adminHolder.stagedTransactions(complete).length, 0);
    }

    function test_stagedTransactions_carryNoValue() public view {
        Transaction[] memory staged = _stagedFor(address(_adminHolder));

        for (uint256 i; i < staged.length; ++i) {
            assertEq(staged[i].value, 0);
        }
    }

    /* ============ helpers ============ */

    function _migrateToCompletion() internal {
        Config.ProtocolConfig memory config = _desiredConfig();

        _runAs(_adminHolder, config);
        _runAs(_rateHolder, config);
        _runAs(_newLzOperator, config);
        _runAs(_adminHolder, config);
    }

    function _runAs(MigrateRolesHarness holder, Config.ProtocolConfig memory config) internal {
        _runAs(holder, config, _migrationConfig());
    }

    function _runAs(
        MigrateRolesHarness holder,
        Config.ProtocolConfig memory config,
        Config.MigrationConfig memory migration
    ) internal {
        MigrationAction[] memory actions = holder.planMigration(_record(), config, migration, address(holder));

        holder.executeBatch(holder.stagedTransactions(actions));
    }

    /// @dev Whether the plan carries this exact call, regardless of who can send it.
    function _plansCall(
        MigrationAction[] memory actions,
        address target,
        bytes memory data
    ) internal pure returns (bool) {
        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].planned.transaction.target != target) continue;
            if (keccak256(actions[i].planned.transaction.data) != keccak256(data)) continue;

            return true;
        }

        return false;
    }

    function _plansSameCall(
        Transaction[] memory transactions,
        address target,
        bytes memory data
    ) internal pure returns (bool) {
        for (uint256 i; i < transactions.length; ++i) {
            if (transactions[i].target != target) continue;
            if (keccak256(transactions[i].data) != keccak256(data)) continue;

            return true;
        }

        return false;
    }

    function _plansAnyCallTo(MigrationAction[] memory actions, address target) internal pure returns (bool) {
        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].planned.transaction.target == target) return true;
        }

        return false;
    }

    function _retireBucketCall(address holder) internal pure returns (bytes memory) {
        return abi.encodeCall(IRateLimiter.setRateLimit, (holder, 0, 0, false));
    }

    function _outgoingHoldersPlus(address extra) internal view returns (address[] memory extended) {
        address[] memory outgoing = _migrationConfig().outgoingHolders;

        extended = new address[](outgoing.length + 1);

        for (uint256 i; i < outgoing.length; ++i) {
            extended[i] = outgoing[i];
        }

        extended[outgoing.length] = extra;
    }

    function _wrapperOperatorRole() internal view returns (bytes32) {
        return IPortalOFTWrapperLike(_wrapper).OPERATOR_ROLE();
    }

    function _stagedFor(address executor) internal view returns (Transaction[] memory) {
        return
            _adminHolder.stagedTransactions(
                _adminHolder.planMigration(_record(), _desiredConfig(), _migrationConfig(), executor)
            );
    }

    function _outstanding() internal view returns (uint256) {
        return
            _adminHolder.outstandingCount(
                _adminHolder.planMigration(_record(), _desiredConfig(), _migrationConfig(), address(0))
            );
    }

    function _record() internal view returns (ScriptBase.Deployments memory record) {
        record.pyusdx = _stack.pyusdxProxy;
        record.issuerGateway = _stack.issuerGatewayProxy;
        record.swapFacility = _stack.swapFacilityProxy;
        record.extensionFactory = _stack.factoryProxy;
        record.yieldToOneBeacon = _stack.yieldToOneBeaconProxy;
        record.multiMintBeacon = _stack.multiMintBeaconProxy;
        record.portal = _stack.portalProxy;
        record.layerZeroBridgeAdapter = _stack.layerZeroBridgeAdapterProxy;
        record.pyusdxPortalOFTWrapper = _wrapper;
        record.extensionNames = new string[](0);
        record.extensionAddresses = new address[](0);
    }

    function _migrationConfig() internal view returns (Config.MigrationConfig memory migration) {
        address[] memory outgoing = new address[](8);
        outgoing[0] = address(_adminHolder);
        outgoing[1] = address(_rateHolder);
        outgoing[2] = pauser;
        outgoing[3] = freezeManager;
        outgoing[4] = forcedTransferManager;
        outgoing[5] = earnerManager;
        outgoing[6] = operator;
        outgoing[7] = factoryManager;

        migration.outgoingHolders = outgoing;
        migration.hasPortalOFTWrapper = true;
        migration.portalOFTWrapper = Config.PortalOFTWrapperConfig({ admin: _newAdmin, operator: _newOperator });
    }

    function _desiredConfig() internal view returns (Config.ProtocolConfig memory config) {
        config.pyusdx = Config.PYUSDXConfig({
            name: "PayPal USD Yield",
            symbol: "PYUSDX",
            admin: _newAdmin,
            pauser: _newPauser,
            freezeManager: _newFreezeManager,
            forcedTransferManager: _newForcedTransferManager,
            earnerManager: _newEarnerManager,
            rateManager: _newRateManager,
            earnerManagerRateLimitCapacity: _EARNER_CAPACITY,
            earnerManagerRateLimitRefillPerSecond: _EARNER_REFILL
        });

        config.issuerGateway = Config.IssuerGatewayConfig({
            admin: _newAdmin,
            operator: _newOperator,
            executor: _newExecutor,
            mintDelay: MINT_DELAY,
            mintTTL: MINT_TTL,
            rateLimitCapacity: type(uint128).max,
            rateLimitRefillPerSecond: 0
        });

        config.swapFacility = Config.SwapFacilityConfig({ admin: _newAdmin, pauser: _newPauser });
        config.extensionFactory = Config.FactoryConfig({ admin: _newAdmin, factoryManager: _newFactoryManager });

        config.portal = Config.PortalConfig({
            admin: _newAdmin,
            pauser: _newPauser,
            operator: _newOperator,
            fallbackRecipient: _newFallbackRecipient,
            rateLimitCapacity: type(uint128).max,
            rateLimitRefillPerSecond: 0
        });

        config.layerZeroBridgeAdapter = Config.LayerZeroBridgeAdapterConfig({
            lzEndpoint: LZ_ENDPOINT,
            admin: _newAdmin,
            operator: address(_newLzOperator)
        });
    }

    function _outgoingPYUSDXConfig() internal view returns (Config.PYUSDXConfig memory) {
        return
            Config.PYUSDXConfig({
                name: "PayPal USD Yield",
                symbol: "PYUSDX",
                admin: address(_adminHolder),
                pauser: pauser,
                freezeManager: freezeManager,
                forcedTransferManager: forcedTransferManager,
                earnerManager: earnerManager,
                rateManager: address(_rateHolder),
                earnerManagerRateLimitCapacity: _EARNER_CAPACITY,
                earnerManagerRateLimitRefillPerSecond: _EARNER_REFILL
            });
    }

    function _outgoingIssuerGatewayConfig() internal view returns (Config.IssuerGatewayConfig memory) {
        return
            Config.IssuerGatewayConfig({
                admin: address(_adminHolder),
                operator: operator,
                executor: executor,
                mintDelay: MINT_DELAY,
                mintTTL: MINT_TTL,
                rateLimitCapacity: type(uint128).max,
                rateLimitRefillPerSecond: 0
            });
    }

    function _outgoingPortalConfig() internal view returns (Config.PortalConfig memory) {
        return
            Config.PortalConfig({
                admin: address(_adminHolder),
                pauser: pauser,
                operator: operator,
                fallbackRecipient: fallbackRecipient,
                rateLimitCapacity: type(uint128).max,
                rateLimitRefillPerSecond: 0
            });
    }

    function _hasRole(address target, bytes32 role, address account) internal view returns (bool) {
        return IAccessControl(target).hasRole(role, account);
    }

    function _proxyOwner(address proxy) internal view returns (address) {
        return _adminHolder.proxyAdminOwner(proxy);
    }

    function _pyusdx() internal view returns (IPYUSDXLike) {
        return IPYUSDXLike(_stack.pyusdxProxy);
    }

    function _portal() internal view returns (IPortalLike) {
        return IPortalLike(_stack.portalProxy);
    }

    function _gateway() internal view returns (IGatewayLike) {
        return IGatewayLike(_stack.issuerGatewayProxy);
    }
}

/// @dev Minimal read surfaces, to keep the test off the production contract types whose forge-std
///      version differs from the test tree's.
interface IPYUSDXLike {
    function ISSUER_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function FREEZE_MANAGER_ROLE() external view returns (bytes32);

    function FORCED_TRANSFER_MANAGER_ROLE() external view returns (bytes32);

    function RATE_LIMIT_MANAGER_ROLE() external view returns (bytes32);

    function earnerManager() external view returns (address);
}

interface IPortalLike {
    function fallbackRecipient() external view returns (address);
}

interface IGatewayLike {
    function OPERATOR_ROLE() external view returns (bytes32);
}

interface IPortalOFTWrapperLike {
    function OPERATOR_ROLE() external view returns (bytes32);

    function portal() external view returns (address);

    function layerZeroBridgeAdapter() external view returns (address);
}

interface ILayerZeroBridgeAdapterLike {
    function setDelegate(address delegate) external;
}
