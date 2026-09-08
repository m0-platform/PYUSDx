// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { Safe } from "../../../lib/safe-utils/src/Safe.sol";

import { Chains } from "../../../script/config/Chains.sol";
import { SafeAppConfig } from "../../../script/config/SafeAppConfig.sol";
import {
    ProposalValueNotSupported,
    Transaction,
    TransactionHelper
} from "../../../script/libraries/TransactionHelper.sol";

import {
    EmptyTransactionBatch,
    NotSelfCall,
    SafeBatchNotPersisted,
    SafeMultisigNotSet,
    SafeProposerBase
} from "../../../script/configure/SafeProposerBase.sol";
import { SafeProposerAlertHarness } from "../../harness/SafeProposerAlertHarness.sol";

/// @notice Drives the real `TransactionHelper.propose` boundary from an external frame.
/// @dev    Only ever called with a valued transaction, which the guard rejects before `safe-utils`
///         issues any request -- so this cannot reach the network.
contract ProposeValueGuard {
    using TransactionHelper for Transaction[];

    Safe.Client internal safeClient;

    function propose(Transaction[] memory transactions) external {
        transactions.propose(safeClient, address(0x5AFE), address(0xB0B));
    }
}

/// @notice Covers when `SafeProposerBase` submits a proposal, when it alerts, and what the alert
///         says.
/// @dev    Nothing here reaches the network. The submission seam -- `SafeProposerBase` calling
///         `Safe.proposeTransactions` -- is always the harness's stand-in, and so is the Slack one,
///         except for the test that proves an unavailable transport is contained.
///
///         What `safe-utils` and `foundry-slack` do internally is their own suites' business:
///         `MultiSend` packing, request bodies, signature encoding and JSON escaping are not
///         reasserted here.
contract SafeProposerAlertTest is Test {
    /// @dev Deliberately unroutable: nothing listens here, so even a run with `--ffi` cannot deliver
    ///      an alert anywhere.
    string internal constant TEST_WEBHOOK_URL = "http://127.0.0.1:1/pyusdx-alert-test";

    uint256 internal constant PROPOSER_KEY = 0xB0BB1E;

    address internal constant SAFE = address(0x5AFE);

    address internal constant PORTAL = address(0xA11CE);

    address internal constant ADAPTER = address(0xB0B);

    SafeProposerAlertHarness internal harness;

    function setUp() external {
        harness = new SafeProposerAlertHarness();

        harness.setSafe(SAFE);
        harness.setPrivateKey(PROPOSER_KEY);
        // Every chain-dependent branch is exercised explicitly; Ethereum is the default so the
        // submission path has a supported chain to work with.
        vm.chainId(Chains.ETHEREUM);
    }

    /* ============ Offline export (default) ============ */

    function test_writeSafeBatch_exportOnly_neverSubmitsOrAlerts() external {
        // A configured webhook must not be enough to produce an alert: a written file is not a
        // proposal the Safe has accepted.
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        harness.writeSafeBatch("export-only", _transactions(2));

        assertEq(harness.submittedProposalCount(), 0);
        assertEq(harness.recordedAlertCount(), 0);

        string memory path = _batchPath("export-only");
        assertTrue(vm.isFile(path));
        assertEq(vm.parseJsonAddress(vm.readFile(path), ".transactions[0].to"), PORTAL);

        _removeBatch("export-only");
    }

    function test_writeSafeBatch_emptyBatch_revertsBeforeAnything() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        vm.expectRevert(EmptyTransactionBatch.selector);
        harness.writeSafeBatch("empty-batch", new Transaction[](0));

        assertEq(harness.submittedProposalCount(), 0);
        assertEq(harness.recordedAlertCount(), 0);
        assertFalse(vm.isFile(_batchPath("empty-batch")));
    }

    function test_writeSafeBatch_unconfirmedExport_revertsBeforeSubmission() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);
        harness.setConfirmBatch(false);

        vm.expectRevert(abi.encodeWithSelector(SafeBatchNotPersisted.selector, _batchPath("unconfirmed")));
        harness.writeSafeBatch("unconfirmed", _transactions(2));

        assertEq(harness.submittedProposalCount(), 0);
        assertEq(harness.recordedAlertCount(), 0);

        _removeBatch("unconfirmed");
    }

    /* ============ Dry run ============ */

    function test_writeSafeBatch_dryRun_bypassesSubmissionAndAlert() external {
        harness.setSubmit(true);
        harness.setDryRun(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        harness.writeSafeBatch("dry-run", _transactions(2));

        // `DRY_RUN=true` promises no network side effects. A queued proposal is one, and so is a
        // Slack message.
        assertEq(harness.submittedProposalCount(), 0);
        assertEq(harness.recordedAlertCount(), 0);
        assertTrue(vm.isFile(_batchPath("dry-run")));

        _removeBatch("dry-run");
    }

    /* ============ Accepted submission ============ */

    function test_writeSafeBatch_acceptedProposal_alertsOnce() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        Transaction[] memory transactions = _transactions(2);

        harness.writeSafeBatch("accepted", transactions);

        assertEq(harness.submittedProposalCount(), 1);
        assertEq(harness.submittedProposal(0).safe, SAFE);
        assertEq(harness.submittedProposal(0).proposer, vm.addr(PROPOSER_KEY));
        assertEq(harness.submittedProposal(0).transactionCount, 2);

        assertEq(harness.recordedAlertCount(), 1);
        assertEq(harness.pendingWebhookUrl(), TEST_WEBHOOK_URL);

        string memory payload = harness.recordedPayload(0);

        // The alert carries what only a confirmed submission can give it.
        assertTrue(vm.contains(payload, vm.toString(harness.expectedSafeTxHash(transactions))));
        assertTrue(vm.contains(payload, "*Nonce*\\n7"));
        assertTrue(vm.contains(payload, vm.toString(harness.proposer())));
        assertTrue(vm.contains(payload, vm.toString(SAFE)));
        assertTrue(vm.contains(payload, string.concat("safe/", vm.toString(block.chainid), "-accepted.json")));

        _removeBatch("accepted");
    }

    function test_writeSafeBatch_acceptedProposal_missingWebhook_stillSubmits() external {
        harness.setSubmit(true);
        harness.setWebhookUrl("");

        harness.writeSafeBatch("no-webhook", _transactions(2));

        assertEq(harness.submittedProposalCount(), 1);
        assertEq(harness.recordedAlertCount(), 0);

        _removeBatch("no-webhook");
    }

    function test_writeSafeBatch_missingSafe_revertsBeforeSubmission() external {
        harness.setSubmit(true);
        harness.setSafe(address(0));

        vm.expectRevert(SafeMultisigNotSet.selector);
        harness.writeSafeBatch("no-safe", _transactions(2));

        assertEq(harness.submittedProposalCount(), 0);
        assertEq(harness.recordedAlertCount(), 0);

        _removeBatch("no-safe");
    }

    /* ============ Rejected submission ============ */

    function test_writeSafeBatch_rejectedProposal_revertsWithoutAlert() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);
        harness.setRejectionReason("nonce already used");

        // `Safe.proposeTransactions` reverts on any non-2xx answer, so the whole run fails before
        // the alert is reached: a rejected proposal does not exist to sign.
        vm.expectRevert(bytes("nonce already used"));
        harness.writeSafeBatch("rejected", _transactions(2));

        // The revert rolls the harness's records back with everything else, but the export survives
        // it, because a file write is not EVM state.
        assertEq(harness.submittedProposalCount(), 0);
        assertEq(harness.recordedAlertCount(), 0);
        assertTrue(vm.isFile(_batchPath("rejected")));

        _removeBatch("rejected");
    }

    /* ============ Alert failure containment ============ */

    function test_writeSafeBatch_alertFailure_doesNotRevertOrResubmit() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);
        harness.setPostOutcome(SafeProposerBase.AlertOutcome.Failed);

        harness.writeSafeBatch("alert-failed", _transactions(2));

        // One submission, one alert attempt, no revert. A retry here is what would turn a webhook
        // outage into a second queued proposal once an operator reran the script.
        assertEq(harness.submittedProposalCount(), 1);
        assertEq(harness.recordedAlertCount(), 1);
        assertTrue(vm.isFile(_batchPath("alert-failed")));

        _removeBatch("alert-failed");
    }

    function test_writeSafeBatch_unavailableAlertTransport_doesNotRevert() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);
        harness.setUseRealAlertTransport(true);

        // `--ffi` is off by default, so `Slack.send` cannot run at all here. That is the harshest
        // case -- the cheatcode itself reverts -- and the `try` boundary must still contain it.
        harness.writeSafeBatch("no-transport", _transactions(2));

        assertEq(harness.submittedProposalCount(), 1);
        assertEq(harness.recordedAlertCount(), 1);

        _removeBatch("no-transport");
    }

    function test_sendPendingAlert_rejectsExternalCallers() external {
        // The entry point is `external` only so `_postAlert` can `try` it. Nobody else may send.
        vm.expectRevert(NotSelfCall.selector);
        harness.sendPendingAlert();
    }

    /* ============ Payload ============ */

    function test_writeSafeBatch_payloadIsValidBlockKit() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        harness.writeSafeBatch("configure-portal", _transactions(2));

        string memory payload = harness.recordedPayload(0);

        assertEq(vm.parseJsonString(payload, ".text"), "Safe proposal: configure-portal on eth (1)");
        // header, fields, calls, divider, sign -- and nothing after them.
        assertEq(vm.parseJsonString(payload, ".blocks[0].type"), "header");
        assertEq(vm.parseJsonString(payload, ".blocks[1].type"), "section");
        assertEq(vm.parseJsonString(payload, ".blocks[2].type"), "section");
        assertEq(vm.parseJsonString(payload, ".blocks[3].type"), "divider");
        assertEq(vm.parseJsonString(payload, ".blocks[4].type"), "section");
        assertFalse(vm.keyExists(payload, ".blocks[5]"));

        assertEq(vm.parseJsonString(payload, ".blocks[1].fields[0].text"), "*Chain*\neth (1)");
        assertEq(
            vm.parseJsonString(payload, ".blocks[1].fields[1].text"),
            string.concat("*Safe*\n`", vm.toString(SAFE), "`")
        );
        assertEq(vm.parseJsonString(payload, ".blocks[1].fields[2].text"), "*Nonce*\n7");
        assertEq(
            vm.parseJsonString(payload, ".blocks[1].fields[3].text"),
            string.concat("*Proposer*\n`", vm.toString(vm.addr(PROPOSER_KEY)), "`")
        );
        assertEq(vm.parseJsonString(payload, ".blocks[1].fields[4].text"), "*Operation*\nDelegateCall (MultiSend)");
        assertEq(vm.parseJsonString(payload, ".blocks[1].fields[5].text"), "*Calls*\n2 (batched)");
        assertFalse(vm.keyExists(payload, ".blocks[1].fields[6]"));

        _removeBatch("configure-portal");
    }

    function test_writeSafeBatch_payloadEscapesQuotesAndNewlines() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        // Composed from the byte rather than written as a literal: a literal double quote inside a
        // Solidity string makes prettier switch the whole literal to single quotes, which solhint
        // then rejects. The batch name is the only caller-supplied string in the message.
        string memory name = string.concat("weird", string(abi.encodePacked(bytes1(0x22))), "name\nwith\ttabs");

        harness.writeSafeBatch(name, _transactions(1));

        // Round-tripping through the JSON parser is the assertion: an unescaped quote or newline
        // would make the whole body unparseable, which is exactly how Slack would see it.
        assertEq(
            vm.parseJsonString(harness.recordedPayload(0), ".text"),
            string.concat("Safe proposal: ", name, " on eth (1)")
        );

        _removeBatch(name);
    }

    function test_writeSafeBatch_mappedChain_includesSigningLink() external {
        vm.chainId(Chains.ARBITRUM);

        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        Transaction[] memory transactions = _transactions(1);

        harness.writeSafeBatch("configure-lz-adapter", transactions);

        string memory safeAddress = vm.toString(SAFE);

        assertTrue(
            vm.contains(
                harness.recordedPayload(0),
                string.concat(
                    "https://app.safe.global/transactions/tx?safe=arb1:",
                    safeAddress,
                    "&id=multisig_",
                    safeAddress,
                    "_",
                    vm.toString(harness.expectedSafeTxHash(transactions))
                )
            )
        );

        _removeBatch("configure-lz-adapter");
    }

    function test_writeSafeBatch_unmappedChain_omitsLink() external {
        // Monad Testnet has a transaction service but no Safe web app, so a proposal there is real
        // and its link is not. The hash still ships; a dead link does not.
        vm.chainId(Chains.MONAD_TESTNET);

        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        Transaction[] memory transactions = _transactions(1);

        harness.writeSafeBatch("configure-portal", transactions);

        string memory payload = harness.recordedPayload(0);

        assertFalse(vm.contains(payload, "app.safe.global"));
        assertTrue(vm.contains(payload, vm.toString(harness.expectedSafeTxHash(transactions))));
        assertEq(
            vm.parseJsonString(payload, ".text"),
            string.concat("Safe proposal: configure-portal on ", vm.toString(uint256(Chains.MONAD_TESTNET)))
        );

        _removeBatch("configure-portal");
    }

    function test_writeSafeBatch_longBatch_truncatesCallList() external {
        harness.setSubmit(true);
        harness.setWebhookUrl(TEST_WEBHOOK_URL);

        uint256 count = harness.maxListedTransactions() + 5;

        harness.writeSafeBatch("long-batch", _transactions(count));

        string memory payload = harness.recordedPayload(0);

        assertTrue(vm.contains(payload, "*Calls*\\n25 (batched)"));
        assertTrue(vm.contains(payload, "_+5 more_"));
        // The 21st call is the first one dropped; its selector must not appear.
        assertTrue(vm.contains(payload, _selectorString(harness.maxListedTransactions() - 1)));
        assertFalse(vm.contains(payload, _selectorString(harness.maxListedTransactions())));

        _removeBatch("long-batch");
    }

    /* ============ Library boundary ============ */

    function test_propose_valuedTransaction_reverts() external {
        // `safe-utils` packs every call in a batch at zero value, so a valued call cannot be
        // proposed as the offline export describes it. Failing is the only honest option.
        Transaction[] memory transactions = new Transaction[](2);
        transactions[0] = Transaction({ target: PORTAL, data: hex"c0de0000", value: 0 });
        transactions[1] = Transaction({ target: ADAPTER, data: hex"c0de0001", value: 1 ether });

        ProposeValueGuard guard = new ProposeValueGuard();

        vm.expectRevert(abi.encodeWithSelector(ProposalValueNotSupported.selector, uint256(1), uint256(1 ether)));
        guard.propose(transactions);
    }

    /* ============ Chain coverage ============ */

    /// @dev The boundary between this repo's chain list and `safe-utils`'s tables, which is what
    ///      decides whether `SAFE_SUBMIT=true` can work at all on a given deployment target. The
    ///      tables themselves are the library's to test; that they answer for every PYUSDX chain is
    ///      this repo's to check, and it is what the README's coverage table claims.
    function test_chainCoverage_matchesTheDocumentedTable() external {
        uint32[7] memory submittable = [
            Chains.ETHEREUM,
            Chains.ARBITRUM,
            Chains.MONAD,
            Chains.BASE,
            Chains.SEPOLIA,
            Chains.BASE_SEPOLIA,
            Chains.MONAD_TESTNET
        ];

        for (uint256 i; i < submittable.length; ++i) {
            assertTrue(bytes(harness.networkShortName(submittable[i])).length != 0);
            assertTrue(harness.multiSendCallOnly(submittable[i]) != address(0));
        }

        // No Safe transaction service serves Arbitrum Sepolia, so it is offline-export only.
        vm.expectRevert(abi.encodeWithSelector(Safe.ApiKitUrlNotFound.selector, uint256(Chains.ARBITRUM_SEPOLIA)));
        harness.networkShortName(Chains.ARBITRUM_SEPOLIA);

        // A signing link needs a Safe web app, which is a different question and a smaller set.
        (string memory monadTestnetShortName, ) = SafeAppConfig.getConfig(Chains.MONAD_TESTNET);
        assertEq(monadTestnetShortName, "");

        (string memory ethereumShortName, string memory ethereumAppUrl) = SafeAppConfig.getConfig(Chains.ETHEREUM);
        assertEq(ethereumShortName, "eth");
        assertEq(ethereumAppUrl, "https://app.safe.global");
    }

    /* ============ Helpers ============ */

    /// @dev Every call gets a distinct selector so a truncation assertion can name the first entry
    ///      that should have been dropped.
    function _transactions(uint256 count) internal pure returns (Transaction[] memory transactions) {
        transactions = new Transaction[](count);

        for (uint256 i; i < count; ++i) {
            transactions[i] = Transaction({
                target: i == 0 ? PORTAL : ADAPTER,
                data: abi.encodePacked(_selector(i)),
                value: 0
            });
        }
    }

    function _selector(uint256 index) internal pure returns (bytes4) {
        return bytes4(uint32(0xc0de0000 + index));
    }

    function _selectorString(uint256 index) internal pure returns (string memory) {
        return vm.toString(abi.encodePacked(_selector(index)));
    }

    function _batchPath(string memory name) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/safe/", vm.toString(block.chainid), "-", name, ".json");
    }

    function _removeBatch(string memory name) internal {
        string memory path = _batchPath(name);

        if (vm.isFile(path)) vm.removeFile(path);
    }
}
