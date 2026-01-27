# Software Design Document: PYUSDX

**Version:** 1.0
**Date:** 2025-01-26
**Status:** Draft
**Author:** Claude (sc-sdd skill)
**Runtime:** EVM (Solidity/Foundry)

---

## 1. Overview

### 1.1 Document Purpose

This document describes the technical design for PYUSDX, an upgradeable, non-rebasing ERC20 token with claimable yield and built-in compliance features. It specifies the architecture, interfaces, invariants, and design patterns required to implement the feature as defined in the PRD.

### 1.2 Design Goals

- **Non-rebasing yield accrual**: Track yield separately from principal via a continuous global index
- **Explicit yield claiming**: Users control when to recognize yield; no auto-compounding
- **Permission-based earning**: Only approved earners can accrue yield on their balances
- **Compliance-ready**: Built-in freezing, forced transfers, and pausing for regulated use cases
- **Upgradeable**: Follow Transparent Proxy pattern for future enhancements
- **Gas-efficient**: Optimize storage layout and minimize unnecessary state updates

### 1.3 Design Non-Goals

- **Automatic yield compounding**: Yield must be explicitly claimed via `claimFor()`
- **On-chain yield tracking**: Yield source is off-chain (e.g., T-bills); only rate/index is tracked
- **Registrar support**: Earner status is managed by EarnerManager only
- **Migratable pattern**: Uses standard OpenZeppelin upgradeable, not custom migration
- **Staking or locking**: No lock-up periods or staking requirements

### 1.4 References

