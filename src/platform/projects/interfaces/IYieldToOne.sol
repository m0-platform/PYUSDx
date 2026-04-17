// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  PYUSDX Extension where all yield is claimable by a single recipient.
/// @author M0 Labs
interface IYieldToOne {
    /* ============ Events ============ */

    /// @notice Emitted when this contract's excess PYUSDX yield is claimed.
    /// @param  yield The amount of yield claimed.
    event YieldClaimed(uint256 yield);

    /// @notice Emitted when the yield recipient is set.
    /// @param  yieldRecipient The address of the new yield recipient.
    event YieldRecipientSet(address indexed yieldRecipient);

    /* ============ Custom Errors ============ */

    /// @notice Emitted in initializer if Yield Recipient is 0x0.
    error ZeroYieldRecipient();

    /// @notice Emitted in initializer if Yield Recipient Manager is 0x0.
    error ZeroYieldRecipientManager();

    /// @notice Emitted in initializer if Version Manager is 0x0.
    error ZeroVersionManager();

    /// @notice Emitted in initializer if Admin is 0x0.
    error ZeroAdmin();

    /* ============ Interactive Functions ============ */

    /// @notice Claims accrued yield to the yield recipient.
    /// @dev    MUST only be callable by the YIELD_RECIPIENT_MANAGER_ROLE.
    /// @dev    Calls `pyusdx.claimFor(address(this))` to realize pending yield,
    ///         then mints extension tokens for the resulting increase in totalSupply.
    /// @dev    Callable while paused so the admin retains an emergency lever to rotate a
    ///         compromised yield recipient mid-incident via `setYieldRecipient`. The
    ///         freshly minted extension tokens cannot move while paused because transfer,
    ///         wrap, and unwrap all revert, so the supply is economically inert until
    ///         unpause.
    /// @dev    Reverts if the current yield recipient is frozen. Use `setYieldRecipient`
    ///         to rotate to a non-frozen recipient first; that path skips the internal
    ///         claim so the pending yield stays as excess and accrues to the next
    ///         recipient on their first claim.
    function claimYield() external returns (uint256);

    /// @notice Sets the yield recipient.
    /// @dev    MUST only be callable by the YIELD_RECIPIENT_MANAGER_ROLE.
    /// @dev    SHOULD revert if `yieldRecipient` is 0x0.
    /// @dev    SHOULD return early if the `yieldRecipient` is already the actual yield recipient.
    /// @dev    Internally calls `claimYield()` to pay out the outgoing recipient, unless
    ///         the outgoing recipient is frozen. When frozen, the claim is skipped:
    ///         pending PYUSDX yield remains as excess on the extension and is paid to
    ///         the next recipient's first claim. Makes recipient rotation usable as an
    ///         incident-response lever while a compromised recipient is frozen, at the
    ///         cost of the outgoing recipient's pending slice.
    /// @param  yieldRecipient The address of the new yield recipient.
    function setYieldRecipient(address yieldRecipient) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can manage the yield recipient.
    function YIELD_RECIPIENT_MANAGER_ROLE() external view returns (bytes32);

    /// @notice The amount of pending accrued yield from PYUSDX.
    function yield() external view returns (uint256);

    /// @notice The address of the yield recipient.
    function yieldRecipient() external view returns (address);
}
