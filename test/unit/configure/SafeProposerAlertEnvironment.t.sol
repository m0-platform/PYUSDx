// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { Chains } from "../../../script/config/Chains.sol";
import { Transaction } from "../../../script/libraries/TransactionHelper.sol";

import { SafeProposerAlertHarness } from "../../harness/SafeProposerAlertHarness.sol";

/// @notice Covers the one thing `SafeProposerAlert.t.sol` deliberately does not: that every setting
///         is actually read from the environment.
/// @dev    Its own file holding a single test, because forge shares one process environment across a
///         whole run and may interleave the tests within a suite. Being the only writer and the only
///         reader of these variables is what makes this deterministic.
///
///         Both library seams are still the harness's stand-ins, so this reads the environment
///         without submitting a proposal or sending an alert.
contract SafeProposerAlertEnvironmentTest is Test {
    string internal constant TEST_WEBHOOK_URL = "http://127.0.0.1:1/pyusdx-alert-env-test";

    address internal constant SAFE = address(0x5AFE);

    /// @dev Anvil's first default key. Never funded on any live network, and only ever used here to
    ///      show the configured key is the one the proposer address comes from.
    uint256 internal constant PROPOSER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    SafeProposerAlertHarness internal harness;

    function setUp() external {
        harness = new SafeProposerAlertHarness();

        harness.setUseEnvironment(true);

        vm.chainId(Chains.ETHEREUM);
    }

    function test_writeSafeBatch_readsEverySettingFromTheEnvironment() external {
        vm.setEnv("SAFE_SUBMIT", "true");
        vm.setEnv("SAFE_MULTISIG", vm.toString(SAFE));
        vm.setEnv("SLACK_WEBHOOK_URL", TEST_WEBHOOK_URL);
        vm.setEnv("PRIVATE_KEY", vm.toString(bytes32(PROPOSER_KEY)));

        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = Transaction({ target: address(0xA11CE), data: hex"c0de0000", value: 0 });

        harness.writeSafeBatch("environment", transactions);

        // `SAFE_SUBMIT` was honoured, against the `SAFE_MULTISIG` and `PRIVATE_KEY` from the
        // environment.
        assertEq(harness.submittedProposalCount(), 1);
        assertEq(harness.submittedProposal(0).safe, SAFE);
        assertEq(harness.submittedProposal(0).proposer, vm.addr(PROPOSER_KEY));

        // `SLACK_WEBHOOK_URL` reached the alert.
        assertEq(harness.recordedAlertCount(), 1);
        assertEq(harness.pendingWebhookUrl(), TEST_WEBHOOK_URL);

        string memory path = string.concat(vm.projectRoot(), "/safe/", vm.toString(block.chainid), "-environment.json");

        if (vm.isFile(path)) vm.removeFile(path);

        // Defensive: these writes outlive the test, since forge only rolls back EVM state between
        // tests. Every other suite reads these settings from its harness rather than the
        // environment, so this is belt and braces rather than the thing keeping them isolated.
        vm.setEnv("SAFE_SUBMIT", "false");
        vm.setEnv("SLACK_WEBHOOK_URL", "");
    }
}
