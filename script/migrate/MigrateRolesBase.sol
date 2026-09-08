// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Ownable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import { IForcedTransferable } from "../../lib/evm-m-extensions/src/components/forcedTransferable/IForcedTransferable.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { IPausable } from "../../lib/evm-m-extensions/src/components/pausable/IPausable.sol";

import { Upgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { console } from "../../lib/forge-std/src/console.sol";

import { IRateLimiter } from "../../src/abstract/interfaces/IRateLimiter.sol";
import { IIssuerGateway } from "../../src/core/IIssuerGateway.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";
import { IExtensionBeacon } from "../../src/platform/interfaces/IExtensionBeacon.sol";
import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { IBridgeAdapter } from "../../src/portal/interfaces/IBridgeAdapter.sol";
import { IPortal } from "../../src/portal/interfaces/IPortal.sol";
import { ILayerZeroBridgeAdapter } from "../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroBridgeAdapter.sol";
import { ILayerZeroEndpointV2 } from "../../src/portal/bridgeAdapters/layerZero/interfaces/ILayerZeroEndpointV2.sol";
import { IPortalOFTWrapper } from "../../src/portal/oft/interfaces/IPortalOFTWrapper.sol";
import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

import { Config } from "../Config.sol";
import { ConfigurationPlan, PlannedAction } from "../libraries/ConfigurationPlan.sol";
import { StateReader } from "../libraries/StateReader.sol";
import { Transaction } from "../libraries/TransactionHelper.sol";
import { ScriptBase } from "../ScriptBase.s.sol";

/// @notice One outstanding migration obligation, plus what it takes to send it.
/// @dev    `planned.applied` is the executor-independent half — the chain already carries the
///         intended end state — which is what lets the verifier reuse this plan. `executable` is the
///         executor-dependent half, filled in by staging from the authority the executor holds *now*.
///         An obligation that is neither applied nor executable is deferred, never dropped.
struct MigrationAction {
    PlannedAction planned;
    /// @dev What the sender must hold on this call's own target: a role, `_OWNERSHIP` for a
    ///      ProxyAdmin transfer, `_NO_AUTHORITY` for a self-`renounceRole`, or `_NEXT_INVOCATION`
    ///      when an earlier step has to land first and the call therefore belongs to a later run.
    bytes32 requiredRole;
    /// @dev The role this call takes away, or `_NOTHING_REMOVED`. An authority is never removed
    ///      while earlier outstanding work on the same contract still needs it.
    bytes32 removesRole;
    bool executable;
}

/// @notice Thrown when a contract the migration must cover carries no address in the deployment record.
error MissingDeployment(string name);

/// @notice Thrown when a recorded address holds no code on the target chain.
error NotAContract(string name, address target);

/// @notice Thrown when the config names no outgoing holders.
/// @dev    `AccessControl` here is not enumerable and these scripts do not scan historical logs,
///         so the addresses being migrated away from must be supplied explicitly. An empty list
///         would silently migrate nothing away, which is the failure this refuses to ship.
error NoOutgoingHolders();

/// @notice Thrown when `migration.outgoingHolders` carries a zero address.
error ZeroOutgoingHolder(uint256 index);

/// @notice Thrown when a PortalOFTWrapper is deployed but the config names no holders for it.
error PortalOFTWrapperNotConfigured(address deployed);

/// @notice Thrown when the deployed suite is not wired the way the config describes.
error UnexpectedWiring(string what, address expected);

/// @notice Thrown when a getter the plan depends on could not be read at all.
error UnreadableState(string what, address target);

/// @notice Thrown when work remains but this executor may send none of it.
/// @dev    An executor holding no relevant authority would otherwise broadcast an empty batch and
///         look like a clean run, which is the one outcome a migration must never report.
error NothingExecutable(address executor, uint256 outstanding);

/// @notice Thrown by the verifier while any obligation is still outstanding.
error MigrationIncomplete(uint256 outstanding);

/// @title  MigrateRolesBase
/// @notice Builds the ordered set of calls that moves the deployed PYUSDX suite from its current role
///         holders to the ones named in `deploymentConfigs/<chainId>/protocol.json`, tagging each
///         with whether the chain already carries it and whether the given executor may send it now.
/// @dev    Shared by the broadcast script (`MigrateRoles`), the Safe propose script
///         (`ProposeMigrateRoles`) and the verifier (`VerifyRoles`), so all three read one plan.
///
///         Staging asks only what the executor holds on chain right now. Authority a batch grants
///         takes effect on the grantee's next invocation rather than being predicted mid-batch, which
///         is what makes the migration resumable: each current holder runs the target in turn until
///         the plan is empty.
///
///         Ordering is three named rules, not a scheduler:
///
///         1. A call that removes a role waits while any earlier outstanding call on the same
///            contract still needs that role. This is what keeps `DEFAULT_ADMIN_ROLE` until the work
///            it governs is done, and `RATE_LIMIT_MANAGER_ROLE` until the buckets are set.
///         2. `setEarnerManager` waits for the incoming manager's rate-limit bucket.
///         3. The LayerZero `setDelegate` follow-up waits for the operator revoke that clears it.
///
///         Two properties make the verifier sound: `planned.applied` never depends on the executor,
///         and a read that fails leaves the obligation outstanding, so unreadable state fails
///         verification rather than passing quietly. Granting a role is never a completed handover —
///         the superseded holder's revoke is its own obligation.
abstract contract MigrateRolesBase is ScriptBase {
    using ConfigurationPlan for PlannedAction[];
    using StateReader for address;

    /* ============ Constants ============ */

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    /// @dev Sender requirement: `Ownable.owner()` of the ProxyAdmin, not an AccessControl role.
    bytes32 internal constant _OWNERSHIP = keccak256("MigrateRoles.sender.ownership");

    /// @dev Sender requirement: none. A self-`renounceRole` is gated on being the account.
    bytes32 internal constant _NO_AUTHORITY = keccak256("MigrateRoles.sender.self");

    /// @dev Sender requirement: an earlier step has to land first, so this belongs to a later run.
    bytes32 internal constant _NEXT_INVOCATION = keccak256("MigrateRoles.sender.nextInvocation");

    /// @dev `removesRole` for a call that takes no authority away. Not `0x00`, which is a real role.
    bytes32 internal constant _NOTHING_REMOVED = keccak256("MigrateRoles.removes.nothing");

    /// @dev Upper bound on emitted actions: every role slot may need one grant plus one revoke per
    ///      outgoing holder, plus the singletons, buckets, delegate and ProxyAdmin transfers.
    ///      There are 23 role slots today (4 on PYUSDX, 2 on the IssuerGateway, 1 on the
    ///      SwapFacility, 3 across the factory and both beacons, 2 on the Portal, 1 on the adapter,
    ///      1 on the wrapper and 9 `DEFAULT_ADMIN_ROLE`s), so raise this when one is added. An
    ///      undersized array panics on the write rather than truncating.
    uint256 private constant _ROLE_SLOTS = 25;

    /// @dev The non-role actions: the earner bucket, `setEarnerManager`, `setFallbackRecipient`,
    ///      `setDelegate` and 9 ProxyAdmin transfers, plus headroom for one bucket retirement per
    ///      outgoing holder.
    uint256 private constant _EXTRA_ACTIONS = 24;

    /// @dev Accumulator threaded through the builders. A memory struct is passed by reference, so
    ///      `count` advances across helper calls without each one returning it.
    struct PlanBuilder {
        MigrationAction[] actions;
        uint256 count;
        address executor;
        address[] outgoing;
    }

    /* ============ Plan Construction ============ */

    /// @notice Builds every outstanding migration obligation, in the order it must be sent.
    /// @param  deployments The chain's deployment record.
    /// @param  config      The desired end state, from the chain's `protocol.json`.
    /// @param  migration   The migration-only blocks of the same file.
    /// @param  executor    The address that would send the batch — the signer for a direct run, the
    ///                     Safe for a proposal, and address(0) when only the obligations matter.
    /// @return actions     Every obligation, tagged applied / executable.
    function _planMigration(
        Deployments memory deployments,
        ProtocolConfig memory config,
        Config.MigrationConfig memory migration,
        address executor
    ) internal view returns (MigrationAction[] memory actions) {
        // Config first, then the record: a file with no `migration` block is the gap an operator
        // adopting this hits first, so report it before anything that depends on the chain.
        _revertIfInvalidMigration(migration);
        _revertIfInvalidRecord(deployments, migration);
        _revertIfUnexpectedWiring(deployments, config);

        PlanBuilder memory plan = PlanBuilder({
            actions: new MigrationAction[](_ROLE_SLOTS * (1 + migration.outgoingHolders.length) + _EXTRA_ACTIONS),
            count: 0,
            executor: executor,
            outgoing: migration.outgoingHolders
        });

        _planPYUSDX(plan, deployments, config);
        _planIssuerGateway(plan, deployments, config);
        _planSwapFacility(plan, deployments, config);
        _planFactoryAndBeacons(plan, deployments, config);
        _planPortal(plan, deployments, config);
        _planLayerZeroAdapter(plan, deployments, config);
        _planPortalOFTWrapper(plan, deployments, migration);
        _planProxyAdmins(plan, deployments, config, migration);
        _planAdminHandover(plan, deployments, config, migration);

        actions = plan.actions;

        // Truncate the over-allocated array to what was actually emitted.
        assembly {
            mstore(actions, mload(add(plan, 0x20)))
        }

        _stage(actions, executor);
    }

    /* ============ Preflight ============ */

    /// @dev Every core contract and both beacons must be recorded and carry code. A missing address
    ///      is a failure, never a silently skipped contract: skipping would let the run report a
    ///      complete handover for a suite it never touched.
    function _revertIfInvalidRecord(
        Deployments memory deployments,
        Config.MigrationConfig memory migration
    ) private view {
        _revertIfNotDeployed("pyusdx", deployments.pyusdx);
        _revertIfNotDeployed("issuerGateway", deployments.issuerGateway);
        _revertIfNotDeployed("swapFacility", deployments.swapFacility);
        _revertIfNotDeployed("extensionFactory", deployments.extensionFactory);
        _revertIfNotDeployed("yieldToOneBeacon", deployments.yieldToOneBeacon);
        _revertIfNotDeployed("multiMintBeacon", deployments.multiMintBeacon);
        _revertIfNotDeployed("portal", deployments.portal);
        _revertIfNotDeployed("layerZeroBridgeAdapter", deployments.layerZeroBridgeAdapter);

        // The wrapper is optional, but a deployed one with no target config is a config gap, not an
        // absent contract — say which, so the fix is obvious.
        if (deployments.pyusdxPortalOFTWrapper == address(0)) return;

        if (!migration.hasPortalOFTWrapper) revert PortalOFTWrapperNotConfigured(deployments.pyusdxPortalOFTWrapper);

        _revertIfNotDeployed("pyusdxPortalOFTWrapper", deployments.pyusdxPortalOFTWrapper);
    }

    function _revertIfNotDeployed(string memory name, address target) private view {
        if (target == address(0)) revert MissingDeployment(name);
        if (target.code.length == 0) revert NotAContract(name, target);
    }

    function _revertIfInvalidMigration(Config.MigrationConfig memory migration) private pure {
        if (migration.outgoingHolders.length == 0) revert NoOutgoingHolders();

        for (uint256 i; i < migration.outgoingHolders.length; ++i) {
            if (migration.outgoingHolders[i] == address(0)) revert ZeroOutgoingHolder(i);
        }
    }

    /// @dev Confirms the recorded addresses are the suite the config describes before any call is
    ///      built against them, and that the issuer wiring the migration must preserve is intact.
    function _revertIfUnexpectedWiring(Deployments memory deployments, ProtocolConfig memory config) private view {
        address pyusdx = deployments.pyusdx;

        _requireAddress("issuerGateway.pyusdx", deployments.issuerGateway, IIssuerGateway.pyusdx.selector, pyusdx);
        _requireAddress("swapFacility.pyusdx", deployments.swapFacility, ISwapFacility.pyusdx.selector, pyusdx);
        _requireAddress(
            "swapFacility.extensionFactory",
            deployments.swapFacility,
            ISwapFacility.extensionFactory.selector,
            deployments.extensionFactory
        );
        _requireAddress(
            "extensionFactory.pyusdx",
            deployments.extensionFactory,
            IExtensionFactory.pyusdx.selector,
            pyusdx
        );
        _requireAddress(
            "extensionFactory.yieldToOneBeacon",
            deployments.extensionFactory,
            IExtensionFactory.yieldToOneBeacon.selector,
            deployments.yieldToOneBeacon
        );
        _requireAddress(
            "extensionFactory.multiMintBeacon",
            deployments.extensionFactory,
            IExtensionFactory.multiMintBeacon.selector,
            deployments.multiMintBeacon
        );
        _requireAddress("portal.pyusdx", deployments.portal, IPortal.pyusdx.selector, pyusdx);
        _requireAddress(
            "layerZeroBridgeAdapter.portal",
            deployments.layerZeroBridgeAdapter,
            IBridgeAdapter.portal.selector,
            deployments.portal
        );
        _requireAddress(
            "layerZeroBridgeAdapter.endpoint",
            deployments.layerZeroBridgeAdapter,
            ILayerZeroBridgeAdapter.endpoint.selector,
            config.layerZeroBridgeAdapter.lzEndpoint
        );

        // ISSUER_ROLE is not represented in the config and must survive the migration untouched.
        bytes32 issuerRole = _roleHash(pyusdx, IPYUSDX.ISSUER_ROLE.selector);

        _requireRole("pyusdx.ISSUER_ROLE(issuerGateway)", pyusdx, issuerRole, deployments.issuerGateway);
        _requireRole("pyusdx.ISSUER_ROLE(portal)", pyusdx, issuerRole, deployments.portal);

        if (deployments.pyusdxPortalOFTWrapper == address(0)) return;

        _requireAddress(
            "pyusdxPortalOFTWrapper.portal",
            deployments.pyusdxPortalOFTWrapper,
            IPortalOFTWrapper.portal.selector,
            deployments.portal
        );
        _requireAddress(
            "pyusdxPortalOFTWrapper.layerZeroBridgeAdapter",
            deployments.pyusdxPortalOFTWrapper,
            IPortalOFTWrapper.layerZeroBridgeAdapter.selector,
            deployments.layerZeroBridgeAdapter
        );
    }

    function _requireAddress(string memory what, address target, bytes4 selector, address expected) private view {
        (bytes32 word, bool readable) = target.readWord(abi.encodeWithSelector(selector));

        if (!readable) revert UnreadableState(what, target);
        if (address(uint160(uint256(word))) != expected) revert UnexpectedWiring(what, expected);
    }

    function _requireRole(string memory what, address target, bytes32 role, address account) private view {
        (bool held, bool readable) = _hasRole(target, role, account);

        if (!readable) revert UnreadableState(what, target);
        if (!held) revert UnexpectedWiring(what, account);
    }

    /* ============ Per-Contract Plans ============ */

    /// @dev The order here is load-bearing. The incoming earner manager's bucket is provisioned before
    ///      the manager is switched, so it is never live without one; the superseded buckets are
    ///      retired before `RATE_LIMIT_MANAGER_ROLE` moves, because retiring one afterwards would need
    ///      an authority the outgoing holder no longer has. Both mirror the failure recorded in the
    ///      historical runbook, where a missing bucket left `distributeReward` reverting with
    ///      `RateLimitNotConfigured` after the handover had completed.
    function _planPYUSDX(
        PlanBuilder memory plan,
        Deployments memory deployments,
        ProtocolConfig memory config
    ) private view {
        address pyusdx = deployments.pyusdx;
        Config.PYUSDXConfig memory desired = config.pyusdx;

        bool bucketReady = _planEarnerBucket(plan, pyusdx, desired);

        _planEarnerManager(plan, pyusdx, desired.earnerManager, bucketReady);
        _planRetireSupersededBuckets(plan, pyusdx, desired.earnerManager);

        _planRoleFor(plan, pyusdx, IPausable.PAUSER_ROLE.selector, desired.pauser);
        _planRoleFor(plan, pyusdx, IFreezable.FREEZE_MANAGER_ROLE.selector, desired.freezeManager);
        _planRoleFor(
            plan,
            pyusdx,
            IForcedTransferable.FORCED_TRANSFER_MANAGER_ROLE.selector,
            desired.forcedTransferManager
        );
        _planRoleFor(plan, pyusdx, IRateLimiter.RATE_LIMIT_MANAGER_ROLE.selector, desired.rateManager);
    }

    /// @return applied Whether the incoming earner manager's bucket already matches the config.
    function _planEarnerBucket(
        PlanBuilder memory plan,
        address pyusdx,
        Config.PYUSDXConfig memory desired
    ) private view returns (bool applied) {
        (uint128 capacity, uint128 refill, bool readable) = _rateLimit(pyusdx, desired.earnerManager);

        applied =
            readable &&
            capacity == desired.earnerManagerRateLimitCapacity &&
            refill == desired.earnerManagerRateLimitRefillPerSecond;

        _push(
            plan,
            pyusdx,
            abi.encodeCall(
                IRateLimiter.setRateLimit,
                (
                    desired.earnerManager,
                    desired.earnerManagerRateLimitCapacity,
                    desired.earnerManagerRateLimitRefillPerSecond,
                    true
                )
            ),
            _describe(
                string.concat("pyusdx.setRateLimit(earnerManager ", vm.toString(desired.earnerManager), ")"),
                readable
            ),
            applied,
            _roleHash(pyusdx, IRateLimiter.RATE_LIMIT_MANAGER_ROLE.selector),
            _NOTHING_REMOVED
        );
    }

    /// @dev Ordering rule 2: until the incoming manager has a bucket, the switch belongs to a later
    ///      run — the rate-limit manager provisions the bucket, the admin then switches.
    function _planEarnerManager(
        PlanBuilder memory plan,
        address pyusdx,
        address desired,
        bool bucketReady
    ) private view {
        (bytes32 word, bool readable) = pyusdx.readWord(abi.encodeCall(IPYUSDX.earnerManager, ()));

        _push(
            plan,
            pyusdx,
            abi.encodeCall(IPYUSDX.setEarnerManager, (desired)),
            _describe(
                string.concat(
                    "pyusdx.setEarnerManager(",
                    vm.toString(desired),
                    bucketReady ? ")" : ") [waits for the incoming manager's bucket]"
                ),
                readable
            ),
            readable && address(uint160(uint256(word))) == desired,
            bucketReady ? _DEFAULT_ADMIN_ROLE : _NEXT_INVOCATION,
            _NOTHING_REMOVED
        );
    }

    /// @dev Only a superseded earner manager's bucket is retired. An outgoing holder that actually
    ///      holds `ISSUER_ROLE` keeps its bucket, because that bucket is what lets it mint and this
    ///      migration never touches `ISSUER_ROLE`. That covers the IssuerGateway and the Portal,
    ///      which always hold it, and any issuer granted after deployment. A membership that cannot
    ///      be read keeps the bucket too: deleting one is not reversible by this script.
    function _planRetireSupersededBuckets(
        PlanBuilder memory plan,
        address pyusdx,
        address desiredEarnerManager
    ) private view {
        bytes32 issuerRole = _roleHash(pyusdx, IPYUSDX.ISSUER_ROLE.selector);
        bytes32 rateLimitManagerRole = _roleHash(pyusdx, IRateLimiter.RATE_LIMIT_MANAGER_ROLE.selector);

        for (uint256 i; i < plan.outgoing.length; ++i) {
            address holder = plan.outgoing[i];

            if (holder == desiredEarnerManager) continue;
            if (_keepsIssuerBucket(pyusdx, issuerRole, holder)) continue;

            (uint128 capacity, uint128 refill, bool readable) = _rateLimit(pyusdx, holder);

            // Nothing to retire, and a completed rerun must not re-send a removal already carried.
            if (readable && capacity == 0 && refill == 0) continue;

            _push(
                plan,
                pyusdx,
                abi.encodeCall(IRateLimiter.setRateLimit, (holder, 0, 0, false)),
                _describe(string.concat("pyusdx.setRateLimit(retire ", vm.toString(holder), ")"), readable),
                false,
                rateLimitManagerRole,
                _NOTHING_REMOVED
            );
        }
    }

    /// @dev True when `holder` currently holds `ISSUER_ROLE`, so its bucket must survive.
    ///      An unreadable membership reverts rather than being guessed either way. Treating unknown
    ///      as "issuer" would omit the retirement obligation entirely, and `VerifyRoles` would then
    ///      pass with a superseded bucket still live; treating it as "not an issuer" could stop a
    ///      live issuer minting. Neither is recoverable from the plan, so the read has to succeed.
    function _keepsIssuerBucket(address pyusdx, bytes32 issuerRole, address holder) private view returns (bool) {
        (bool isIssuer, bool readable) = _hasRole(pyusdx, issuerRole, holder);

        if (!readable) revert UnreadableState("pyusdx.ISSUER_ROLE(outgoing holder)", pyusdx);

        return isIssuer;
    }

    function _planIssuerGateway(
        PlanBuilder memory plan,
        Deployments memory deployments,
        ProtocolConfig memory config
    ) private view {
        address gateway = deployments.issuerGateway;

        _planRoleFor(plan, gateway, IIssuerGateway.OPERATOR_ROLE.selector, config.issuerGateway.operator);
        _planRoleFor(plan, gateway, IIssuerGateway.EXECUTOR_ROLE.selector, config.issuerGateway.executor);
    }

    function _planSwapFacility(
        PlanBuilder memory plan,
        Deployments memory deployments,
        ProtocolConfig memory config
    ) private view {
        address swapFacility = deployments.swapFacility;

        _planRoleFor(plan, swapFacility, IPausable.PAUSER_ROLE.selector, config.swapFacility.pauser);
    }

    /// @dev Both beacons take their holders from the `extensionFactory` block, matching how
    ///      `DeployBase._deployBeacon` initialises them from the same `FactoryConfig`.
    function _planFactoryAndBeacons(
        PlanBuilder memory plan,
        Deployments memory deployments,
        ProtocolConfig memory config
    ) private view {
        address manager = config.extensionFactory.factoryManager;
        address factory = deployments.extensionFactory;

        _planRoleFor(plan, factory, IExtensionFactory.FACTORY_MANAGER_ROLE.selector, manager);
        _planRoleFor(plan, deployments.yieldToOneBeacon, IExtensionBeacon.BEACON_MANAGER_ROLE.selector, manager);
        _planRoleFor(plan, deployments.multiMintBeacon, IExtensionBeacon.BEACON_MANAGER_ROLE.selector, manager);
    }

    function _planPortal(
        PlanBuilder memory plan,
        Deployments memory deployments,
        ProtocolConfig memory config
    ) private view {
        address portal = deployments.portal;
        address recipient = config.portal.fallbackRecipient;

        (bytes32 word, bool readable) = portal.readWord(abi.encodeCall(IPortal.fallbackRecipient, ()));

        _push(
            plan,
            portal,
            abi.encodeCall(IPortal.setFallbackRecipient, (recipient)),
            _describe(string.concat("portal.setFallbackRecipient(", vm.toString(recipient), ")"), readable),
            readable && address(uint160(uint256(word))) == recipient,
            _DEFAULT_ADMIN_ROLE,
            _NOTHING_REMOVED
        );

        _planRoleFor(plan, portal, IPausable.PAUSER_ROLE.selector, config.portal.pauser);
        _planRoleFor(plan, portal, IPortal.OPERATOR_ROLE.selector, config.portal.operator);
    }

    /// @dev `LayerZeroBridgeAdapter._revokeRole` clears the endpoint delegate on every successful
    ///      `OPERATOR_ROLE` revocation, self-renounce included, and only an operator can restore it.
    ///      So the restore is emitted after the revokes and forced back into the plan whenever one is
    ///      pending, even when the delegate currently reads as the intended one — it will not survive.
    ///
    ///      Ordering rule 3: while a revoke is pending, the restore belongs to the incoming operator's
    ///      own run. Appending it to this batch would revert and take every preceding call with it.
    function _planLayerZeroAdapter(
        PlanBuilder memory plan,
        Deployments memory deployments,
        ProtocolConfig memory config
    ) private view {
        address adapter = deployments.layerZeroBridgeAdapter;
        address desiredOperator = config.layerZeroBridgeAdapter.operator;
        bytes32 operatorRole = _roleHash(adapter, IBridgeAdapter.OPERATOR_ROLE.selector);

        bool revokePending = _planRole(plan, adapter, operatorRole, desiredOperator);

        (bytes32 word, bool readable) = config.layerZeroBridgeAdapter.lzEndpoint.readWord(
            abi.encodeCall(ILayerZeroEndpointV2.delegates, (adapter))
        );

        if (!revokePending && readable && address(uint160(uint256(word))) == desiredOperator) return;

        _push(
            plan,
            adapter,
            abi.encodeCall(ILayerZeroBridgeAdapter.setDelegate, (desiredOperator)),
            _describe(
                string.concat(
                    "adapter.setDelegate(",
                    vm.toString(desiredOperator),
                    revokePending ? ") [re-asserted: the operator revoke clears it]" : ")"
                ),
                readable
            ),
            false,
            revokePending ? _NEXT_INVOCATION : operatorRole,
            _NOTHING_REMOVED
        );
    }

    function _planPortalOFTWrapper(
        PlanBuilder memory plan,
        Deployments memory deployments,
        Config.MigrationConfig memory migration
    ) private view {
        address wrapper = deployments.pyusdxPortalOFTWrapper;

        if (wrapper == address(0)) return;

        _planRoleFor(plan, wrapper, IPortalOFTWrapper.OPERATOR_ROLE.selector, migration.portalOFTWrapper.operator);
    }

    /// @dev Upgrade authority follows the same `admin` field that seeded it at deploy time: every
    ///      `_deployCreate3TransparentProxy` call in `DeployBase` passes that component's configured
    ///      admin as the proxy's initial owner, and both beacons take the factory's.
    function _planProxyAdmins(
        PlanBuilder memory plan,
        Deployments memory deployments,
        ProtocolConfig memory config,
        Config.MigrationConfig memory migration
    ) private view {
        _planProxyAdmin(plan, deployments.pyusdx, config.pyusdx.admin);
        _planProxyAdmin(plan, deployments.issuerGateway, config.issuerGateway.admin);
        _planProxyAdmin(plan, deployments.swapFacility, config.swapFacility.admin);
        _planProxyAdmin(plan, deployments.extensionFactory, config.extensionFactory.admin);
        _planProxyAdmin(plan, deployments.yieldToOneBeacon, config.extensionFactory.admin);
        _planProxyAdmin(plan, deployments.multiMintBeacon, config.extensionFactory.admin);
        _planProxyAdmin(plan, deployments.portal, config.portal.admin);
        _planProxyAdmin(plan, deployments.layerZeroBridgeAdapter, config.layerZeroBridgeAdapter.admin);

        if (deployments.pyusdxPortalOFTWrapper == address(0)) return;

        _planProxyAdmin(plan, deployments.pyusdxPortalOFTWrapper, migration.portalOFTWrapper.admin);
    }

    /// @dev OpenZeppelin's `ProxyAdmin` is `Ownable`, so upgrade authority moves in a single step and
    ///      there is no acceptance to wait for.
    function _planProxyAdmin(PlanBuilder memory plan, address proxy, address desired) private view {
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        (bytes32 word, bool readable) = proxyAdmin.readWord(abi.encodeCall(Ownable.owner, ()));

        _push(
            plan,
            proxyAdmin,
            abi.encodeCall(Ownable.transferOwnership, (desired)),
            _describe(
                string.concat("proxyAdmin(", vm.toString(proxy), ").transferOwnership(", vm.toString(desired), ")"),
                readable
            ),
            readable && address(uint160(uint256(word))) == desired,
            _OWNERSHIP,
            _OWNERSHIP
        );
    }

    /// @dev `DEFAULT_ADMIN_ROLE` is planned last so that, by ordering rule 1, its revoke waits for
    ///      every admin-gated obligation on the same contract. Dropping it earlier would strand that
    ///      work with no authority able to send it.
    function _planAdminHandover(
        PlanBuilder memory plan,
        Deployments memory deployments,
        ProtocolConfig memory config,
        Config.MigrationConfig memory migration
    ) private view {
        _planRole(plan, deployments.pyusdx, _DEFAULT_ADMIN_ROLE, config.pyusdx.admin);
        _planRole(plan, deployments.issuerGateway, _DEFAULT_ADMIN_ROLE, config.issuerGateway.admin);
        _planRole(plan, deployments.swapFacility, _DEFAULT_ADMIN_ROLE, config.swapFacility.admin);
        _planRole(plan, deployments.extensionFactory, _DEFAULT_ADMIN_ROLE, config.extensionFactory.admin);
        _planRole(plan, deployments.yieldToOneBeacon, _DEFAULT_ADMIN_ROLE, config.extensionFactory.admin);
        _planRole(plan, deployments.multiMintBeacon, _DEFAULT_ADMIN_ROLE, config.extensionFactory.admin);
        _planRole(plan, deployments.portal, _DEFAULT_ADMIN_ROLE, config.portal.admin);
        _planRole(plan, deployments.layerZeroBridgeAdapter, _DEFAULT_ADMIN_ROLE, config.layerZeroBridgeAdapter.admin);

        if (deployments.pyusdxPortalOFTWrapper == address(0)) return;

        _planRole(plan, deployments.pyusdxPortalOFTWrapper, _DEFAULT_ADMIN_ROLE, migration.portalOFTWrapper.admin);
    }

    /* ============ Role Planning ============ */

    /// @dev Grants the role to its intended holder, then removes it from every configured outgoing
    ///      holder that is not that holder. An outgoing address that is also the intended holder for
    ///      this role keeps it — the config, not the outgoing list, decides who ends up holding what.
    /// @return revokePending Whether any revoke was emitted for this role.
    function _planRole(
        PlanBuilder memory plan,
        address target,
        bytes32 role,
        address desired
    ) private view returns (bool revokePending) {
        (bool desiredHolds, bool readable) = _hasRole(target, role, desired);

        _push(
            plan,
            target,
            abi.encodeCall(IAccessControl.grantRole, (role, desired)),
            _describe(
                string.concat("grantRole(", _roleLabel(role), ", ", vm.toString(desired), ") on ", vm.toString(target)),
                readable
            ),
            readable && desiredHolds,
            _DEFAULT_ADMIN_ROLE,
            _NOTHING_REMOVED
        );

        for (uint256 i; i < plan.outgoing.length; ++i) {
            address holder = plan.outgoing[i];

            if (holder == desired) continue;

            (bool holds, bool holderReadable) = _hasRole(target, role, holder);

            if (holderReadable && !holds) continue;

            _pushRevoke(plan, target, role, holder);

            revokePending = true;
        }
    }

    /// @dev Plans a role named by its getter on the contract that owns it. Every non-admin role is
    ///      reached this way, so the hash is always the one that contract actually checks.
    function _planRoleFor(
        PlanBuilder memory plan,
        address target,
        bytes4 roleSelector,
        address desired
    ) private view returns (bool) {
        return _planRole(plan, target, _roleHash(target, roleSelector), desired);
    }

    /// @dev A holder revoking itself must use `renounceRole`: OpenZeppelin rejects renouncing on
    ///      another account's behalf, and `revokeRole` would demand a `DEFAULT_ADMIN_ROLE` this
    ///      holder may not have. That is what lets a non-admin outgoing holder retire its own role.
    function _pushRevoke(PlanBuilder memory plan, address target, bytes32 role, address holder) private pure {
        bool isSelf = holder == plan.executor && holder != address(0);

        _push(
            plan,
            target,
            isSelf
                ? abi.encodeCall(IAccessControl.renounceRole, (role, holder))
                : abi.encodeCall(IAccessControl.revokeRole, (role, holder)),
            string.concat(
                isSelf ? "renounceRole(" : "revokeRole(",
                _roleLabel(role),
                ", ",
                vm.toString(holder),
                ") on ",
                vm.toString(target)
            ),
            false,
            isSelf ? _NO_AUTHORITY : _DEFAULT_ADMIN_ROLE,
            role
        );
    }

    function _push(
        PlanBuilder memory plan,
        address target,
        bytes memory data,
        string memory description,
        bool applied,
        bytes32 requiredRole,
        bytes32 removesRole
    ) private pure {
        // Assigned field by field rather than through a struct literal: the literal builds the whole
        // nested value on the stack, which this many parameters cannot afford. `value` is already
        // zero — every migration call is value-free — and `TransactionHelper.propose` rejects any
        // that is not, so a Safe batch cannot silently carry one.
        plan.actions[plan.count].planned.transaction.target = target;
        plan.actions[plan.count].planned.transaction.data = data;
        plan.actions[plan.count].planned.description = description;
        plan.actions[plan.count].planned.applied = applied;
        plan.actions[plan.count].requiredRole = requiredRole;
        plan.actions[plan.count].removesRole = removesRole;

        plan.count = plan.count + 1;
    }

    /* ============ Staging ============ */

    /// @dev Marks the obligations this executor may send now. Authority is read from the chain as it
    ///      stands: a role this batch grants is simply usable on the grantee's next invocation, which
    ///      is what makes the migration resumable without predicting mid-batch state.
    function _stage(MigrationAction[] memory actions, address executor) private view {
        if (executor == address(0)) return;

        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].planned.applied) continue;
            if (!_senderRequirementMet(actions[i], executor)) continue;
            if (!_removalIsSafe(actions, i)) continue;

            actions[i].executable = true;
        }
    }

    function _senderRequirementMet(MigrationAction memory action, address executor) private view returns (bool) {
        bytes32 required = action.requiredRole;

        if (required == _NEXT_INVOCATION) return false;
        if (required == _NO_AUTHORITY) return true;

        address target = action.planned.transaction.target;

        if (required == _OWNERSHIP) {
            (bytes32 word, bool readable) = target.readWord(abi.encodeCall(Ownable.owner, ()));

            return readable && address(uint160(uint256(word))) == executor;
        }

        (bool held, bool readable) = _hasRole(target, required, executor);

        return readable && held;
    }

    /// @dev Ordering rule 1: an authority is never removed while earlier outstanding work on the same
    ///      contract still needs it and this run is not about to do that work either. This defers the
    ///      final `DEFAULT_ADMIN_ROLE` revoke behind the calls it governs, and the
    ///      `RATE_LIMIT_MANAGER_ROLE` revoke behind the bucket work.
    function _removalIsSafe(MigrationAction[] memory actions, uint256 index) private pure returns (bool) {
        bytes32 removed = actions[index].removesRole;

        if (removed == _NOTHING_REMOVED) return true;

        address target = actions[index].planned.transaction.target;

        for (uint256 i; i < index; ++i) {
            if (actions[i].planned.transaction.target != target) continue;
            if (actions[i].requiredRole != removed) continue;
            if (actions[i].planned.applied || actions[i].executable) continue;

            return false;
        }

        return true;
    }

    /* ============ Plan Views ============ */

    /// @notice The obligations the chain does not yet carry, regardless of who would send them.
    function _outstandingCount(MigrationAction[] memory actions) internal pure returns (uint256 count) {
        for (uint256 i; i < actions.length; ++i) {
            if (!actions[i].planned.applied) ++count;
        }
    }

    /// @notice The outstanding obligations this executor cannot send yet.
    function _deferredCount(MigrationAction[] memory actions) internal pure returns (uint256 count) {
        for (uint256 i; i < actions.length; ++i) {
            if (!actions[i].planned.applied && !actions[i].executable) ++count;
        }
    }

    /// @notice The batch this executor can send now, in order.
    /// @dev    Compacted through `ConfigurationPlan`, so the direct and Safe paths reduce the same
    ///         plan to the same transactions for the same executor.
    function _stagedTransactions(MigrationAction[] memory actions) internal pure returns (Transaction[] memory) {
        PlannedAction[] memory staged = new PlannedAction[](actions.length);

        for (uint256 i; i < actions.length; ++i) {
            staged[i] = actions[i].planned;
            staged[i].applied = actions[i].planned.applied || !actions[i].executable;
        }

        return staged.compact();
    }

    /// @notice Prints the obligations, then what this executor can send and what waits for someone else.
    function _logPlan(MigrationAction[] memory actions, string memory title) internal pure {
        PlannedAction[] memory obligations = new PlannedAction[](actions.length);

        for (uint256 i; i < actions.length; ++i) {
            obligations[i] = actions[i].planned;
        }

        obligations.log(title);

        uint256 deferred = _deferredCount(actions);

        // Both halves of the outstanding set, so the pair sums to what still needs doing and a
        // completed rerun reports `0 / 0` rather than counting obligations the chain already carries.
        console.log(
            "  sendable now / deferred to another current holder:",
            _outstandingCount(actions) - deferred,
            deferred
        );

        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].planned.applied || actions[i].executable) continue;

            console.log(
                string.concat("  [defer] ", actions[i].planned.description, " -- needs ", _senderLabel(actions[i]))
            );
        }
    }

    /* ============ Reads ============ */

    function _hasRole(address target, bytes32 role, address account) private view returns (bool held, bool readable) {
        bytes32 word;
        (word, readable) = target.readWord(abi.encodeCall(IAccessControl.hasRole, (role, account)));

        return (word != bytes32(0), readable);
    }

    /// @dev Two packed words, which `StateReader.readWord` rejects by design, so this reads directly.
    function _rateLimit(
        address token,
        address account
    ) private view returns (uint128 capacity, uint128 refillPerSecond, bool readable) {
        (bool success, bytes memory returnData) = token.staticcall(
            abi.encodeCall(IRateLimiter.getRateLimitConfig, (account))
        );

        if (!success || returnData.length != 64) return (0, 0, false);

        (capacity, refillPerSecond) = abi.decode(returnData, (uint128, uint128));

        return (capacity, refillPerSecond, true);
    }

    /// @dev Role hashes come from the contract rather than a local `keccak256`, so a renamed or
    ///      re-derived role fails loudly here instead of granting a hash nothing checks.
    function _roleHash(address target, bytes4 selector) private view returns (bytes32) {
        (bytes32 word, bool readable) = target.readWord(abi.encodeWithSelector(selector));

        if (!readable) revert UnreadableState("role getter", target);

        return word;
    }

    /* ============ Config ============ */

    /// @dev The migration-only blocks. Read separately from `_parseProtocolConfig` so a config that
    ///      predates them still deploys, and so `DeployAll` never depends on them.
    function _parseMigrationConfig(string memory json) internal view returns (Config.MigrationConfig memory migration) {
        migration.outgoingHolders = vm.keyExistsJson(json, ".migration.outgoingHolders")
            ? vm.parseJsonAddressArray(json, ".migration.outgoingHolders")
            : new address[](0);

        if (!vm.keyExistsJson(json, ".portalOFTWrapper")) return migration;

        migration.hasPortalOFTWrapper = true;
        migration.portalOFTWrapper = PortalOFTWrapperConfig({
            admin: vm.parseJsonAddress(json, ".portalOFTWrapper.admin"),
            operator: vm.parseJsonAddress(json, ".portalOFTWrapper.operator")
        });

        require(migration.portalOFTWrapper.admin != address(0), "zero portalOFTWrapper.admin");
        require(migration.portalOFTWrapper.operator != address(0), "zero portalOFTWrapper.operator");
    }

    /* ============ Labels ============ */

    /// @dev Marks a description whose current on-chain value could not be read. Such an action stays
    ///      outstanding, so unreadable state fails verification rather than passing quietly.
    function _describe(string memory description, bool readable) private pure returns (string memory) {
        return readable ? description : string.concat(description, " [current state unreadable]");
    }

    function _roleLabel(bytes32 role) private pure returns (string memory) {
        return role == _DEFAULT_ADMIN_ROLE ? "DEFAULT_ADMIN_ROLE" : vm.toString(role);
    }

    function _senderLabel(MigrationAction memory action) private pure returns (string memory) {
        if (action.requiredRole == _NEXT_INVOCATION) return "an earlier step to land first";
        if (action.requiredRole == _NO_AUTHORITY) return "the outgoing holder itself";

        address target = action.planned.transaction.target;

        if (action.requiredRole == _OWNERSHIP) return string.concat("owner() of ", vm.toString(target));

        return string.concat(_roleLabel(action.requiredRole), " on ", vm.toString(target));
    }
}
