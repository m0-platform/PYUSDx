// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { SafeProposerBase } from "../../script/configure/SafeProposerBase.sol";
import { Transaction } from "../../script/libraries/TransactionHelper.sol";

/// @notice Exposes SafeProposerBase's offline batch export for unit testing.
/// @dev    Pinned to export-only, ignoring the environment on purpose. Two reasons, and both are
///         about determinism rather than convenience:
///
///         1. Forge shares one process environment across a whole run and may interleave suites, so
///            a `SAFE_SUBMIT` or `SLACK_WEBHOOK_URL` set by one test would otherwise change what
///            this harness does in another -- including in the rerun suites, which use it only to
///            check that an export was written.
///         2. A developer with a real webhook in `.env` running `forge test --ffi` must not have a
///            unit test post to a live channel, or reach a live transaction service.
///
///         `SafeProposerAlertHarness` is where submission and alerting are exercised, against
///         stand-ins for both.
contract SafeProposerHarness is SafeProposerBase {
    function writeSafeBatch(string memory name, Transaction[] memory transactions) external {
        _writeSafeBatch(name, transactions);
    }

    function _submitEnabled() internal pure override returns (bool) {
        return false;
    }

    function _alertWebhookUrl() internal pure override returns (string memory) {
        return "";
    }
}
