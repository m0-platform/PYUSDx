// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { Transaction } from "../../../script/libraries/TransactionHelper.sol";

import { EmptyTransactionBatch } from "../../../script/configure/SafeProposerBase.sol";
import { SafeProposerHarness } from "../../harness/SafeProposerHarness.sol";

contract SafeProposerTest is Test {
    SafeProposerHarness internal harness;

    function setUp() external {
        harness = new SafeProposerHarness();
    }

    function test_writeSafeBatch_emptyTransactions() external {
        Transaction[] memory transactions = new Transaction[](0);

        vm.expectRevert(EmptyTransactionBatch.selector);

        harness.writeSafeBatch("unit-test", transactions);
    }

    function test_writeSafeBatch_writesImportableJson() external {
        Transaction[] memory transactions = new Transaction[](2);
        transactions[0] = Transaction({ target: address(0xAAa), data: hex"1234", value: 0 });
        transactions[1] = Transaction({ target: address(0xBbB), data: hex"5678", value: 0 });

        harness.writeSafeBatch("unit-test", transactions);

        string memory path = string.concat(vm.projectRoot(), "/safe/", vm.toString(block.chainid), "-unit-test.json");
        string memory json = vm.readFile(path);

        assertEq(vm.parseJsonString(json, ".version"), "1.0");
        assertEq(vm.parseJsonString(json, ".chainId"), vm.toString(block.chainid));
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(0xAAa));
        assertEq(vm.parseJsonBytes(json, ".transactions[0].data"), hex"1234");
        assertEq(vm.parseJsonAddress(json, ".transactions[1].to"), address(0xBbB));
        assertEq(vm.parseJsonBytes(json, ".transactions[1].data"), hex"5678");

        vm.removeFile(path);
    }
}
