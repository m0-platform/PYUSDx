// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Slack } from "../../lib/foundry-slack/src/Slack.sol";
import { Safe } from "../../lib/safe-utils/src/Safe.sol";

import { SafeProposerBase } from "../../script/configure/SafeProposerBase.sol";
import { Transaction } from "../../script/libraries/TransactionHelper.sol";

/// @notice Exposes `SafeProposerBase`'s submission and alert paths for unit testing, and substitutes
///         both library-facing seams so no test can queue a real proposal or send a real alert.
/// @dev    The two seams are exactly where `safe-utils` and `foundry-slack` are called:
///         `_submitSafeProposal` wraps `Safe.proposeTransactions`, `_postAlert` wraps `Slack.send`.
///         Overriding them records what would have gone out and lets a test drive acceptance,
///         rejection and a failing notification without a network.
///
///         `setUseRealAlertTransport(true)` opts one test back into the production containment
///         boundary, to prove a transport that cannot run is contained rather than fatal.
contract SafeProposerAlertHarness is SafeProposerBase {
    using Slack for Slack.Message;

    struct SubmittedProposal {
        address safe;
        address proposer;
        uint256 transactionCount;
    }

    string[] internal _recordedPayloads;

    SubmittedProposal[] internal _submittedProposals;

    bool internal _confirmBatch = true;

    bool internal _useRealAlertTransport;

    AlertOutcome internal _postOutcome = AlertOutcome.Sent;

    bool internal _useEnvironment;

    bool internal _submit;

    bool internal _dryRunOverride;

    string internal _webhookUrl;

    address internal _safe;

    uint256 internal _privateKey = 0xA11CE;

    /// @dev The nonce the stand-in service reports the proposal claimed.
    uint256 internal _nonce = 7;

    /// @dev When set, the stand-in service rejects the proposal with this message instead of
    ///      accepting it, standing in for `Safe.ProposeTransactionFailed`.
    string internal _rejectionReason;

    /* ============ Exposed internals ============ */

    function writeSafeBatch(string memory name, Transaction[] memory transactions) external {
        _writeSafeBatch(name, transactions);
    }

    /* ============ Test configuration ============ */

    /// @notice Withholds export confirmation, standing in for a write that did not land.
    function setConfirmBatch(bool confirmBatch) external {
        _confirmBatch = confirmBatch;
    }

    function setPostOutcome(AlertOutcome outcome) external {
        _postOutcome = outcome;
    }

    /// @notice Makes the stand-in transaction service reject the proposal.
    function setRejectionReason(string memory reason) external {
        _rejectionReason = reason;
    }

    function setNonce(uint256 nonce) external {
        _nonce = nonce;
    }

    function setSubmit(bool submit) external {
        _submit = submit;
    }

    function setDryRun(bool dryRun) external {
        _dryRunOverride = dryRun;
    }

    function setWebhookUrl(string memory webhookUrl) external {
        _webhookUrl = webhookUrl;
    }

    function setSafe(address safe) external {
        _safe = safe;
    }

    function setPrivateKey(uint256 privateKey) external {
        _privateKey = privateKey;
    }

    function proposer() external view returns (address) {
        return vm.addr(_privateKey);
    }

    /// @notice Reads every setting from the process environment instead of from this harness.
    function setUseEnvironment(bool useEnvironment) external {
        _useEnvironment = useEnvironment;
    }

    /// @notice Uses the production containment boundary for the alert.
    /// @dev    There is deliberately no equivalent for the submission seam. Pointing that at a
    ///         stand-in Safe would still address Safe's real transaction service, and this repo's
    ///         tests must never issue a real proposal.
    function setUseRealAlertTransport(bool useRealAlertTransport) external {
        _useRealAlertTransport = useRealAlertTransport;
    }

    /* ============ Records ============ */

    function recordedAlertCount() external view returns (uint256) {
        return _recordedPayloads.length;
    }

    function recordedPayload(uint256 index) external view returns (string memory) {
        return _recordedPayloads[index];
    }

    /// @notice The webhook the pending message was built against.
    function pendingWebhookUrl() external view returns (string memory) {
        return _pendingAlert().webhookUrl;
    }

    function submittedProposalCount() external view returns (uint256) {
        return _submittedProposals.length;
    }

    function submittedProposal(uint256 index) external view returns (SubmittedProposal memory) {
        return _submittedProposals[index];
    }

    /// @notice The digest the stand-in service reports for a batch, so a test can assert the alert
    ///         carries the hash the submission produced.
    function expectedSafeTxHash(Transaction[] memory transactions) external view returns (bytes32) {
        return _safeTxHash(transactions);
    }

    /* ============ Exposed library boundary ============ */

    /// @notice `MAX_LISTED_TRANSACTIONS`, which an external test cannot read directly.
    function maxListedTransactions() external pure returns (uint256) {
        return MAX_LISTED_TRANSACTIONS;
    }

    /// @notice The `MultiSendCallOnly` `safe-utils` would batch a chain's proposal through.
    /// @dev    Exposed because the lookup takes a `Safe.Client` in storage, which a library-level
    ///         test has no way to supply.
    function multiSendCallOnly(uint256 chainId) external view returns (address) {
        return address(Safe.getMultiSendCallOnly(safeClient, chainId));
    }

    /// @notice The transaction service slug `safe-utils` resolves for a chain.
    /// @dev    Exposed so a test can assert the revert on an unserved chain, which `vm.expectRevert`
    ///         cannot see when the library call shares the test's own frame.
    function networkShortName(uint256 chainId) external pure returns (string memory) {
        return Safe.getNetworkShortName(chainId);
    }

    /* ============ Overrides ============ */

    function _submitEnabled() internal view override returns (bool) {
        return _useEnvironment ? super._submitEnabled() : _submit;
    }

    function _dryRun() internal view override returns (bool) {
        return _useEnvironment ? super._dryRun() : _dryRunOverride;
    }

    function _safeMultisig() internal view override returns (address) {
        return _useEnvironment ? super._safeMultisig() : _safe;
    }

    function _alertWebhookUrl() internal view override returns (string memory) {
        return _useEnvironment ? super._alertWebhookUrl() : _webhookUrl;
    }

    function _proposerPrivateKey() internal view override returns (uint256) {
        return _useEnvironment ? super._proposerPrivateKey() : _privateKey;
    }

    function _confirmSafeBatch(string memory path, string memory json) internal override returns (bool) {
        if (!_confirmBatch) return false;

        return super._confirmSafeBatch(path, json);
    }

    /// @dev Records the attempt before deciding the outcome, so a rejected submission is still
    ///      counted -- which is what makes "rejected, and not retried" assertable.
    ///
    ///      Rejection reverts, exactly as `Safe.proposeTransactions` does on a non-2xx answer.
    function _submitSafeProposal(
        address safe,
        address proposerAddress,
        Transaction[] memory transactions
    ) internal override returns (bytes32 safeTxHash, uint256 nonce) {
        _submittedProposals.push(
            SubmittedProposal({ safe: safe, proposer: proposerAddress, transactionCount: transactions.length })
        );

        if (bytes(_rejectionReason).length != 0) revert(_rejectionReason);

        return (_safeTxHash(transactions), _nonce);
    }

    function _postAlert() internal override returns (AlertOutcome) {
        // Recorded before any dispatch so an attempt is counted even when the transport fails.
        _recordedPayloads.push(_pendingAlert().buildPayload());

        if (_useRealAlertTransport) return super._postAlert();

        return _postOutcome;
    }

    /* ============ Helpers ============ */

    /// @dev Stands in for the digest the Safe returns. The propose path only needs it to be stable
    ///      and to change when the batch does; the real one comes from the Safe over RPC.
    function _safeTxHash(Transaction[] memory transactions) internal view returns (bytes32) {
        return keccak256(abi.encode(_safe, block.chainid, _nonce, abi.encode(transactions)));
    }
}
