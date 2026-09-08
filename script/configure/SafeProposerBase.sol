// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { console } from "../../lib/forge-std/src/console.sol";

import { Slack } from "../../lib/foundry-slack/src/Slack.sol";
import { Safe } from "../../lib/safe-utils/src/Safe.sol";

import { SafeAppConfig } from "../config/SafeAppConfig.sol";
import { Transaction, TransactionHelper } from "../libraries/TransactionHelper.sol";
import { ScriptBase } from "../ScriptBase.s.sol";

/// @notice Thrown when a Safe batch would be written with no transactions, which would otherwise
///         report success for work that was never proposed.
error EmptyTransactionBatch();

/// @notice Thrown when the batch file cannot be read back byte-for-byte after being written, so the
///         export a signer is meant to import does not verifiably exist.
error SafeBatchNotPersisted(string path);

/// @notice Thrown when submission is requested without a `SAFE_MULTISIG` to submit to.
error SafeMultisigNotSet();

/// @notice Thrown when the alert send entry point is called from outside the script.
/// @dev    It is `external` only so the notification can be contained by a `try`; it is not part of
///         the script's interface.
error NotSelfCall();

/// @title  SafeProposerBase
/// @notice Turns a `Transaction[]` into a Safe proposal for the `Propose*` configuration scripts, so
///         the wiring can be executed by a multisig instead of broadcast directly. Two modes:
///
///         - **Offline export (default).** Serializes the batch to a Safe Transaction Builder JSON
///           at `safe/<chainid>-<name>.json` for manual import. Touches no network and never alerts:
///           a file on disk is not a proposal the Safe has accepted, and announcing one as if it
///           were is exactly the false signal this must not send.
///         - **Service submission (`SAFE_SUBMIT=true`).** Also queues the batch on the Safe
///           transaction service through `lib/safe-utils`, then announces it through
///           `lib/foundry-slack` -- only after the service has accepted it.
///
/// @dev    Composition only. The Safe wire format, per-chain transaction service and
///         `MultiSendCallOnly` tables, signing and the HTTP request belong to `lib/safe-utils`; the
///         Block Kit payload and its transport belong to `lib/foundry-slack`. What is left here is
///         the mode gating, the offline export and the message content -- adapted from
///         `evm-m-suite-deployment/script/ProposeBase.sol`. Setup and limitations are documented in
///         `README.md#multisig-alerts`.
///
///         The export is written in both modes, before anything is submitted. It costs nothing and
///         leaves a reviewable artifact whether or not the submission goes through.
abstract contract SafeProposerBase is ScriptBase {
    using Safe for Safe.Client;
    using Slack for Slack.Client;
    using Slack for Slack.Message;
    using TransactionHelper for Transaction[];

    /// @notice What happened to a proposal alert.
    /// @dev    Returned rather than reverted on: by the time an alert is attempted the proposal has
    ///         already been accepted, and none of these outcomes changes that.
    ///
    ///         There is deliberately no `Delivered`. `Slack._post` discards `curl`'s output, so the
    ///         webhook's response status never reaches this contract and a claim of delivery would
    ///         be a claim this code cannot support. `Sent` means the request was issued.
    enum AlertOutcome {
        Skipped,
        Sent,
        Failed
    }

    /// @dev A Block Kit section caps at 3000 characters. To avoid a payload Slack rejects, at most
    ///      this many calls are listed and the rest are reduced to a count.
    uint256 internal constant MAX_LISTED_TRANSACTIONS = 20;

    /// @dev Every name below is read through `vm.envOr` except `PRIVATE_KEY`, which is required once
    ///      submission is on. Held as constants so the docs, the log lines and the lookups cannot
    ///      drift apart.
    string internal constant ALERT_WEBHOOK_URL_ENV = "SLACK_WEBHOOK_URL";

    string internal constant SAFE_MULTISIG_ENV = "SAFE_MULTISIG";

    string internal constant SAFE_SUBMIT_ENV = "SAFE_SUBMIT";

    string internal constant PRIVATE_KEY_ENV = "PRIVATE_KEY";

    string internal constant DRY_RUN_ENV = "DRY_RUN";

    Safe.Client internal safeClient;

    Slack.Client internal slackClient;

    /// @notice Exports the batch and, when submission is enabled, queues and announces it.
    function _writeSafeBatch(string memory name, Transaction[] memory transactions) internal {
        if (transactions.length == 0) revert EmptyTransactionBatch();

        string memory relativePath = _exportSafeBatch(name, transactions);

        if (!_submitEnabled()) {
            console.log("Offline export only: %s is not true, so no proposal was", SAFE_SUBMIT_ENV);
            console.log("submitted to the Safe transaction service and no alert was sent.");
            return;
        }

        // `DRY_RUN=true` means no network side effects anywhere in this repo. A queued proposal is
        // one, so the mode is honoured by not submitting -- and therefore by not alerting either.
        if (_dryRun()) {
            console.log("%s=true: submission bypassed. The export above is the only output.", DRY_RUN_ENV);
            return;
        }

        address safe = _safeMultisig();

        if (safe == address(0)) revert SafeMultisigNotSet();

        // Registering the key is what lets `Safe.sign` sign the digest for this address; the
        // proposer is then just an address as far as everything below is concerned.
        address proposer = vm.rememberKey(_proposerPrivateKey());

        (bytes32 safeTxHash, uint256 nonce) = _submitSafeProposal(safe, proposer, transactions);

        console.log("Safe transaction service accepted the proposal at nonce %s, safeTxHash:", nonce);
        console.log(vm.toString(safeTxHash));

        _notifySafeProposal(name, relativePath, safe, proposer, safeTxHash, nonce, transactions);
    }

    /* ============ Export ============ */

    /// @notice Writes the Transaction Builder batch and confirms it landed. Returns its path,
    ///         relative to the project root.
    function _exportSafeBatch(
        string memory name,
        Transaction[] memory transactions
    ) internal returns (string memory relativePath) {
        string memory dir = string.concat(vm.projectRoot(), "/safe");
        vm.createDir(dir, true);

        string memory json = _buildBatchJson(name, transactions);

        relativePath = string.concat("safe/", vm.toString(block.chainid), "-", name, ".json");

        string memory path = string.concat(vm.projectRoot(), "/", relativePath);

        vm.writeFile(path, json);

        if (!_confirmSafeBatch(path, json)) revert SafeBatchNotPersisted(path);

        console.log("Safe batch (%s transactions) exported to:", transactions.length);
        console.log(path);
    }

    function _buildBatchJson(
        string memory name,
        Transaction[] memory transactions
    ) internal view returns (string memory) {
        string memory transactionsJson = "[";

        for (uint256 i; i < transactions.length; ++i) {
            if (i > 0) transactionsJson = string.concat(transactionsJson, ",");

            transactionsJson = string.concat(
                transactionsJson,
                '{"to":"',
                vm.toString(transactions[i].target),
                '","value":"',
                vm.toString(transactions[i].value),
                '","data":"',
                vm.toString(transactions[i].data),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        transactionsJson = string.concat(transactionsJson, "]");

        return
            string.concat(
                '{"version":"1.0","chainId":"',
                vm.toString(block.chainid),
                '","createdAt":',
                vm.toString(block.timestamp),
                ',"meta":{"name":"',
                name,
                '","txBuilderVersion":"1.16.5"},"transactions":',
                transactionsJson,
                "}"
            );
    }

    /// @notice Confirms the written export is the batch that was serialized.
    /// @dev    `virtual` so a test can withhold confirmation without corrupting the filesystem.
    function _confirmSafeBatch(string memory path, string memory json) internal virtual returns (bool) {
        if (!vm.isFile(path)) return false;

        return keccak256(bytes(vm.readFile(path))) == keccak256(bytes(json));
    }

    /* ============ Submission ============ */

    /// @notice Queues the batch on the Safe transaction service, and reports the nonce it claimed.
    /// @dev    `Safe.proposeTransactions` reverts unless the service answers 2xx, so everything
    ///         downstream -- the log line, the alert -- already sits behind an accepted proposal.
    ///
    ///         `virtual` so a test can drive both outcomes without touching the network.
    function _submitSafeProposal(
        address safe,
        address proposer,
        Transaction[] memory transactions
    ) internal virtual returns (bytes32 safeTxHash, uint256 nonce) {
        safeTxHash = transactions.propose(safeClient, safe, proposer);

        // Read after proposing on purpose: queuing does not advance the Safe's on-chain nonce, so
        // this is still the nonce the proposal claimed and the one a signer will see pending.
        nonce = safeClient.getNonce();
    }

    /* ============ Alerts ============ */

    /// @notice Announces an accepted proposal, if a webhook is configured.
    /// @dev    Total: every failure below returns an outcome instead of reverting. The proposal is
    ///         already queued by this point, so a revert here would report failure for work that
    ///         succeeded, and an operator rerunning the script would submit the same batch again.
    ///         Queuing does not advance the Safe's on-chain nonce -- that only moves on execution --
    ///         so the second proposal lands at the same nonce as the first, and signers are left
    ///         with two competing entries. Alert failures must stay invisible to the proposal.
    function _notifySafeProposal(
        string memory name,
        string memory relativePath,
        address safe,
        address proposer,
        bytes32 safeTxHash,
        uint256 nonce,
        Transaction[] memory transactions
    ) internal returns (AlertOutcome) {
        // Unconfigured is a silent no-op, so the alert integration stays opt-in.
        string memory webhookUrl = _alertWebhookUrl();

        if (bytes(webhookUrl).length == 0) {
            console.log("Proposal alert skipped: %s is not set.", ALERT_WEBHOOK_URL_ENV);
            return AlertOutcome.Skipped;
        }

        (string memory shortName, string memory appUrl) = SafeAppConfig.getConfig(uint32(block.chainid));

        Slack.Message storage message = slackClient.initialize(webhookUrl);

        message.withText(string.concat("Safe proposal: ", name, " on ", _chainLabel(shortName)));
        message.addHeader(string.concat(unicode"🔐 Safe proposal — ", name));
        message.addFields(_summaryFields(safe, proposer, nonce, transactions.length, shortName));
        message.addSection(_callsSection(transactions));
        message.addDivider();
        message.addSection(_signSection(safe, safeTxHash, relativePath, shortName, appUrl));

        // Logged before sending, and never alongside the webhook URL: the payload is what makes a
        // delivery failure diagnosable after the fact, and the URL is the credential.
        console.log(message.buildPayload());

        AlertOutcome outcome = _postAlert();

        if (outcome == AlertOutcome.Sent) {
            // Not "delivered": `Slack._post` discards the webhook's response, so a 4xx from Slack
            // is indistinguishable here from a message that arrived.
            console.log("Proposal alert sent. Slack's response is not visible to this script, so");
            console.log("confirm the message landed in the channel.");
        } else {
            console.log("Proposal alert NOT sent -- but the proposal above IS queued. Do NOT rerun");
            console.log("the propose target: that would submit the same batch again at the same nonce.");
            console.log("Retry the notification only, or pass the safeTxHash above to signers by hand.");
        }

        return outcome;
    }

    /// @notice Posts the message `_notifySafeProposal` just built.
    /// @dev    The narrow containment boundary. `Slack.send` goes out through `vm.ffi`, which
    ///         reverts outright when the run has no `--ffi` and when `curl` exits non-zero. The
    ///         proposal is already queued by the time this runs, so that revert must not reach the
    ///         caller -- hence the external self-call, which is the only way to `try` an internal
    ///         library call.
    ///
    ///         `virtual` so a test can substitute a transport and assert on what would have been
    ///         sent.
    function _postAlert() internal virtual returns (AlertOutcome) {
        try this.sendPendingAlert() {
            return AlertOutcome.Sent;
        } catch {
            return AlertOutcome.Failed;
        }
    }

    /// @notice Sends the pending alert. Not part of the script's interface.
    /// @dev    `external` only so `_postAlert` can contain a transport that cannot run.
    function sendPendingAlert() external {
        if (msg.sender != address(this)) revert NotSelfCall();

        _pendingAlert().send();
    }

    /// @dev The message `_notifySafeProposal` built, which is the one `sendPendingAlert` sends.
    function _pendingAlert() internal view returns (Slack.Message storage) {
        return slackClient.messages[slackClient.messages.length - 1];
    }

    /* ============ Message content ============ */

    /// @dev The nonce is the one the proposal was built against and is now claimed by it. Queuing
    ///      does not advance the Safe's on-chain nonce, so this is what a signer will see pending.
    function _summaryFields(
        address safe,
        address proposer,
        uint256 nonce,
        uint256 transactionCount,
        string memory shortName
    ) internal view returns (string[] memory fields) {
        fields = new string[](6);

        fields[0] = string.concat("*Chain*\n", _chainLabel(shortName));
        fields[1] = string.concat("*Safe*\n`", vm.toString(safe), "`");
        fields[2] = string.concat("*Nonce*\n", vm.toString(nonce));
        fields[3] = string.concat("*Proposer*\n`", vm.toString(proposer), "`");
        // The whole batch is one Safe transaction routed through MultiSend, which the Safe delegate
        // calls; the calls inside it are plain calls.
        fields[4] = "*Operation*\nDelegateCall (MultiSend)";
        fields[5] = string.concat("*Calls*\n", vm.toString(transactionCount), " (batched)");
    }

    /// @dev One line per call, target and selector only. Deliberately no ABI decoding -- the alert
    ///      exists to say which contracts are about to be touched and roughly how, and a signer
    ///      verifies the arguments in the Safe UI, not here.
    function _callsSection(Transaction[] memory transactions) internal pure returns (string memory section) {
        section = "*Calls*";

        uint256 listed = transactions.length > MAX_LISTED_TRANSACTIONS ? MAX_LISTED_TRANSACTIONS : transactions.length;

        for (uint256 i; i < listed; ++i) {
            section = string.concat(
                section,
                unicode"\n• `",
                vm.toString(transactions[i].target),
                unicode"` · `",
                _selector(transactions[i].data),
                "`"
            );
        }

        if (transactions.length > listed) {
            section = string.concat(section, "\n_+", vm.toString(transactions.length - listed), " more_");
        }
    }

    /// @dev Renders the `safeTxHash` in full rather than truncated -- a signer's whole job is to
    ///      match this against what their wallet shows, which a shortened hash defeats. The exported
    ///      batch file is named too, so the same wiring can be reviewed offline.
    ///
    ///      The link is built from `SafeAppConfig` rather than from `safe-utils`, which answers a
    ///      different question: whether a transaction service is reachable, not whether a web app
    ///      serves the chain. Monad Testnet has the first and not the second.
    function _signSection(
        address safe,
        bytes32 safeTxHash,
        string memory relativePath,
        string memory shortName,
        string memory appUrl
    ) internal pure returns (string memory section) {
        section = string.concat("*safeTxHash*\n`", vm.toString(safeTxHash), "`");

        if (bytes(shortName).length != 0) {
            string memory safeAddress = vm.toString(safe);

            section = string.concat(
                section,
                "\n<",
                appUrl,
                "/transactions/tx?safe=",
                shortName,
                ":",
                safeAddress,
                "&id=multisig_",
                safeAddress,
                "_",
                vm.toString(safeTxHash),
                unicode"|Review & sign in Safe →>"
            );
        }

        return string.concat(section, "\n_Batch also exported to `", relativePath, "`._");
    }

    function _chainLabel(string memory shortName) internal view returns (string memory) {
        return
            bytes(shortName).length == 0
                ? vm.toString(block.chainid)
                : string.concat(shortName, " (", vm.toString(block.chainid), ")");
    }

    /// @dev First four bytes of the calldata, rendered raw.
    function _selector(bytes memory data) internal pure returns (string memory) {
        if (data.length < 4) return "0x";

        bytes4 selector;

        assembly {
            selector := mload(add(data, 0x20))
        }

        return vm.toString(abi.encodePacked(selector));
    }

    /* ============ Environment ============ */

    /// @notice Whether to queue the batch on the Safe transaction service.
    /// @dev    Off by default, so a propose run stays the offline, network-free operation it has
    ///         always been unless someone asks for more.
    ///
    ///         This and the three below are `virtual` so a test can supply a value without writing
    ///         to the process environment. Forge shares one environment across a whole run and may
    ///         interleave the tests in a suite, which makes an env-var fixture a race.
    function _submitEnabled() internal view virtual returns (bool) {
        return vm.envOr(SAFE_SUBMIT_ENV, false);
    }

    /// @notice Whether this run must not touch the network, matching the repo-wide `DRY_RUN=true`.
    function _dryRun() internal view virtual returns (bool) {
        return vm.envOr(DRY_RUN_ENV, false);
    }

    /// @notice The Safe to queue on. Required for submission; unused by the export.
    function _safeMultisig() internal view virtual returns (address) {
        return vm.envOr(SAFE_MULTISIG_ENV, address(0));
    }

    /// @notice The webhook to post the alert to; empty means the integration is not configured.
    function _alertWebhookUrl() internal view virtual returns (string memory) {
        return vm.envOr(ALERT_WEBHOOK_URL_ENV, string(""));
    }

    /// @notice The key whose signature confirms the proposal to the service, which also identifies
    ///         the proposer.
    /// @dev    Read with `vm.envUint`, not `envOr`: submission cannot proceed without it, and a
    ///         default would mean signing as somebody. Only reached once submission is enabled and
    ///         not dry-run, so an offline export still needs no key at all.
    function _proposerPrivateKey() internal view virtual returns (uint256) {
        return vm.envUint(PRIVATE_KEY_ENV);
    }
}
