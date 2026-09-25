// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;
/* solhint-disable quotes */

import { PausableUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { MigrateExtensionRoles } from "../../script/migrate/MigrateExtensionRoles.s.sol";
import { ScriptBase } from "../../script/ScriptBase.s.sol";
import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { IYieldToOne } from "../../src/platform/projects/interfaces/IYieldToOne.sol";
import { IMultiMint } from "../../src/platform/projects/interfaces/IMultiMint.sol";
import { IPausable } from "../../lib/evm-m-extensions/src/components/pausable/IPausable.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

contract ExtensionMigrationHarness is MigrateExtensionRoles {
    string private _name;
    string private _json;
    Deployments private _record;
    uint256 private _key;

    function inputs(string memory name, string memory json, Deployments memory record) external {
        _name = name;
        _json = json;
        _record = record;
    }

    function signer(uint256 key) external {
        _key = key;
    }
    function _readInputs() internal view override returns (string memory, string memory, Deployments memory) {
        return (_name, _json, _record);
    }
    function _signerPrivateKey() internal view override returns (uint256) {
        return _key;
    }
}

contract ExtensionMigrationTests is IntegrationForkTest {
    ExtensionMigrationHarness private _migration;
    address private _old;
    uint256 private _oldKey;
    address private _next;
    uint256 private _nextKey;
    address private _recipient = makeAddr("newRecipient");
    address private _extension;
    bool private _multi;
    string private constant _NAME = "Migration USD";

    function setUp() public override {
        super.setUp();
        (_old, _oldKey) = makeAddrAndKey("migrationOld");
        (_next, _nextKey) = makeAddrAndKey("migrationNext");
        _migration = new ExtensionMigrationHarness();
    }

    function test_outgoingListMustStillBeExplicit() public {
        _deploy(true);
        _inputs(vm.replace(_json(), "outgoingHolders", "omittedOutgoingHolders"));
        vm.expectRevert(
            bytes('vm.parseJsonAddressArray: path ".migration.outgoingHolders" must return exactly one JSON value')
        );
        _migration.run();
    }

    function test_emptyOutgoingListRetainsEveryDeployerRole() public {
        _deploy(true);
        _inputs(vm.replace(_json(), string.concat('["', vm.toString(_old), '"]'), "[]"));
        _migration.run();
        _migration.verify();
        bytes32[6] memory roles = [
            bytes32(0),
            IYieldToOne(_extension).YIELD_RECIPIENT_MANAGER_ROLE(),
            IFreezable(_extension).FREEZE_MANAGER_ROLE(),
            IPausable(_extension).PAUSER_ROLE(),
            IExtension(_extension).VERSION_MANAGER_ROLE(),
            IMultiMint(_extension).ASSET_CAP_MANAGER_ROLE()
        ];
        for (uint256 i; i < roles.length; ++i) {
            assertTrue(IAccessControl(_extension).hasRole(roles[i], _old), "deployer must retain every role");
            assertTrue(IAccessControl(_extension).hasRole(roles[i], _next), "incoming holder must receive every role");
        }
        assertEq(IYieldToOne(_extension).yieldRecipient(), _recipient);
        vm.recordLogs();
        _migration.run();
        assertEq(vm.getRecordedLogs().length, 0, "rerun must do nothing");
    }

    function test_singleSignerMigratesMultiMint() public {
        _deploy(true);
        _complete();
    }
    function test_singleSignerMigratesYieldToOne() public {
        _deploy(false);
        _complete();
    }

    function test_missingAuthoritySkipsWithoutSelfRenouncing() public {
        _deploy(true);
        bytes32 pauserRole = IPausable(_extension).PAUSER_ROLE();
        vm.prank(_old);
        IAccessControl(_extension).grantRole(pauserRole, _next);
        _migration.signer(_nextKey);
        _migration.run();
        assertTrue(IAccessControl(_extension).hasRole(0, _old));
        assertTrue(IAccessControl(_extension).hasRole(pauserRole, _old));
        vm.expectPartialRevert(MigrateExtensionRoles.MigrationIncomplete.selector);
        _migration.verify();
    }

    function test_splitAuthorityCanFinishOnLaterRun() public {
        _deploy(false);
        bytes32 role = IYieldToOne(_extension).YIELD_RECIPIENT_MANAGER_ROLE();
        vm.prank(_old);
        IAccessControl(_extension).revokeRole(role, _old);
        _migration.run(); // Admin can grant replacements, but cannot change the yield recipient.
        assertTrue(IAccessControl(_extension).hasRole(0, _old));
        assertTrue(IAccessControl(_extension).hasRole(0, _next));
        assertEq(IYieldToOne(_extension).yieldRecipient(), _old);
        _migration.signer(_nextKey);
        _migration.run();
        _migration.verify();
        assertFalse(IAccessControl(_extension).hasRole(0, _old));
    }

    function test_multipleAdminsRemovedBeforeExecutingAdmin() public {
        _deploy(true);
        address other = makeAddr("secondAdmin");
        vm.prank(_old);
        IAccessControl(_extension).grantRole(0, other);
        _inputs(
            vm.replace(
                _json(),
                string.concat('["', vm.toString(_old), '"]'),
                string.concat('["', vm.toString(_old), '","', vm.toString(other), '"]')
            )
        );
        _complete();
        assertFalse(IAccessControl(_extension).hasRole(0, other));
    }

    /// @notice Regression: the executing admin leaves last through `renounceRole`, as the suite
    ///         migration does, rather than revoking itself through its own admin authority.
    function test_executingAdminRenouncesLast() public {
        _deploy(false);
        vm.expectCall(_extension, abi.encodeCall(IAccessControl.renounceRole, (bytes32(0), _old)), 1);
        vm.expectCall(_extension, abi.encodeCall(IAccessControl.revokeRole, (bytes32(0), _old)), 0);
        _complete();
    }

    /// @notice Regression: a signer without admin authority skips another outgoing holder it cannot
    ///         revoke, and still retires its own role once the incoming holder has it.
    function test_nonAdminSignerRenouncesAfterOtherOutgoingHolder() public {
        (address holder, bytes32 pauserRole) = _nonAdminPauser(true, true);
        _inputs(_withOutgoing(string.concat('["', vm.toString(_old), '","', vm.toString(holder), '"]')));
        _migration.run();
        assertFalse(IAccessControl(_extension).hasRole(pauserRole, holder), "signer must renounce its own role");
        assertTrue(IAccessControl(_extension).hasRole(pauserRole, _old), "unauthorized revoke must be skipped");
        assertTrue(IAccessControl(_extension).hasRole(pauserRole, _next));
    }

    /// @notice A non-admin signer cannot grant its replacement, so it keeps its role until the
    ///         incoming holder has been granted it.
    function test_nonAdminSignerRetainsRoleWithoutIncomingHolder() public {
        (address holder, bytes32 pauserRole) = _nonAdminPauser(false, true);
        _inputs(_withOutgoing(string.concat('["', vm.toString(holder), '"]')));
        _migration.run();
        assertTrue(IAccessControl(_extension).hasRole(pauserRole, holder), "signer must keep an unreplaced role");
        assertFalse(IAccessControl(_extension).hasRole(pauserRole, _next));
    }

    /// @notice No role is removed while the yield recipient still has to change.
    function test_nonAdminSignerRetainsRoleWhileYieldRecipientPending() public {
        (address holder, bytes32 pauserRole) = _nonAdminPauser(true, false);
        _inputs(_withOutgoing(string.concat('["', vm.toString(holder), '"]')));
        _migration.run();
        assertTrue(IAccessControl(_extension).hasRole(pauserRole, holder), "signer must wait for the yield recipient");
        assertEq(IYieldToOne(_extension).yieldRecipient(), _old);
    }

    function test_holderStillDesiredKeepsRole() public {
        _deploy(true);
        _inputs(
            vm.replace(
                _json(),
                string.concat('"pauser":"', vm.toString(_next)),
                string.concat('"pauser":"', vm.toString(_old))
            )
        );
        _migration.run();
        _migration.verify();
        assertTrue(IAccessControl(_extension).hasRole(IPausable(_extension).PAUSER_ROLE(), _old));
        assertFalse(IAccessControl(_extension).hasRole(0, _old));
    }

    function test_grantMustActuallyTakeEffectBeforeRevocation() public {
        _deploy(false);
        vm.mockCall(_extension, abi.encodeCall(IAccessControl.grantRole, (bytes32(0), _next)), abi.encode(false));
        vm.expectPartialRevert(MigrateExtensionRoles.MissingRole.selector);
        _migration.run();
        vm.stopBroadcast();
        assertTrue(IAccessControl(_extension).hasRole(0, _old));
    }

    function test_revertingGrantIsNotSkipped() public {
        _deploy(true);
        vm.mockCallRevert(_extension, abi.encodeCall(IAccessControl.grantRole, (bytes32(0), _next)), "grant failed");
        vm.expectRevert(bytes("grant failed"));
        _migration.run();
        vm.stopBroadcast();
        assertTrue(IAccessControl(_extension).hasRole(0, _old));
    }

    function test_verifierRejectsIncompleteOrUnreadableState() public {
        _deploy(false);
        vm.expectPartialRevert(MigrateExtensionRoles.MigrationIncomplete.selector);
        _migration.verify();
        _complete();
        vm.mockCallRevert(_extension, abi.encodeWithSelector(IAccessControl.hasRole.selector), "unreadable");
        vm.expectRevert(bytes("unreadable"));
        _migration.verify();
    }

    function test_preservesPauseFreezeVersionAndCollateral() public {
        _deploy(true);
        address frozen = makeAddr("frozenAccount");
        vm.startPrank(_old);
        IPausable(_extension).pause();
        IFreezable(_extension).freeze(frozen);
        IExtension(_extension).pinVersion(1);
        IMultiMint(_extension).setAssetCap(address(USDC), 1_000_000);
        vm.stopPrank();
        address implementation = IExtension(_extension).pinnedImplementation();
        _complete();
        assertTrue(PausableUpgradeable(_extension).paused());
        assertTrue(IFreezable(_extension).isFrozen(frozen));
        assertEq(IExtension(_extension).pinnedImplementation(), implementation);
        assertEq(IMultiMint(_extension).assetCap(address(USDC)), 1_000_000);
    }

    function test_staleDeploymentCollateralDoesNotBlockMigration() public {
        _deploy(true);
        _inputs(
            vm.replace(
                _json(),
                '"roles":',
                '"assets":[{"address":"0x0000000000000000000000000000000000000000","cap":0}],"roles":'
            )
        );
        _complete();
    }

    function test_rejectsWrongIdentityChainAndZeroHolders() public {
        _deploy(true);
        _inputs(vm.replace(_json(), '"tokenName":"Migration USD"', '"tokenName":"Wrong Name"'));
        vm.expectRevert(bytes("config tokenName must equal extensionName"));
        _migration.run();
        _inputs(vm.replace(_json(), string.concat('"chainId":', vm.toString(block.chainid)), '"chainId":9999'));
        vm.expectRevert(bytes("config chainId mismatch"));
        _migration.run();
        _inputs(vm.replace(_json(), vm.toString(_next), vm.toString(address(0))));
        vm.expectRevert(bytes("zero incoming holder"));
        _migration.run();
        _inputs(vm.replace(_json(), vm.toString(_old), vm.toString(address(0))));
        vm.expectRevert(bytes("zero outgoing holder"));
        _migration.run();
        assertTrue(IAccessControl(_extension).hasRole(0, _old));
    }

    function test_rejectsMissingDuplicateOrWrongWiringRecord() public {
        _deploy(false);
        ScriptBase.Deployments memory record = _record();
        record.extensionAddresses[0] = address(0);
        _migration.inputs(_NAME, _json(), record);
        vm.expectRevert(bytes("extension not deployed"));
        _migration.run();
        record = _record();
        record.extensionNames = new string[](2);
        record.extensionAddresses = new address[](2);
        record.extensionNames[0] = _NAME;
        record.extensionNames[1] = _NAME;
        record.extensionAddresses[0] = _extension;
        record.extensionAddresses[1] = _extension;
        _migration.inputs(_NAME, _json(), record);
        vm.expectRevert(bytes("ambiguous extension record"));
        _migration.run();
        record = _record();
        record.pyusdx = address(swapFacility);
        _migration.inputs(_NAME, _json(), record);
        vm.expectRevert(bytes("extension wiring mismatch"));
        _migration.run();
    }

    function test_rejectsUnregisteredOrWrongTypeExtension() public {
        _deploy(false);
        _inputs(
            vm.replace(_json(), '"roles":{', string.concat('"roles":{"assetCapManager":"', vm.toString(_next), '",'))
        );
        vm.expectRevert(bytes("config extension type mismatch"));
        _migration.run();
        _inputs(_json());
        vm.mockCall(
            address(factory),
            abi.encodeCall(IExtensionFactory.getExtensionType, (_extension)),
            abi.encode(IExtensionFactory.ExtensionType.NONE)
        );
        vm.expectRevert(bytes("extension not registered"));
        _migration.run();
    }

    /// @dev A signer holding only the pauser role; `_old` keeps every role, including admin.
    function _nonAdminPauser(bool incomingGranted, bool recipientSet) private returns (address holder, bytes32 role) {
        _deploy(false);
        uint256 key;
        (holder, key) = makeAddrAndKey("nonAdminPauser");
        role = IPausable(_extension).PAUSER_ROLE();
        vm.startPrank(_old);

        IAccessControl(_extension).grantRole(role, holder);
        if (incomingGranted) IAccessControl(_extension).grantRole(role, _next);
        if (recipientSet) IYieldToOne(_extension).setYieldRecipient(_recipient);

        vm.stopPrank();
        _migration.signer(key);
    }

    function _withOutgoing(string memory outgoing) private view returns (string memory) {
        return vm.replace(_json(), string.concat('["', vm.toString(_old), '"]'), outgoing);
    }

    function _inputs(string memory json) private {
        _migration.inputs(_NAME, json, _record());
    }

    function _complete() private {
        _migration.run();
        assertTrue(IAccessControl(_extension).hasRole(0, _next), "replacement admin must be granted");
        assertFalse(IAccessControl(_extension).hasRole(0, _old), "old admin must be removed");
        assertEq(IYieldToOne(_extension).yieldRecipient(), _recipient);
        _migration.verify();
        assertTrue(IAccessControl(_extension).hasRole(IExtension(_extension).VERSION_MANAGER_ROLE(), _next));
        assertTrue(IAccessControl(_extension).hasRole(IFreezable(_extension).FREEZE_MANAGER_ROLE(), _next));
        assertTrue(IAccessControl(_extension).hasRole(IPausable(_extension).PAUSER_ROLE(), _next));
        assertTrue(IAccessControl(_extension).hasRole(IYieldToOne(_extension).YIELD_RECIPIENT_MANAGER_ROLE(), _next));
        if (_multi)
            assertTrue(IAccessControl(_extension).hasRole(IMultiMint(_extension).ASSET_CAP_MANAGER_ROLE(), _next));
        vm.recordLogs();
        _migration.run();
        assertEq(vm.getRecordedLogs().length, 0, "completed rerun must do nothing");
    }

    function _deploy(bool multi) private {
        _multi = multi;
        if (multi) {
            (_extension, ) = factory.deployMultiMint(
                _NAME,
                IExtensionFactory.MultiMintParams({
                    name: _NAME,
                    symbol: "MUSD",
                    yieldRecipient: _old,
                    admin: _old,
                    assetCapManager: _old,
                    freezeManager: _old,
                    pauser: _old,
                    yieldRecipientManager: _old,
                    versionManager: _old
                })
            );
        } else {
            (_extension, ) = factory.deployYieldToOne(
                _NAME,
                IExtensionFactory.YieldToOneParams({
                    name: _NAME,
                    symbol: "MUSD",
                    yieldRecipient: _old,
                    admin: _old,
                    freezeManager: _old,
                    pauser: _old,
                    yieldRecipientManager: _old,
                    versionManager: _old
                })
            );
        }
        _migration.inputs(_NAME, _json(), _record());
        _migration.signer(_oldKey);
    }

    function _record() private view returns (ScriptBase.Deployments memory d) {
        d.pyusdx = address(pyusdx);
        d.swapFacility = address(swapFacility);
        d.extensionFactory = address(factory);
        d.extensionNames = new string[](1);
        d.extensionNames[0] = _NAME;
        d.extensionAddresses = new address[](1);
        d.extensionAddresses[0] = _extension;
    }

    function _json() private view returns (string memory) {
        string memory holder = vm.toString(_next);
        return
            string.concat(
                '{"extensionName":"',
                _NAME,
                '","tokenName":"',
                _NAME,
                '","tokenSymbol":"MUSD","chainId":',
                vm.toString(block.chainid),
                ',"roles":{"admin":"',
                holder,
                '","freezeManager":"',
                holder,
                '","pauser":"',
                holder,
                '","versionManager":"',
                holder,
                '","yieldRecipientManager":"',
                holder,
                '","yieldRecipient":"',
                vm.toString(_recipient),
                '"',
                _multi ? string.concat(',"assetCapManager":"', holder, '"') : "",
                '},"migration":{"outgoingHolders":["',
                vm.toString(_old),
                '"]}}'
            );
    }
}