- PRD: `./artifacts/pyusdx/prd.md`
- PYUSDX Specification: `./artifacts/pyusdx/PYUSDX-spec.md`
- EarnerManager Specification: `./artifacts/earnerManager/EarnerManager-spec.md`
- [M0 Wrapped M Token](https://github.com/m0-foundation/wrapped-m-token) - Reference implementation
- [M0 Protocol](https://github.com/MZero-Labs/protocol) - Continuous indexing pattern
- [M0 Common Libraries](https://github.com/m0-foundation/common) - Shared utilities
- [OpenZeppelin Upgrades](https://docs.openzeppelin.com/upgrades) - Upgradeable contract patterns
- [M0 Protocol - ContinuousIndexing.sol](https://github.com/MZero-Labs/protocol/blob/b42fe5bc13b14202c684f78aaa15be284664834d/src/abstract/ContinuousIndexing.sol?plain=1#L1) - Global interest rate index implementation

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ PYUSDX System                                                                        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│  ┌──────────────────┐    ┌──────────────────┐                                      │
│  │  Minter Gateway  │    │  Earner Manager  │                                      │
│  │  (External)      │    │   (Inherited)    │                                      │
│  │                  │    │                  │                                      │
│  │  - mint()        │    │  - setEarnerDetails() │                                      │
│  │  - burn()        │    │                      │                                    │
│  └────────┬─────────┘    └────────┬─────────┘                                      │
│           │                       │                                                  │
│           │ calls                 │ calls                                             │
│           ▼                       ▼                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                           PYUSDX Contract                                    │   │
│  ├─────────────────────────────────────────────────────────────────────────────┤   │
│  │ ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐               │   │
│  │ │ ContinuousIndex │ │   ERC20Extended  │ │   EarnerManager  │               │   │
│  │ │                  │ │                  │ │                  │               │   │
│  │ │ - setRate()      │ │ - transfer()     │ │ - earnerStatus   │               │   │
│  │ │ - rate()         │ │ - transferFrom() │ │ - feeRate        │               │   │
│  │ │ - updateIndex()  │ │                  │ │                  │               │   │
│  │ │ - latestIndex    │ │                  │ │                  │               │   │
│  │ └──────────────────┘ └──────────────────┘ └──────────────────┘               │   │
│  │ ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐               │   │
│  │ │   Freezable      │ │  ForcedTransfer  │ │    Pausable      │               │   │
│  │ │                  │ │                  │ │                  │               │   │
│  │ │ - freeze()       │ │ - forceTransfer()│ │ - pause()        │               │   │
│  │ │ - unfreeze()     │ │                  │ │ - unpause()      │               │   │
│  │ └──────────────────┘ └──────────────────┘ └──────────────────┘               │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                          │                                          │
│                                          │ inherits                                 │
│                                          ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                    M0 Common Libraries (External)                            │   │
│  ├─────────────────────────────────────────────────────────────────────────────┤   │
│  │ - IndexingMath        │ - UIntMath        │ - ERC20ExtendedUpgradeable       │   │
│  │ - AccessControl       │ - PausableUpgrade  │ - Initializable                  │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Overview

| Component | Responsibility | Interactions |
|-----------|---------------|--------------|
| **PYUSDX** | Main token contract; coordinates all components | MinterGateway (mint/burn), setRate (inherited from ContinuousIndexing, via RATE_MANAGER_ROLE), EarnerManager (inherited) |
| **ContinuousIndexing** | Manages yield index and rate updates | Internal rate storage; updates index based on stored rate |
| **ERC20ExtendedUpgradeable** | Standard ERC20 + EIP-2612 (permit) + EIP-3009 (gasless transfer) | External wallets, DEXs, integrators |
| **EarnerManager** | Manages approved earners and fee rates | Admin (via EARNER_MANAGER_ROLE) |
| **Freezable** | Account-level freeze functionality | Freeze Manager (via FREEZE_MANAGER_ROLE) |
| **ForcedTransferable** | Force transfer from frozen accounts | Forced Transfer Manager (via FORCED_TRANSFER_MANAGER_ROLE) |
| **Pausable** | Contract-level pause functionality | Pauser (via PAUSER_ROLE) |
| **Minter Gateway** | External contract that mints/burns PYUSDX | Calls mint/burn on PYUSDX; collateral held by Minter (off-chain or in separate contract) |

### 2.3 Contract Structure

```

                         ┌─────────────────────────────────────┐
                         │          IPYUSDX                    │
                         │  (interface - public API)           │
                         └─────────────────┬───────────────────┘
                                           │ inherits
                                           ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ PYUSDX                                                                               │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐        │
│  │ ContinuousIndexing  │  │ ERC20Extended       │  │ EarnerManager       │        │
│  │                     │  │ Upgradeable         │  │                     │        │
│  │ - updateIndex()    │  │ - transfer()        │  │ - setEarnerDetails()│        │
│  │ - rate()            │  │ - transferFrom()    │  │ - _earnerDetails    │        │
│  │ - _setRate()       │  │                     │  │                     │        │
│  │ - latestIndex       │  │ - permit()          │  │ - earnerStatusFor() │        │
│  │ - _latestRate      │  │ - receiveWithAuth() │  │                     │        │
│  │ - latestUpdateTimestamp │  │                     │  │                     │        │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘        │
│                                                                                     │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐        │
│  │ Freezable           │  │ ForcedTransferable  │  │ Pausable            │        │
│  │                     │  │                     │  │                     │        │
│  │ - freeze()          │  │ - forceTransfer()   │  │ - pause()           │        │
│  │ - unfreeze()        │  │                     │  │ - unpause()         │        │
│  │ - _frozen           │  │                     │  │ - _paused           │        │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘        │
│                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │ PYUSDX Core Implementation                                                   │   │
│  │                                                                             │   │
│  │ - mint() / burn()           (Minter Gateway only)                            │   │
│  │ - claimFor()                (Anyone, on behalf of earner)                    │   │
│  │ - startEarningFor()         (Anyone, for approved earners)                   │   │
│  │ - stopEarningFor()          (Anyone, for removed earners)                    │   │
│  │ - setClaimRecipient()       (Earner Manager only)                            │   │
│  │ - balanceOf() / totalSupply() (Override for earning supply)                  │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
│  State Variables:                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │ Immutable:                         Mutable:                                  │   │
│  │ - minterGateway (address)          - latestIndex (uint128)                   │   │
│  │ - pyusd (address)                  - latestUpdateTimestamp (uint40)          │   │
│  │                                    - totalEarningPrincipal (uint112)         │   │
│  │                                    - totalEarningSupply (uint240)            │   │
│  │                                    - totalNonEarningSupply (uint240)         │   │
│  │                                    - _latestRate (uint32) [ContinuousIndexing] │   │
│  │                                    - rate (uint32) [ContinuousIndexing]        │   │
│  │                                    - _accounts (mapping)                     │   │
│  │                                    - _claimRecipients (mapping)              │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.4 External Dependencies

| Dependency | Type | Purpose | Trust Assumptions |
|------------|------|---------|-------------------|
| **Minter Gateway** | Protocol/Contract | Authorized to mint/burn PYUSDX; collateral held by Minter (off-chain or in separate contract) | Trusted custodian |
| **PYUSD Token** | ERC20 Token | Reference asset; collateral backing PYUSDX | PayPal-issued stablecoin |
| **M0 Common Libraries** | Library | Shared utilities (IndexingMath, UIntMath, base contracts) | Open-source, audited by M0 |
| **M0 EVM Extensions** | Library | ForcedTransferable, Freezable, Pausable components | Open-source, audited by M0 |
| **OpenZeppelin Contracts** | Library | Access control, upgradeable patterns | Industry standard, audited |

---

## 3. Interface Definitions

### 3.1 Primary Interface

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface IPYUSDX {
    /* ============ Errors ============ */

    /// @notice Thrown when minter gateway address is zero
    error ZeroMinterGateway();

    /// @notice Thrown when PYUSD address is zero
    error ZeroPYUSD();

    /* ============ View Functions ============ */

    /// @notice Returns accrued but unclaimed yield
    /// @param account Account to query
    /// @return Accrued yield amount
    function accruedYieldOf(address account) external view returns (uint240);

    /// @notice Returns balance excluding accrued yield
    /// @param account Account to query
    /// @return Current balance
    function balanceOf(address account) external view override returns (uint256);

    /// @notice Returns balance including accrued yield
    /// @param account Account to query
    /// @return Balance plus accrued yield
    function balanceWithYieldOf(address account) external view returns (uint256);

    /// @notice Returns earning principal for yield calculations
    /// @param account Account to query
    /// @return Principal amount
    function earningPrincipalOf(address account) external view returns (uint112);

    /// @notice Returns claim recipient for an account
    /// @param account Account to query
    /// @return Claim recipient (account if not set)
    function claimRecipientFor(address account) external view returns (address);

    /// @notice Returns current yield index
    /// @return Current index value
    function currentIndex() external view returns (uint128);

    /// @notice Returns whether an account is earning
    /// @param account Account to query
    /// @return True if earning
    function isEarning(address account) external view returns (bool);

    /// @notice Returns total supply of tokens in earning state
    /// @return Total earning supply
    function totalEarningSupply() external view returns (uint256);

    /// @notice Returns total supply of tokens not earning
    /// @return Total non-earning supply
    function totalNonEarningSupply() external view returns (uint256);

    /* ============ Interactive Functions ============ */

    /// @notice Mints PYUSDX to an account
    /// @dev Only callable by the Minter Gateway
    /// @param account Recipient of minted tokens
    /// @param amount Amount to mint
    function mint(address account, uint256 amount) external;

    /// @notice Burns PYUSDX from an account
    /// @dev Only callable by the Minter Gateway
    /// @param account Account to burn from
    /// @param amount Amount to burn
    function burn(address account, uint256 amount) external;

    /// @notice Claims accrued yield for an earner
    /// @param account Earner to claim for
    /// @return Amount of yield claimed
    function claimFor(address account) external returns (uint240);

    /// @notice Starts earning for an approved earner
    /// @param account Account to start earning
    function startEarningFor(address account) external;

    /// @notice Starts earning for multiple approved earners
    /// @param accounts Accounts to start earning
    function startEarningFor(address[] calldata accounts) external;

    /// @notice Stops earning for a removed earner
    /// @dev Only callable by the Earner Manager; remaining yield is claimed before stopping earning
    /// @param account Account to stop earning
    function stopEarningFor(address account) external;

    /// @notice Stops earning for multiple removed earners
    /// @dev Only callable by the Earner Manager; remaining yield is claimed before stopping earning
    /// @param accounts Accounts to stop earning
    function stopEarningFor(address[] calldata accounts) external;

    /// @notice Sets claim recipient for an earner
    /// @dev Only callable by the Earner Manager
    /// @param account Earner account
    /// @param claimRecipient Recipient for yield claims (address(0) to clear)
    function setClaimRecipient(address account, address claimRecipient) external;

    /* ============ Events ============ */

    event Claimed(address indexed account, address indexed recipient, uint240 yield);
    event StartedEarning(address indexed account);
    event StoppedEarning(address indexed account);
    event ClaimRecipientSet(address indexed account, address indexed recipient);
}
```

### 3.2 Earner Manager Interface

```solidity
// External interface for EarnerManager contract (inherited by PYUSDX)
interface IEarnerManager {
    /* ============ Errors ============ */

    /// @notice Emitted when no earner manager is set
    error ZeroEarnerManager();

    /// @notice Emitted when the fee rate provided is too high (higher than 100% in basis points)
    error FeeRateTooHigh();

    /// @notice Emitted when setting fee rate to a nonzero value while setting status to false
    error InvalidDetails();

    /// @notice Emitted when the lengths of input arrays do not match
    error ArrayLengthMismatch();

    /// @notice Emitted when the length of an input array is 0
    error ArrayLengthZero();

    /// @notice Emitted when the earner details have already been set by an existing and active admin
    error EarnerDetailsAlreadySet(address account);

    /* ============ View Functions ============ */

    /// @notice The role that can manage earners
    function EARNER_MANAGER_ROLE() external view returns (bytes32);

    /// @notice Returns the earner status for an account
    /// @param account The account being queried
    /// @return Whether the account is an earner
    function earnerStatusFor(address account) external view returns (bool);

    /// @notice Returns the earner statuses for multiple accounts
    /// @param accounts The accounts being queried
    /// @return Whether each account is an earner, respectively
    function earnerStatusesFor(address[] calldata accounts) external view returns (bool[] memory);

    /// @notice Returns the earner details for an account
    /// @param account The account being queried
    /// @return status Whether the account is an earner
    /// @return feeRate The fee rate to be taken from the yield
    /// @return admin The admin who set the details and who will collect the fee
    function getEarnerDetails(address account) external view returns (bool status, uint16 feeRate, address admin);

    /// @notice Returns the earner details for multiple accounts
    /// @param accounts The accounts being queried
    /// @return statuses Whether each account is an earner, respectively
    /// @return feeRates The fee rates to be taken from the yield, respectively
    /// @return admins The admin who set the details and who will collect the fee, respectively
    function getEarnerDetails(
        address[] calldata accounts
    ) external view returns (bool[] memory statuses, uint16[] memory feeRates, address[] memory admins);

    /* ============ Interactive Functions ============ */

    /// @notice Sets earner details
    /// @dev Only callable by the Earner Manager
    /// @param account Account to configure
    /// @param status True to approve as earner, false to remove
    /// @param feeRate Fee rate in basis points (0-10000)
    function setEarnerDetails(address account, bool status, uint16 feeRate) external;

    /// @notice Batch sets earner details
    /// @dev Only callable by the Earner Manager
    /// @param accounts Accounts to configure
    /// @param statuses Earner statuses
    /// @param feeRates Fee rates
    function setEarnerDetails(
        address[] calldata accounts,
        bool[] calldata statuses,
        uint16[] calldata feeRates
    ) external;

    /* ============ Events ============ */

    event EarnerDetailsSet(address indexed account, bool status, address indexed admin, uint16 feeRate);
}
```

### 3.3 Freezable Interface

```solidity
/**
 * @title Freezable interface
 * @author M0 Labs
 */
interface IFreezable {
    /* ============ Events ============ */

    /**
     * @notice Emitted when an account is frozen
     * @param account The address of the frozen account
     * @param timestamp The timestamp at which the account was frozen
     */
    event Frozen(address indexed account, uint256 timestamp);

    /**
     * @notice Emitted when an account is unfrozen
     * @param account The address of the unfrozen account
     * @param timestamp The timestamp at which the account was unfrozen
     */
    event Unfrozen(address indexed account, uint256 timestamp);

    /* ============ Errors ============ */

    /**
     * @notice Emitted when an account is already frozen
     * @param account The address of the frozen account
     */
    error AccountFrozen(address account);

    /**
     * @notice Emitted when an account is not frozen
     * @param account The address of the account that is not frozen
     */
    error AccountNotFrozen(address account);

    /// @notice Emitted if no freeze manager is set
    error ZeroFreezeManager();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Freezes an account
     * @dev MUST only be callable by the FREEZE_MANAGER_ROLE
     * @param account The address of the account to freeze
     */
    function freeze(address account) external;

    /**
     * @notice Freezes multiple accounts
     * @dev MUST only be callable by the FREEZE_MANAGER_ROLE
     * @param accounts The list of addresses to freeze
     */
    function freezeAccounts(address[] calldata accounts) external;

    /**
     * @notice Unfreezes an account
     * @dev MUST only be callable by the FREEZE_MANAGER_ROLE
     * @param account The address of the account to unfreeze
     */
    function unfreeze(address account) external;

    /**
     * @notice Unfreezes multiple accounts
     * @dev MUST only be callable by the FREEZE_MANAGER_ROLE
     * @param accounts The list of addresses to unfreeze
     */
    function unfreezeAccounts(address[] calldata accounts) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can manage the freezelist
    function FREEZE_MANAGER_ROLE() external view returns (bytes32);

    /**
     * @notice Returns whether an account is frozen or not
     * @param account The address of the account to check
     * @return True if the account is frozen, false otherwise
     */
    function isFrozen(address account) external view returns (bool);
}
```

### 3.4 ForcedTransferable Interface

```solidity
interface IForcedTransferable {
    /* ============ Events ============ */

    /**
     * @notice Emitted when tokens are forcefully transferred from a frozen account
     */
    event ForcedTransfer(
        address indexed frozenAccount,
        address indexed recipient,
        address indexed forcedTransferManager,
        uint256 amount
    );

    /* ============ Custom Errors ============ */

    /// @notice Error for zero forced transfer manager address
    error ZeroForcedTransferManager();

    /// @notice Error for array length mismatch
    error ArrayLengthMismatch();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Forcefully transfers tokens from a frozen account to a recipient
     * @dev MUST only be callable by the FORCE_TRANSFER_MANAGER_ROLE
     * @dev SHOULD revert if `frozenAccount` is not frozen
     * @dev SHOULD revert if `recipient` is the zero address
     * @dev SHOULD revert if `amount` exceeds the balance of `frozenAccount`
     * @param frozenAccount The address of the frozen account from which tokens are seized
     * @param recipient     The address receiving the seized tokens
     * @param amount        The amount of tokens to transfer
     */
    function forceTransfer(address frozenAccount, address recipient, uint256 amount) external;

    /**
     * @notice Forcefully transfers tokens from multiple frozen accounts to multiple recipients
     * @dev MUST only be callable by the FORCE_TRANSFER_MANAGER_ROLE
     * @dev SHOULD revert if any `frozenAccount` is not frozen
     * @dev SHOULD revert if array lengths do not match
     * @dev SHOULD revert if any `recipient` is the zero address
     * @dev SHOULD revert if any `amount` exceeds the balance of the corresponding `frozenAccount`
     * @param frozenAccounts The array of frozen accounts from which tokens are seized
     * @param recipients     The array of recipient addresses
     * @param amounts        The array of amounts to transfer for each account
     */
    function forceTransfers(
        address[] calldata frozenAccounts,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can manage force transfers
    function FORCED_TRANSFER_MANAGER_ROLE() external view returns (bytes32);
}
```

### 3.5 Pausable Interface

```solidity
/**
 * @title Pausable interface
 * @author M0 Labs
 */
interface IPausable {
    /* ============ Errors ============ */

    /// @notice Emitted if no pauser is set
    error ZeroPauser();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Pauses the contract
     * @dev Can only be called by an account with the PAUSER_ROLE
     * @dev When paused, wrap/unwrap and transfer of tokens should be disabled
     * @dev Approval should still be enabled to allow users to change their allowances
     */
    function pause() external;

    /**
     * @notice Unpauses the contract
     * @dev Can only be called by an account with the PAUSER_ROLE
     */
    function unpause() external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can pause/unpause the contract
    function PAUSER_ROLE() external view returns (bytes32);
}
```

### 3.6 Minter Gateway Interface

```solidity
// External interface for Minter Gateway contract
interface IMinterGateway {
    /* ============ View Functions ============ */

    /// @notice The role that can mint/burn
    function MINTER_ROLE() external view returns (bytes32);

    /* ============ Interactive Functions ============ */

    /// @notice Mints PYUSDX to recipient
    /// @dev Only callable by the minter
    /// @param recipient Recipient of minted tokens
    /// @param amount Amount to mint
    function mintPYUSDX(address recipient, uint256 amount) external;

    /// @notice Burns PYUSDX from account
    /// @dev Only callable by the minter
    /// @param account Account to burn from
    /// @param amount Amount to burn
    function burnPYUSDX(address account, uint256 amount) external;
}
```

---

## 4. Data Structures

### 4.1 State Variables

```solidity
contract PYUSDX is
    IPYUSDX,
    ContinuousIndexing,
    EarnerManager,
    ERC20ExtendedUpgradeable,
    ForcedTransferable,
    Freezable,
    Pausable
{
    // =====================================================================
    // Immutable Variables (set in constructor)
    // =====================================================================

    /// @notice Address of the Minter Gateway contract
    address public immutable minterGateway;

    /// @notice Address of the PYUSD token contract
    address public immutable pyusd;

    // =====================================================================
    // Mutable Variables
    // =====================================================================

    /// @notice Sum of all earners' principal balances
    uint112 public totalEarningPrincipal;

    /// @notice Total supply of tokens held by earners
    uint240 public totalEarningSupply;

    /// @notice Total supply of tokens held by non-earners
    uint240 public totalNonEarningSupply;

    // =====================================================================
    // Internal Mappings
    // =====================================================================

    /// @notice Per-account balance and earning state
    mapping(address => Account) internal _accounts;

    /// @notice Custom claim recipients per account
    mapping(address => address) internal _claimRecipients;
}
```

### 4.2 Structs

```solidity
/// @notice Represents an account's balance and yield earning details
struct Account {
    // First Slot (32 bytes)
    bool isEarning;           // Whether the account is actively earning yield (1 byte)
    uint240 balance;          // The current token balance (30 bytes)

    // Second Slot (32 bytes)
    uint112 earningPrincipal; // Principal for yield calculations (14 bytes)
    bool hasClaimRecipient;   // Whether account has custom claim recipient (1 byte)
    bool hasEarnerDetails;    // Whether account has earner details set (1 byte)
    // 16 bytes padding for future use
}
```

### 4.3 Storage Layout Considerations

**Slot Allocation:**
- Slot 1: `minterGateway` (address, 20 bytes) + `pyusd` (address, 20 bytes) = 40 bytes → 2 slots needed
- Slot 2-3: Immutable addresses
- Slot 4: `latestIndex` (128 bits) + `latestUpdateTimestamp` (40 bits) + `rate` (32 bits) + `_latestRate` (32 bits) = 232 bits (packed) from ContinuousIndexing
- Slot 5: `totalEarningPrincipal` (112 bits) + padding = 1 slot
- Slot 6: `totalEarningSupply` (240 bits) = 1 slot
- Slot 7: `totalNonEarningSupply` (240 bits) = 1 slot
- Slot 8: role storage from inherited components

**Account Mapping:**
- Each `Account` struct uses exactly 2 storage slots
- First slot: `isEarning` (1 byte) + `balance` (30 bytes)
- Second slot: `earningPrincipal` (14 bytes) + `hasClaimRecipient` (1 byte) + `hasEarnerDetails` (1 byte) + padding (16 bytes)

**Gas Optimization Notes:**
- Use `uint240` for balances (PYUSD has 6 decimals, supports up to ~10^18 tokens)
- Use `uint112` for earning principal (sufficient for PYUSD scale)
- Pack boolean flags with larger uints where possible
- Consider caching storage reads in memory for multi-read operations

---

## 5. Mathematical Invariants

### 5.1 Core Invariants

**Invariant 1: Conservation of Total Supply**

```
totalSupply = totalEarningSupply + totalNonEarningSupply
```

_Description: The sum of earning and non-earning supplies always equals the tracked total supply._

**Invariant 2: Principal Sum**

```
totalEarningPrincipal = Σ(earningPrincipal[i]) for all earners i
```

_Description: The total earning principal must equal the sum of all individual earning principals._

**Invariant 3: Balance Calculation**

```
∀ account:
  if isEarning[account]:
    balanceWithYield = earningPrincipal × currentIndex / PRECISION
    accruedYield = max(0, balanceWithYield - balance)
  else:
    balanceWithYield = balance
    accruedYield = 0
```

_Description: For earners, balance with yield is calculated from principal and index. Non-earners have no accrued yield._

**Invariant 4: Index Monotonicity**

```
∀ t1 < t2: index[t1] ≤ index[t2]
```

_Description: The yield index never decreases; it only increases or stays the same._

**Invariant 5: Principal Consistency**

```
∀ earner:
  when isEarning becomes true: earningPrincipal = balance × PRECISION / currentIndex
```

_Description: When earning starts, principal is set based on current balance and index._

### 5.2 State Transition Constraints

**Constraint 1: Start Earning**

```
Pre-condition:
  - account.isEarning = false
  - earnerStatusFor(account) = true
  - !frozen[account]
  - !paused

Post-condition:
  - account.isEarning = true
  - account.earningPrincipal = account.balance × PRECISION / currentIndex
  - totalEarningPrincipal += account.earningPrincipal
  - totalEarningSupply += account.balance
  - totalNonEarningSupply -= account.balance
```

**Constraint 2: Stop Earning**

```
Pre-condition:
  - account.isEarning = true
  - earnerStatusFor(account) = false

Post-condition:
  - yield claimed (if any)
  - account.isEarning = false
  - account.earningPrincipal = 0
  - totalEarningPrincipal -= old earningPrincipal
  - totalEarningSupply -= account.balance
  - totalNonEarningSupply += account.balance
```

**Constraint 3: Transfer (Earner → Earner)**

```
Pre-condition:
  - sender.isEarning = true
  - recipient.isEarning = true

Post-condition:
  - sender.balance -= amount
  - recipient.balance += amount
  - sender.earningPrincipal -= amount × PRECISION / currentIndex
  - recipient.earningPrincipal += amount × PRECISION / currentIndex
  - totalEarningSupply unchanged
```

**Constraint 4: Transfer (Non-Earner → Non-Earner)**

```
Pre-condition:
  - sender.isEarning = false
  - recipient.isEarning = false

Post-condition:
  - sender.balance -= amount
  - recipient.balance += amount
  - totalNonEarningSupply unchanged
```

**Constraint 5: Transfer (Non-Earner → Earner)**

```
Pre-condition:
  - sender.isEarning = false
  - recipient.isEarning = true

Post-condition:
  - sender.balance -= amount
  - recipient.balance += amount
  - recipient.earningPrincipal += amount × PRECISION / currentIndex
  - totalNonEarningSupply -= amount
  - totalEarningSupply += amount
  - totalEarningPrincipal += amount × PRECISION / currentIndex
```

**Constraint 6: Transfer (Earner → Non-Earner)**

```
Pre-condition:
  - sender.isEarning = true
  - recipient.isEarning = false

Post-condition:
  - sender.balance -= amount
  - recipient.balance += amount
  - sender.earningPrincipal -= amount × PRECISION / currentIndex
  - totalEarningSupply -= amount
  - totalNonEarningSupply += amount
  - totalEarningPrincipal -= amount × PRECISION / currentIndex
```

**Constraint 7: Claim Yield**

```
Pre-condition:
  - account.isEarning = true
  - accruedYield > 0

Post-condition:
  - yield = accruedYield
  - account.balance += yield
  - account.earningPrincipal += yield × PRECISION / currentIndex
  - totalEarningSupply += yield
  - totalEarningPrincipal += yield × PRECISION / currentIndex
```

### 5.3 Economic Invariants

**Invariant: Fee Deduction**

```
when claiming yield with feeRate > 0:
  grossYield = principal × currentIndex / PRECISION - balance
  fee = grossYield × feeRate / 10000
  netYield = grossYield - fee

where:
  feeRate ∈ [0, 10000] (basis points)
```

_Description: Fees are deducted from gross yield; net yield goes to claim recipient, fee goes to fee recipient._

---

## 6. Detailed Design

### 6.1 Mint and Burn Operations

**Purpose:** Enable Minter Gateway to control PYUSDX supply based on PYUSD collateral.

**Flow Diagram:**

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Minter Gateway  │────▶│     PYUSDX      │────▶│   Account State │
│                 │     │    mint()       │     │   Updated       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │ Supply Tracking │
                       │   Updated       │
                       └─────────────────┘
```

**Algorithm/Logic:**

1. **Pre-flight checks:**
   - Verify caller is `minterGateway`
   - Verify contract is not paused
   - Verify recipient is not frozen
   - Verify amount > 0

2. **Mint operation:**
   - Update account balance
   - If recipient is earner: add to `totalEarningSupply`
   - If recipient is not earner: add to `totalNonEarningSupply`
   - Emit `Transfer(address(0), recipient, amount)`

3. **Burn operation (similar):**
   - Verify caller is `minterGateway`
   - Verify contract is not paused
   - Verify account is not frozen
   - Verify sufficient balance
   - Update account balance
   - Adjust supply tracking based on earning status

**Edge Cases:**
- **Recipient is earner but no principal set**: Should not happen if startEarningFor was called correctly. Defensive: treat as non-earner for supply tracking.
- **Amount exceeds uint240**: Revert with overflow error.
- **Mint to zero address**: Revert with standard ERC20 expectation.

### 6.2 Yield Accrual and Indexing

**Purpose:** Track yield accrual via continuous index without rebasing balances.

**Flow Diagram:**

```
┌──────────────────┐     ┌──────────────────┐
│ Rate Manager     │     │   PYUSDX         │
│ sets rate        │────▶│   stores rate    │
│                  │     │   updateIndex()  │
└──────────────────┘     └────────┬─────────┘
                                   │
                                   ▼
                          ┌──────────────────┐
                          │ Calculate Index  │
                          │ newIndex =       │
                          │ oldIndex ×       │
                          │ (1 + rate × Δt)  │
                          └──────────────────┘
```

**Algorithm/Logic:**

1. **updateIndex()** (called before yield-sensitive operations):
   ```solidity
   function updateIndex() internal returns (uint128) {
       uint32 currentRate = rate();

       if (latestUpdateTimestamp == block.timestamp && _latestRate == currentRate) {
           return latestIndex;
       }

       latestIndex = currentIndex();
       _latestRate = currentRate;
       latestUpdateTimestamp = uint40(block.timestamp);

       emit IndexUpdated(latestIndex, currentRate);
       return latestIndex;
   }
   ```

2. **currentIndex()** (view - calculates current index on-the-fly):
   ```solidity
   function currentIndex() public view returns (uint128) {
       unchecked {
           uint256 newIndex = ContinuousIndexingMath.multiplyIndicesDown(
               latestIndex,
               ContinuousIndexingMath.getContinuousIndex(
                   ContinuousIndexingMath.convertFromBasisPoints(_latestRate),
                   uint32(block.timestamp - latestUpdateTimestamp)
               )
           );
           return UIntMath.bound128(newIndex);
       }
   }
   ```

3. **accruedYieldOf(account)**:
   ```solidity
   function accruedYieldOf(address account) public view returns (uint240) {
       if (!_isEarning[account]) return 0;

       Account storage acct = _accounts[account];
       return _getAccruedYield(acct.balance, acct.earningPrincipal, currentIndex());
   }

   function _getAccruedYield(
       uint240 balance_,
       uint112 earningPrincipal_,
       uint128 currentIndex_
   ) internal pure returns (uint240 yield_) {
       uint240 balanceWithYield_ = IndexingMath.getPresentAmountRoundedDown(earningPrincipal_, currentIndex_);

       unchecked {
           return (balanceWithYield_ <= balance_) ? 0 : balanceWithYield_ - balance_;
       }
   }
   ```

**Edge Cases:**
- **Rate changes mid-period**: Index uses linear interpolation; rate changes are applied on next updateIndex() call.
- **First update (latestIndex = 0)**: Initialize index to PRECISION (1e18 or similar).
- **Overflow in index calculation**: Use IndexingMath library with overflow checks.

### 6.3 Set Rate

**Purpose:** Update the yield rate for index calculations.

**Algorithm/Logic:**

1. **setRate(newRate)** (in ContinuousIndexing, inherited by PYUSDX):
   ```solidity
   function setRate(uint32 newRate) external onlyRateManager {
       _setRate(newRate);
   }
   ```

2. **rate()** (public view in ContinuousIndexing):
   ```solidity
   function rate() public view returns (uint32) {
       return _latestRate;
   }
   ```

3. **_setRate(newRate)** (internal in ContinuousIndexing):
   ```solidity
   function _setRate(uint32 newRate) internal {
       if (newRate == rate) return;  // No change, return early
       if (newRate > 10000) revert RateTooHigh();  // Max 100%
       rate = newRate;
       emit RateSet(newRate);
   }
   ```

**Edge Cases:**
- **Rate too high**: Revert with `RateTooHigh()` if > 10000 (100%)
- **Same rate as current**: Return early without event emission
- **Negative rate**: uint32 prevents negative values

### 6.4 Start/Stop Earning

**Purpose:** Transition accounts between earning and non-earning states while maintaining supply invariants.

**Flow Diagram:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                         startEarningFor(account)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │ Check Approval│   │ Calc Principal  │ │ Update State │             │
│  │ earnerStatus │──▶│ balance × P / I │──▶│ isEarning=true│             │
│  └─────────────┘    └─────────────┘    └─────────────┘             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                         stopEarningFor(account)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │ Claim Yield │   │ Clear Principal │ │ Update State │             │
│  │ if accrued  │──▶│ earningPrincipal=0│──▶│ isEarning=false│            │
│  └─────────────┘    └─────────────┘    └─────────────┘             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Algorithm/Logic:**

1. **startEarningFor(account)**:
   - Verify contract is not paused
   - Verify account is not frozen
   - Verify `earnerStatusFor(account) == true`
   - Verify not already earning
   - Call `_updateIndex()` to get current index
   - Calculate principal: `principal = balance × PRECISION / currentIndex`
   - Update account state
   - Adjust supply totals
   - Emit `StartedEarning(account)`

2. **stopEarningFor(account)**:
   - Verify contract is not paused
   - Verify account is earning
   - Verify `earnerStatusFor(account) == false` (removed by EarnerManager)
   - Call `_updateIndex()`
   - If yield accrued, call `claimFor(account)` first
   - Set `earningPrincipal = 0`
   - Adjust supply totals
   - Emit `StoppedEarning(account)`

**Edge Cases:**
- **Starting with zero balance**: Principal set to 0; account marked as earning but generates no yield until balance > 0.
- **Stopping with unclaimed yield**: Automatically claimed before stopping (per user requirement).
- **EarnerManager removes but stop not called**: Account remains earning until someone calls stopEarningFor. This is intentional - permissionless stop after removal.

### 6.5 Claim Yield

**Purpose:** Transfer accrued yield from the "virtual" yield pool to the claim recipient's balance.

**Flow Diagram:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                            claimFor(account)                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │ Calculate Yield ││ Get Recipient │  │ Check Fee    │             │
│  │ accruedYieldOf  │──▶│ claimRecipient│──▶│ feeRate > 0  │             │
│  │ (uses currentIndex())│ │           │  └─────────────┘             │
│  └─────────────┘    └─────────────┘           │                     │
│                           │                  │                     │
│                           │           ┌──────▼──────┐               │
│                           │           │ Deduct Fee   │               │
│                           │           │ fee = gross × R│              │
│                           │           └──────┬──────┘               │
│                           │                  │                     │
│  ┌─────────────┐    ┌────▼──────┐    ┌──────▼──────┐             │
│  │ Update Principal ││ Mint Yield   │  │ Emit Events │             │
│  │ += yield × P / I│◀─│ to recipient │  │ Claimed    │             │
│  └─────────────┘    └─────────────┘    └─────────────┘             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Algorithm/Logic:**

1. **Pre-flight checks:**
   - Verify not paused
   - Verify account not frozen
   - Verify account is earning

2. **Calculate yield:**
   ```solidity
   Account storage acct = _accounts[account];
   uint240 grossYield = _getAccruedYield(acct.balance, acct.earningPrincipal, currentIndex());

   if (grossYield == 0) return 0;
   ```

3. **Apply fee (if configured):**
   ```solidity
   (, uint16 feeRate,) = getEarnerDetails(account);
   uint240 netYield = grossYield;
   uint240 fee = 0;

   if (feeRate > 0) {
       fee = uint240(grossYield * feeRate / 10000);
       netYield = grossYield - fee;
   }
   ```

4. **Distribute yield:**
   - Update account balance: `balance += grossYield`
   - Update principal: `earningPrincipal += grossYield × PRECISION / latestIndex`
   - If fee > 0: transfer fee to fee recipient (could be protocol or Earner Manager)
   - Transfer net yield to claim recipient

5. **Emit events:**
   - `Claimed(account, recipient, netYield)`
   - `Transfer(address(0), account, grossYield)` (to show yield minted)

**Edge Cases:**
- **Claim recipient not set**: Yield transferred to the earner (account) by default
- **Claim when paused**: Revert with `EnforcedPause()` (from OZ `_requireNotPaused()`)
- **Claim with zero yield**: Return 0 (no revert)
- **Fee recipient not set**: Fees go to the Earner Manager admin assigned to the earner.

### 6.6 Transfer Operations

**Purpose:** Move tokens between accounts while maintaining earning principal consistency.

**Flow Diagram:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                      transfer(recipient, amount)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐                                 │
│  │ Pre-flight  │   │ Check State │                                 │
│  │ not frozen  │──▶│ sender/recv │                                 │
│  └─────────────┘    └─────────────┘                                 │
│                           │                                         │
│                           ▼                                         │
│  ┌─────────────┐    ┌─────────────┐                                 │
│  │ Transfer    │   │ Adjust Principals │                            │
│  │ balance     │──▶│ if both earning  │                           │
│  └─────────────┘    └─────────────┘                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Algorithm/Logic:**

1. **Pre-flight checks:**
   - Verify not paused
   - Verify sender not frozen
   - Verify recipient not frozen
   - Verify sufficient balance

2. **Adjust principals (if both earning):**
   ```solidity
   if (_accounts[msg.sender].isEarning && _accounts[recipient].isEarning) {
       uint256 principalAmount = amount * PRECISION / currentIndex();
       _accounts[msg.sender].earningPrincipal -= uint112(principalAmount);
       _accounts[recipient].earningPrincipal += uint112(principalAmount);
   }
   ```

3. **Handle supply tracking:**
   - Case 1: Both earners → No supply change
   - Case 2: Sender earner, recipient non-earner → Move from earning to non-earning
   - Case 3: Sender non-earner, recipient earner → Move from non-earning to earning
   - Case 4: Both non-earners → No supply change

4. **Execute transfer:**
   ```solidity
   _accounts[msg.sender].balance -= uint240(amount);
   _accounts[recipient].balance += uint240(amount);
   emit Transfer(msg.sender, recipient, amount);
   ```

**Edge Cases:**
- **Transfer with unclaimed yield**: Yield stays with sender; principal adjusted mathematically (per user requirement).
- **Transfer to/from frozen account**: Revert with `AccountFrozen()`.
- **Transfer when paused**: Revert with `ContractPaused()`.
- **Principal overflow**: Use UIntMath or check before addition.

### 6.7 Compliance Operations

**Purpose:** Implement freezing, forced transfers, and pausing for regulated use cases.

**Flow Diagram:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Compliance Controls                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │   freeze()      │  │ forceTransfer() │  │    pause()      │     │
│  │                 │  │                 │  │                 │     │
│  │ Blocks:         │  │ Allows transfer │  │ Blocks all      │     │
│  │ - transfer      │  │ from frozen     │  │ state changes   │     │
│  │ - mint          │  │ accounts only   │  │                 │     │
│  │ - burn          │  │                 │  │                 │     │
│  │ - claim         │  │                 │  │                 │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Algorithm/Logic:**

1. **freeze(account)**:
   - Verify caller has `FREEZE_MANAGER_ROLE`
   - Check if not already frozen (return early if frozen)
   - Set `_frozen[account] = true`
   - Emit `Frozen(account)`

2. **unfreeze(account)**:
   - Verify caller has `FREEZE_MANAGER_ROLE`
   - Check if not already unfrozen (return early if unfrozen)
   - Set `_frozen[account] = false`
   - Emit `Unfrozen(account)`

3. **forceTransfer(from, to, amount)**:
   - Verify caller has `FORCED_TRANSFER_MANAGER_ROLE`
   - Verify `from` is frozen (revert if not)
   - Execute transfer bypassing normal freeze check on `from`
   - Emit `ForcedTransfer(from, to, amount)`

4. **pause()** (calls OZ `_pause()`):
   - Only callable by `PAUSER_ROLE`
   - Calls OZ's `_pause()` which handles state check and event emission

5. **unpause()** (calls OZ `_unpause()`):
   - Only callable by `PAUSER_ROLE`
   - Calls OZ's `_unpause()` which handles state check and event emission

**Edge Cases:**
- **Force transfer from non-frozen account**: Revert with `AccountNotFrozen()`.
- **Freeze the zero address**: Technically allowed but meaningless; could add check.
- **Pause while index update pending**: Index update continues to work (pause only blocks user operations).
- **Multiple freeze managers**: All can freeze/unfreeze; last action wins.

### 6.8 State Machine

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Account States                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    ┌──────────────┐                                                          │
│    │  Non-Earner  │◀────────────────────────────────────────────────┐       │
│    │              │                                                   │       │
│    │ - Holds tokens│                                                  │       │
│    │ - No yield   │                                                  │       │
│    └──────┬───────┘                                                  │       │
│           │                                                          │       │
│           │ startEarningFor()                                         │       │
│           │ (earner approved)                                         │       │
│           ▼                                                          │       │
│    ┌──────────────┐                                                  │       │
│    │    Earner    │                                                  │       │
│    │              │                                                  │       │
│    │ - Earning    │◀───── claimFor() ────▶ balance + yield            │       │
│    │ - Principal  │                                                   │       │
│    │              │                                                  │       │
│    └──────┬───────┘                                                  │       │
│           │                                                          │       │
│           │ stopEarningFor()                                         │       │
│           │ (earner removed, yield claimed)                          │       │
│           │                                                          │       │
│           └──────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                            Contract States                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    ┌──────────────┐                                                          │
│    │   ACTIVE     │◀────────────────────────────────────────────────┐       │
│    │              │                                                   │       │
│    │ - All ops    │                                                   │       │
│    │   enabled    │                                                   │       │
│    └──────┬───────┘                                                  │       │
│           │                                                          │       │
│           │ pause()                                                   │       │
│           ▼                                                          │       │
│    ┌──────────────┐                                                  │       │
│    │    PAUSED    │                                                  │       │
│    │              │                                                  │       │
│    │ - No state   │                                                  │       │
│    │   changes    │                                                  │       │
│    └──────┬───────┘                                                  │       │
│           │                                                          │       │
│           │ unpause()                                                │       │
│           │                                                          │       │
│           └──────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Access Control

### 7.1 Roles

| Role | Description | Assignment |
|------|-------------|------------|
| **DEFAULT_ADMIN_ROLE** | Can grant/revoke all roles; full admin access | Deployer; set in `initialize()` |
| **RATE_MANAGER_ROLE** | Can update yield rate via setRate() (inherited from ContinuousIndexing) | Set in `initialize()`; can add multiple managers |
| **EARNER_MANAGER_ROLE** | Can approve/remove earners and set fee rates | Set in `initialize()`; can add multiple managers |
| **FORCED_TRANSFER_MANAGER_ROLE** | Can force transfer from frozen accounts | Set in `initialize()` |
| **FREEZE_MANAGER_ROLE** | Can freeze/unfreeze accounts | Set in `initialize()` |
| **PAUSER_ROLE** | Can pause/unpause contract | Set in `initialize()` |

### 7.2 Permission Matrix

| Function | DEFAULT_ADMIN | RATE_MANAGER | EARNER_MANAGER | FORCED_TRANSFER_MANAGER | FREEZE_MANAGER | PAUSER | Public |
|----------|---------------|--------------|----------------|-------------------------|----------------|--------|--------|
| `mint()` / `burn()` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | Minter Gateway only |
| `setRate()` | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `transfer()` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (if not frozen/paused) |
| `transferFrom()` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (if not frozen/paused) |
| `claimFor()` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (for any earner) |
| `startEarningFor()` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (if approved) |
| `stopEarningFor()` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (if removed) |
| `setClaimRecipient()` | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| `setEarnerDetails()` | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| `freeze()` / `unfreeze()` | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| `forceTransfer()` | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `pause()` / `unpause()` | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| `updateIndex()` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (anyone) |

### 7.3 Access Control Implementation

Roles are handled per abstract contract using M0 extension components:

```solidity
// From IContinuousIndexing
bytes32 public constant RATE_MANAGER_ROLE = keccak256("RATE_MANAGER_ROLE");

// From IEarnerManager
bytes32 public constant EARNER_MANAGER_ROLE = keccak256("EARNER_MANAGER_ROLE");

// From IFreezable
bytes32 public constant FREEZE_MANAGER_ROLE = keccak256("FREEZE_MANAGER_ROLE");

// From IForcedTransferable
bytes32 public constant FORCED_TRANSFER_MANAGER_ROLE = keccak256("FORCED_TRANSFER_MANAGER_ROLE");

// From IPausable
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
```

Each component provides its own access control:
- **ContinuousIndexing**: `onlyRateManager()` modifier for `setRate()`
- **EarnerManager**: `onlyEarnerManager()` modifier for `setEarnerDetails()`, `setClaimRecipient()`
- **Freezable**: `onlyFreezeManager()` role check for `freeze()`, `unfreeze()`, `freezeAccounts()`, `unfreezeAccounts()`
- **ForcedTransferable**: `onlyForcedTransferManager()` role check for `forceTransfer()`, `forceTransfers()`
- **Pausable**: OZ's `whenNotPaused()` modifier and `onlyPauser` role check for `pause()`, `unpause()`

---

## 8. Security Considerations

### 8.1 Threat Model

#### 8.1.1 Assets at Risk

| Asset | Value | Protection Priority |
|-------|-------|---------------------|
| **PYUSD collateral (held by Minter; may be off-chain or on-chain)** | Full backing of PYUSDX supply | High |
| **PYUSDX tokens held by earners** | User funds | High |
| **Accrued but unclaimed yield** | Pending yield payments | Medium |
| **Protocol fees** | Revenue stream | Medium |

#### 8.1.2 Threat Actors

| Actor | Motivation | Capabilities |
|-------|-----------|--------------|
| **Malicious User** | Extract yield, manipulate state, bypass restrictions | Can call public functions, submit transactions |
| **Compromised Admin/Manager** | Drain funds, manipulate rates, freeze accounts | Has privileged access to admin functions |
| **Minter Gateway Compromise** | Mint unlimited PYUSDX without collateral | Can call mint/burn functions |
| **Rate Model Manipulator** | Set artificial rates to extract value | Can call setRate() (inherited from ContinuousIndexing) via RATE_MANAGER_ROLE |

#### 8.1.3 Attack Vectors

**AV-1: Reentrancy on Claim**

- _Description_: Attacker calls `claimFor()` and recursively re-enters before balance/principal updated
- _Impact_: Could drain yield or claim multiple times
- _Mitigation_:
  - Follow checks-effects-interactions pattern
  - Update state before external calls

**AV-2: Index Manipulation**

- _Description_: Attacker manipulates `latestIndex` to increase yield calculation
- _Impact_: False yield accrual, protocol insolvency
- _Mitigation_:
  - Index updated via `updateIndex()` (public function; can be called by anyone)
  - Rate stored in ContinuousIndexing (inherited by PYUSDX); updated only by RATE_MANAGER_ROLE
  - RATE_MANAGER_ROLE controls rate updates

**AV-3: Supply Tracking Corruption**

- _Description_: `totalEarningSupply` vs `totalNonEarningSupply` inconsistent with actual balances
- _Impact_: Incorrect yield calculations, accounting errors
- _Mitigation_:
  - Update supply tracking atomically with balance changes
  - Add invariant checks in tests

**AV-4: Principal Overflow**

- _Description_: `earningPrincipal` exceeds uint112 max
- _Impact_: Panic/overflow, corrupted state
- _Mitigation_:
  - Use Solidity 0.8+ overflow checks
  - Validate bounds before setting principal
  - UIntMath library for conversions

**AV-5: False Earning Status**

- _Description_: EarnerManager incorrectly sets earner status
- _Impact_: Unauthorized yield accrual or denied yield
- _Mitigation_:
  - Each earner can only be configured by one EarnerManager
  - Clear documentation of earner approval process
  - Event logging for all status changes

**AV-6: Upgrade Takeover**

- _Description_: Malicious upgrade drains funds
- _Impact_: Total loss
- _Mitigation_:
  - Edge case with no real mitigation possible in contract
  - Upgrade process enforced via timelock and multi-sig (operational control)

### 8.2 Security Patterns Used

- [x] **Checks-Effects-Interactions**: All state changes before external calls
- [x] **Overflow Protection**: Solidity 0.8+ built-in checks
- [x] **Access Control**: OpenZeppelin AccessControlUpgradeable for all privileged functions
- [x] **Zero Address Checks**: On all critical address parameters (constructor, initialize)
- [x] **Pausable**: Emergency stop for all state-changing operations
- [x] **Freezable**: Account-level emergency stop
- [x] **Immutable critical addresses**: minterGateway, pyusd set once in constructor

### 8.3 Security Assumptions

- **Minter is honest**: Holds PYUSD 1:1 with PYUSDX supply (off-chain or on-chain)
- **Rate Model is accurate**: Reflects true off-chain yield rate
- **Admin/Manager keys are secure**
- **Underlying collateral (PYUSD) is stable**: PayPal-issued stablecoin
- **Upgrade process is controlled**: No unauthorized upgrades can occur
- **Yield source (off-chain) is secure**: T-bills or money market funds generate expected returns

---

## 9. Off-Chain Components

### 9.1 Required Off-Chain Infrastructure

| Component | Purpose | Criticality |
|-----------|---------|-------------|
| **Minter Gateway Service** | Manages PYUSD collateral, triggers mint/burn | Required |
| **Rate Oracle/Updater** | Monitors off-chain yield rate and calls setRate() on PYUSDX (via RATE_MANAGER_ROLE) | Required |
| **Yield Claim Bot** (optional) | Auto-claims yield for users who opt-in | Optional |
| **Monitoring Service** | Tracks index updates, supply consistency, and emits alerts | Recommended |

### 9.2 Keeper/Bot Requirements

**Keeper Function: Rate Updater**

- _Trigger Condition_: Off-chain yield rate changes (e.g., T-bill rate updates)
- _Action_: Call `PYUSDX.setRate(newRate)` (with RATE_MANAGER_ROLE)
- _Frequency_: On rate change (could be daily, weekly, monthly depending on yield source)
- _Failure Impact_: Index becomes stale; yield calculations use outdated rate; users receive incorrect yield
- _Recommended Implementation_:
  - Monitoring service tracks benchmark rate (e.g., SOFR, T-bill rates)
  - Event emission on rate change for transparency

**Keeper Function: Index Updater** (optional)

- _Trigger Condition_: Time elapsed since last update (e.g., daily)
- _Action_: Call any function that triggers `_updateIndex()` (e.g., `claimFor(dummyAddress)` with zero address check)
- _Frequency_: At minimum frequency to keep index accurate (e.g., daily)
- _Failure Impact_: Index may be stale; users can call updateIndex() before claiming to ensure full yield accrual (index is ever-increasing)
- _Note_: Most user operations (claim, transfer, start/stop earning) trigger index update automatically

---

## 10. Best Practices & Patterns

### 10.1 Runtime-Specific Best Practices (EVM/Solidity)

- **Use Solidity 0.8.30+**: Built-in overflow/underflow protection, improved error messages
- **Follow Checks-Effects-Interactions**: Update state before making external calls
- **Prefer `uint240` for balances**: Sufficient for PYUSD scale (6 decimals), saves storage gas
- **Pack struct members efficiently**: Account struct uses exactly 2 slots with minimal padding
- **Use `calldata` for read-only array arguments**: Saves gas on batch operations
- **Cache storage reads in memory**: For variables accessed multiple times in a function
- **Use named returns**: Improves code readability and can optimize gas
- **Emit events for all state changes**: Critical for off-chain monitoring and indexing
- **Use custom errors instead of revert strings**: Saves gas on error paths
- **Implement invariant checks in tests**: Verify supply tracking and principal consistency
- **Use OpenZeppelin upgradeable contracts**: Industry-standard, audited proxy patterns
- **Avoid calling external contracts in loops**: Can cause DoS or unexpected behavior
- **Use `immutable` for constructor-set variables**: Saves gas on every read
- **Validate array lengths in batch functions**: Revert early if lengths don't match
- **Use UIntMath for explicit type conversions**: Clear intent and overflow safety (https://github.com/MZero-Labs/common/blob/e54273e79cbd8a38b2d2b41ca4123f4e671fcc07/src/libs/UIntMath.sol)

### 10.2 Feature-Specific Patterns

**Non-Rebasing Yield Token Pattern:**
- Store principal separately from balance
- Calculate yield on-demand using global index
- Never auto-adjust balances with index
- Claim must be explicit action

**Continuous Indexing Pattern:**
- Index grows monotonically: `index[t] >= index[t-1]`
- Rate changes are linearly interpolated between updates
- Index precision (PRECISION) should be high enough for accurate calculations (e.g., 1e18)
- Update index before any yield-sensitive operation

**Permission-Based Earning Pattern:**
- Separate "token holder" from "earner" status
- Only approved earners can accrue yield
- Earner status managed by designated admin (EarnerManager)
- Supply tracking differentiates earning vs non-earning

**Compliance-First Design:**
- Freeze at account level (can freeze specific users)
- Pause at contract level (global emergency stop)
- Forced transfer from frozen accounts (recovery mechanism)
- All compliance features emit events for transparency

**Fee Collection Pattern:**
- Fee deducted at claim time, not accrual time
- Fee rate set per earner (basis points: 0-10000)
- Fee portion goes to configurable recipient
- Net yield goes to claim recipient (may differ from earner)

### 10.3 Anti-Patterns to Avoid

- **Don't auto-claim yield**: Breaks user control; causes unexpected tax events
- **Don't rebase balances**: Makes integration difficult; confusing UX
- **Don't skip index update**: Always call `updateIndex()` before yield calculations
- **Don't forget to update supply tracking**: Must track earning vs non-earning supply
- **Don't allow setting claim recipient to zero address**: Should revert, not clear
- **Don't use `transfer()` / `transferFrom()` for fee distribution**: Use low-level call with proper error handling
- **Don't ignore return values from external calls**: Always check success
- **Don't use `block.timestamp` for critical logic**: Can be manipulated by miners (use for rate calculation only, where slight manipulation is acceptable)
- **Don't allow overflow in principal calculations**: Always validate bounds
- **Don't mix earning and non-earning in batch operations**: Handle each account's state correctly
- **Don't forget to emit events**: Critical for monitoring and off-chain systems

---

## 11. Testing Strategy Guidance

### 11.1 Critical Test Scenarios

| Scenario | Type | Priority |
|----------|------|----------|
| **Mint and burn operations** | Unit | High |
| **Start earning flow** | Unit | High |
| **Stop earning flow with claim** | Unit | High |
| **Claim yield with fee deduction** | Unit | High |
| **Transfer between earners** | Unit | High |
| **Transfer earner to non-earner** | Unit | High |
| **Transfer non-earner to earner** | Unit | High |
| **Force transfer from frozen account** | Integration | High |
| **Freeze/unfreeze account** | Unit | Medium |
| **Pause/unpause contract** | Unit | Medium |
| **Index update with rate change** | Unit | High |
| **Set claim recipient** | Unit | Medium |
| **Batch operations (start/stop earning)** | Unit | Medium |
| **Set earner details** | Unit | Medium |
| **Reentrancy on claim** | Fuzz | High |
| **Supply consistency** | Invariant | High |
| **Principal consistency** | Invariant | High |
| **Overflow/underflow protection** | Fuzz | High |

### 11.2 Invariant Testing

**Invariant 1: Total Supply Consistency**
```solidity
// Invariant: totalSupply == totalEarningSupply + totalNonEarningSupply
function invariant_totalSupplyConsistency() public {
    assertEq(
        pyusdx.totalSupply(),
        pyusdx.totalEarningSupply() + pyusdx.totalNonEarningSupply()
    );
}
```

**Invariant 2: Principal Sum**
```solidity
// Invariant: totalEarningPrincipal == sum of all earning principals
function invariant_principalSum() public {
    uint256 sum = 0;
    address[] memory earners = getEarners();
    for (uint i = 0; i < earners.length; i++) {
        sum += pyusdx.earningPrincipalOf(earners[i]);
    }
    assertEq(pyusdx.totalEarningPrincipal(), sum);
}
```

**Invariant 3: Index Monotonicity**
```solidity
// Invariant: index never decreases
uint128 private lastIndex;

function invariant_indexMonotonicity() public {
    assert(pyusdx.currentIndex() >= lastIndex);
    lastIndex = pyusdx.currentIndex();
}
```

**Invariant 4: Balance Calculation**
```solidity
// Invariant: balanceWithYield == balance + accruedYield
function invariant_balanceCalculation(address account) public {
    if (pyusdx.isEarning(account)) {
        assertEq(
            pyusdx.balanceWithYieldOf(account),
            pyusdx.balanceOf(account) + pyusdx.accruedYieldOf(account)
        );
    } else {
        assertEq(pyusdx.accruedYieldOf(account), 0);
    }
}
```

### 11.3 Edge Cases to Test

- **Start earning with zero balance**: Principal should be 0
- **Claim with zero yield**: Should revert
- **Transfer entire balance**: Should clear balance and principal correctly
- **Stop earning immediately after starting**: Should handle gracefully
- **Multiple rate changes before claim**: Index should compound correctly
- **Fee rate of 100%**: User should receive 0 yield
- **Fee rate of 0%**: Full yield to user
- **Batch operations with one failure**: Should handle gracefully or revert all
- **Freeze and unfreeze same account in same transaction**: Should work
- **Pause during pending claim**: Claim should revert
- **Maximum uint240 balance**: Should handle without overflow
- **Principal at uint112 max**: Should handle correctly

### 11.4 Test Organization

**Organize by Type, Not Per-Scenario**

Tests should be organized by test type, not by individual scenarios:

- **Unit tests**: `PYUSDXUnit.t.sol` - Test individual functions in isolation (mint, burn, claim, transfer, etc.)
- **Integration tests**: `PYUSDXIntegration.t.sol` - Test contract interactions and multi-step flows (mint → earn → claim → transfer)
- **Fuzz tests**: `PYUSDXFuzz.t.sol` - Property-based testing with random inputs (reentrancy, overflow, boundary conditions)
- **Invariant tests**: `PYUSDXInvariants.t.sol` - Test system-wide invariants (supply consistency, principal sums, index monotonicity)

**Rationale:**
- Grouping by type reduces test suite overhead (setup/teardown shared)
- Easier to run specific test categories (e.g., only fuzz tests for CI)
- Clearer separation of concerns between unit, integration, and property testing
- Aligns with Foundry's test conventions

---

## 12. Open Design Questions

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | Should claim recipient be per-account or global? | Per-account, Global, Hybrid | **Per-account** (as specified) - allows flexibility for different fee structures |
| 2 | Should there be a minimum claim amount? | No minimum, 1e6 (1 PYUSD), Configurable | **No minimum** - adds complexity for minimal benefit; users can optimize their own gas |
| 3 | Should updateIndex() be callable by anyone or restricted? | Anyone, Admin only, Keepers only | **Anyone** - enables permissionless operation; gas paid by caller benefits protocol |
| 4 | Should we implement a "warm-up" period for new earners? | Immediate earning, 1-day delay, Configurable | **Immediate earning** - per user requirement for immediate removal |
| 5 | How to protect against rate manipulation? | Trust, Add timelock, Multi-sig, Circuit breaker | **Multi-sig + timelock** on RATE_MANAGER_ROLE for rate changes; critical for security |
| 6 | Should totalSupply() include virtual yield? | No (balance only), Yes (balance + yield) | **No** - totalSupply reflects actual minted tokens; balanceWithYieldOf for individual view |

---

## 13. Appendix

### A. Glossary

| Term | Definition |
|------|------------|
| **PYUSD** | PayPal USD stablecoin (6 decimals) |
| **PYUSDX** | Yield-bearing ERC20 token backed by PYUSD collateral |
| **Earner** | Token holder approved to receive yield on their balance |
| **Principal** | Original balance amount stored separately from total balance; used for yield calculations; does NOT include claimed yield |
| **Index** | Global increasing value representing cumulative yield multiplier; current balance = principal × index / PRECISION |
| **Rate** | Yield rate (e.g., 4% annual) stored in ContinuousIndexing (inherited by PYUSDX); updated by RATE_MANAGER_ROLE |
| **Claim Recipient** | Address that receives claimed yield; may differ from earner; set by Earner Manager |
| **Non-rebasing** | Token balances don't auto-adjust with index; principal stays constant; yield is claimed separately |
| **PRECISION** | Scaling factor for index calculations (typically 1e18) |
| **Continuous Indexing** | Pattern where index grows continuously based on rate and time |
| **Minter Gateway** | External contract authorized to mint and burn PYUSDX; Minter holds PYUSD collateral (off-chain or on-chain) |

### B. External References

- [M0 Wrapped M Token](https://github.com/m0-foundation/wrapped-m-token) - Reference implementation for non-rebasing tokens
- [M0 Protocol](https://github.com/MZero-Labs/protocol) - Continuous indexing pattern and EarnerRateModel
- [M0 Common Libraries](https://github.com/m0-foundation/common) - IndexingMath, UIntMath, ERC20ExtendedUpgradeable
- [M0 M-Extensions](https://github.com/m0-foundation/m-extensions) - Freezable, ForcedTransferable, Pausable components
- [OpenZeppelin Upgrades](https://docs.openzeppelin.com/upgrades) - Transparent proxy pattern documentation
- [The Transparent Proxy Pattern](https://www.openzeppelin.com/news/the-transparent-proxy-pattern) - Detailed explanation
- [Upgradeable Proxy Security Best Practices](https://www.certik.com/resources/blog/upgradeable-proxy-contract-security-best-practices) - CertiK security guidance
- [M0 Protocol - ContinuousIndexing.sol](https://github.com/MZero-Labs/protocol/blob/b42fe5bc13b14202c684f78aaa15be284664834d/src/abstract/ContinuousIndexing.sol?plain=1#L1) - Global interest rate index implementation
- [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) - Permit standard for gasless approvals
- [ERC-3009](https://eips.ethereum.org/EIPS/eip-3009) - Gasless transfers via EIP-712 signatures

### C. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-26 | Claude (sc-sdd skill) | Initial design based on PRD and specifications |

---
