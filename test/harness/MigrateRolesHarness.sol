// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Ownable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { Upgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { Config } from "../../script/Config.sol";
import { Transaction, TransactionHelper } from "../../script/libraries/TransactionHelper.sol";
import { MigrateRolesBase, MigrationAction } from "../../script/migrate/MigrateRolesBase.sol";

/// @notice Exposes the role-migration plan builder for testing, and doubles as the sender of the
///         staged batch so a test can play an outgoing authority holder.
/// @dev    `executeBatch` runs the batch through the same `TransactionHelper.execute` the direct
///         script uses, with this contract as `msg.sender` — which is why tests deploy one harness
///         per current authority holder rather than pranking an EOA.
contract MigrateRolesHarness is MigrateRolesBase {
    using TransactionHelper for Transaction[];

    function executeBatch(Transaction[] memory transactions) external {
        transactions.execute();
    }

    function planMigration(
        Deployments memory deployments,
        ProtocolConfig memory config,
        Config.MigrationConfig memory migration,
        address executor
    ) external view returns (MigrationAction[] memory) {
        return _planMigration(deployments, config, migration, executor);
    }

    function stagedTransactions(MigrationAction[] memory actions) external pure returns (Transaction[] memory) {
        return _stagedTransactions(actions);
    }

    function outstandingCount(MigrationAction[] memory actions) external pure returns (uint256) {
        return _outstandingCount(actions);
    }

    function deferredCount(MigrationAction[] memory actions) external pure returns (uint256) {
        return _deferredCount(actions);
    }

    /// @dev Resolves the ProxyAdmin the plan targets, via the same `Upgrades` helper it uses.
    function proxyAdminOf(address proxy) public view returns (address) {
        return Upgrades.getAdminAddress(proxy);
    }

    /// @dev Reads the ProxyAdmin owner the plan compares against.
    function proxyAdminOwner(address proxy) external view returns (address) {
        return Ownable(proxyAdminOf(proxy)).owner();
    }

    function parseMigrationConfig(string memory json) external view returns (Config.MigrationConfig memory) {
        return _parseMigrationConfig(json);
    }
}
