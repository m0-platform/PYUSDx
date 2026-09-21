// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";
import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IERC20Metadata } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { IPausable } from "../../lib/evm-m-extensions/src/components/pausable/IPausable.sol";
import { IExtension } from "../../src/platform/interfaces/IExtension.sol";
import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { IMultiMint } from "../../src/platform/projects/interfaces/IMultiMint.sol";
import { IYieldToOne } from "../../src/platform/projects/interfaces/IYieldToOne.sol";
import { ScriptBase } from "../ScriptBase.s.sol";

/// @notice Migrate one recorded extension to its configured holders; warn and skip missing authority.
/// @dev Uses the grant/check/revoke ordering from the suite migration. No deployment or proposal exports.
contract MigrateExtensionRoles is ScriptBase {
    struct RoleTarget {
        bytes32 role;
        address holder;
    }

    struct Migration {
        address extension;
        RoleTarget[] roles;
        address[] outgoing;
        address yieldRecipient;
    }

    error MigrationIncomplete(uint256 outstanding);
    error MissingRole(bytes32 role, address holder);

    function run() external {
        Migration memory migration = _loadMigration();
        address signer = vm.rememberKey(_signerPrivateKey());
        vm.startBroadcast(signer);
        _migrate(migration, signer);
        vm.stopBroadcast();
        console.log("Outstanding migration checks:", _outstanding(migration));
        console.log("Run verify-extension-roles after mined execution; only listed outgoing holders are checked.");
    }

    /// @notice Strict, read-only verification. Does not require a signing key.
    function verify() external view {
        uint256 outstanding = _outstanding(_loadMigration());
        if (outstanding != 0) revert MigrationIncomplete(outstanding);
        console.log("Configured roles and yield recipient verified; listed outgoing roles removed.");
    }

    function _migrate(Migration memory migration, address signer) private {
        IAccessControl access = IAccessControl(migration.extension);
        for (uint256 i; i < migration.roles.length; ++i) {
            RoleTarget memory desired = migration.roles[i];
            if (access.hasRole(desired.role, desired.holder)) continue;
            if (!_hasAuthority(access, access.getRoleAdmin(desired.role), signer)) continue;
            access.grantRole(desired.role, desired.holder);
            _requireRole(access, desired.role, desired.holder);
        }

        IYieldToOne extension = IYieldToOne(migration.extension);
        if (extension.yieldRecipient() != migration.yieldRecipient) {
            if (!_hasAuthority(access, extension.YIELD_RECIPIENT_MANAGER_ROLE(), signer)) {
                console.log("WARNING: keeping outgoing roles until the yield recipient can be migrated");
                return;
            }
            // Pays accrued yield to the old recipient, unless frozen (the contract then skips the claim).
            extension.setYieldRecipient(migration.yieldRecipient);
            require(extension.yieldRecipient() == migration.yieldRecipient, "yield recipient update failed");
        }

        // DEFAULT_ADMIN_ROLE is first in the list, so reverse iteration removes it last.
        for (uint256 i = migration.roles.length; i > 0; --i) {
            RoleTarget memory desired = migration.roles[i - 1];
            bool removeSelf;
            for (uint256 j; j < migration.outgoing.length; ++j) {
                address old = migration.outgoing[j];
                if (old == desired.holder || !access.hasRole(desired.role, old)) continue;
                if (!_hasAuthority(access, access.getRoleAdmin(desired.role), signer)) break;
                _requireRole(access, desired.role, desired.holder);
                if (old == signer) removeSelf = true;
                else access.revokeRole(desired.role, old);
            }
            // Other admins must leave before the signer, regardless of outgoing-list order.
            if (removeSelf) access.revokeRole(desired.role, signer);
        }
    }

    function _hasAuthority(IAccessControl access, bytes32 role, address signer) private view returns (bool) {
        if (access.hasRole(role, signer)) return true;
        console.log("WARNING: skipped; signer lacks authority on", address(access), signer);
        console.logBytes32(role);
        return false;
    }

    function _requireRole(IAccessControl access, bytes32 role, address holder) private view {
        if (!access.hasRole(role, holder)) revert MissingRole(role, holder);
    }

    function _outstanding(Migration memory migration) private view returns (uint256 count) {
        IAccessControl access = IAccessControl(migration.extension);
        for (uint256 i; i < migration.roles.length; ++i) {
            RoleTarget memory desired = migration.roles[i];
            if (!access.hasRole(desired.role, desired.holder)) {
                console.log("Missing incoming role:", desired.holder);
                console.logBytes32(desired.role);
                ++count;
            }
            for (uint256 j; j < migration.outgoing.length; ++j) {
                address old = migration.outgoing[j];
                if (old == desired.holder || !access.hasRole(desired.role, old)) continue;
                console.log("Outgoing role remains:", old);
                console.logBytes32(desired.role);
                ++count;
            }
        }
        if (IYieldToOne(migration.extension).yieldRecipient() != migration.yieldRecipient) {
            console.log("Outstanding yield recipient:", migration.yieldRecipient);
            ++count;
        }
    }

    function _loadMigration() private view returns (Migration memory migration) {
        (string memory name, string memory json, Deployments memory record) = _readInputs();
        require(bytes(name).length != 0, "empty EXTENSION_NAME");
        require(
            keccak256(bytes(vm.parseJsonString(json, ".extensionName"))) == keccak256(bytes(name)),
            "config extensionName does not match EXTENSION_NAME"
        );
        require(
            keccak256(bytes(vm.parseJsonString(json, ".tokenName"))) == keccak256(bytes(name)),
            "config tokenName must equal extensionName"
        );
        if (vm.keyExistsJson(json, ".chainId"))
            require(vm.parseJsonUint(json, ".chainId") == block.chainid, "config chainId mismatch");
        require(record.extensionNames.length == record.extensionAddresses.length, "invalid deployment record");
        bool found;
        for (uint256 i; i < record.extensionNames.length; ++i) {
            if (keccak256(bytes(record.extensionNames[i])) != keccak256(bytes(name))) continue;
            require(!found, "ambiguous extension record");
            found = true;
            migration.extension = record.extensionAddresses[i];
        }
        address target = migration.extension;
        require(found && target.code.length != 0, "extension not deployed");
        require(
            record.extensionFactory.code.length != 0 &&
                record.pyusdx.code.length != 0 &&
                record.swapFacility.code.length != 0,
            "suite not deployed"
        );
        IExtensionFactory.ExtensionType kind = IExtensionFactory(record.extensionFactory).getExtensionType(target);
        require(kind != IExtensionFactory.ExtensionType.NONE, "extension not registered");
        require(
            IExtension(target).pyusdx() == record.pyusdx && IExtension(target).swapFacility() == record.swapFacility,
            "extension wiring mismatch"
        );
        require(keccak256(bytes(IERC20Metadata(target).name())) == keccak256(bytes(name)), "token name mismatch");
        require(
            keccak256(bytes(IERC20Metadata(target).symbol())) ==
                keccak256(bytes(vm.parseJsonString(json, ".tokenSymbol"))),
            "token symbol mismatch"
        );

        bool multi = kind == IExtensionFactory.ExtensionType.MULTI_MINT;
        require(multi == vm.keyExistsJson(json, ".roles.assetCapManager"), "config extension type mismatch");
        migration.roles = new RoleTarget[](multi ? 6 : 5);
        migration.roles[0] = RoleTarget(0, vm.parseJsonAddress(json, ".roles.admin"));
        migration.roles[1] = RoleTarget(
            IYieldToOne(target).YIELD_RECIPIENT_MANAGER_ROLE(),
            vm.parseJsonAddress(json, ".roles.yieldRecipientManager")
        );
        migration.roles[2] = RoleTarget(
            IFreezable(target).FREEZE_MANAGER_ROLE(),
            vm.parseJsonAddress(json, ".roles.freezeManager")
        );
        migration.roles[3] = RoleTarget(IPausable(target).PAUSER_ROLE(), vm.parseJsonAddress(json, ".roles.pauser"));
        migration.roles[4] = RoleTarget(
            IExtension(target).VERSION_MANAGER_ROLE(),
            vm.parseJsonAddress(json, ".roles.versionManager")
        );
        if (multi)
            migration.roles[5] = RoleTarget(
                IMultiMint(target).ASSET_CAP_MANAGER_ROLE(),
                vm.parseJsonAddress(json, ".roles.assetCapManager")
            );
        for (uint256 i; i < migration.roles.length; ++i)
            require(migration.roles[i].holder != address(0), "zero incoming holder");
        migration.yieldRecipient = vm.parseJsonAddress(json, ".roles.yieldRecipient");
        require(migration.yieldRecipient != address(0), "zero yield recipient");
        // An explicit empty list grants configured roles without removing any existing holder.
        migration.outgoing = vm.parseJsonAddressArray(json, ".migration.outgoingHolders");
        for (uint256 i; i < migration.outgoing.length; ++i)
            require(migration.outgoing[i] != address(0), "zero outgoing holder");
    }

    /// @dev Test seam keeps fixtures in memory rather than writing deployment/config files.
    function _readInputs()
        internal
        view
        virtual
        returns (string memory name, string memory json, Deployments memory record)
    {
        name = _getExtensionName();
        string memory path = vm.envOr(
            "EXTENSION_CONFIG",
            string.concat(vm.projectRoot(), "/deploymentConfigs/", vm.toString(block.chainid), "/", name, ".json")
        );
        console.log("Config file:", path);
        json = vm.readFile(path);
        record = _readDeployment(block.chainid);
    }

    function _signerPrivateKey() internal view virtual returns (uint256) {
        return vm.envUint("PRIVATE_KEY");
    }
}
