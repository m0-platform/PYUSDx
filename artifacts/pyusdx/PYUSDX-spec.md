# PYUSDX - Specification

## Overview

PYUSDX is an upgradeable ERC20 non-rebasing token with claimable yield and built-in pausing and compliance functionalities. 

Yield accrues via an ever increasing Earner Index and the tracking of a principal value.

A Yield Manager controls yield distribution and determines which addresses can receive it. The Yield Manager may optionally charge a fee on the yield. 

Yield needs to be explicitly claimed by earners.

---

**Author:** M0 Labs
**License:** BUSL-1.1
**Solidity Version:** 0.8.30

## Inheritance Hierarchy

```
PYUSDX
├── IPYUSDX (interface)
├── ContinuousIndexing
│   └── IContinuousIndexing
├── EarnerManager
│   ├── IEarnerManager
│   └── AccessControlUpgradeable (OpenZeppelin)
├── ERC20ExtendedUpgradeable
│   ├── IERC20Extended
│   └── ERC3009Upgradeable
│       ├── IERC3009
│       └── StatefulERC712Upgradeable
├── ForcedTransferable
│   ├── IForcedTransferable
│   └── AccessControlUpgradeable (OpenZeppelin)
├── Freezable
│   ├── IFreezable
│   └── AccessControlUpgradeable (OpenZeppelin)
└── Pausable
    ├── IPausable
    ├── PausableUpgradeable (OpenZeppelin)
    └── AccessControlUpgradeable (OpenZeppelin)
```

### External Dependencies

- **IMinterGatewayLike** - The Minter Gateway contract

### Libraries

- **Common:** M0 common library 
[https://github.com/m0-foundation/common](https://github.com/m0-foundation/common)
NOTE: openzeppelin-contracts-upgradeable related contract must be imported from common.
- **IndexingMath** - Index-based yield calculations
[https://github.com/m0-foundation/common/blob/main/src/libs/IndexingMath.sol](https://github.com/m0-foundation/common/blob/main/src/libs/IndexingMath.sol)
- **UIntMath** - Safe type conversions
[https://github.com/m0-foundation/common/blob/main/src/libs/UIntMath.sol](https://github.com/m0-foundation/common/blob/main/src/libs/UIntMath.sol)

### **Components**

Components are abstract contracts with specific features inherited by PYUSDX.

- **ContinuousIndexing:** Abstract Continuous Indexing Contract to handle rate/index updates in inheriting contracts
[https://github.com/MZero-Labs/protocol/blob/b42fe5bc13b14202c684f78aaa15be284664834d/src/abstract/ContinuousIndexing.sol](https://github.com/MZero-Labs/protocol/blob/b42fe5bc13b14202c684f78aaa15be284664834d/src/abstract/ContinuousIndexing.sol?plain=1#L1)
- **ERC20ExtendedUpgradeable:** An upgradeable ERC20 token extended with EIP-2612 permits for signed approvals (via EIP-712 and with EIP-1271 and EIP-5267 compatibility)
https://github.com/m0-foundation/common/blob/main/src/ERC20ExtendedUpgradeable.sol
- **ForcedTransferable**: Upgradable contract that provides force transfer functionality
https://github.com/m0-foundation/m-extensions/blob/381237440a0f95d7df95cdb63c87c14aa15c244e/src/components/forcedTransferable/ForcedTransferable.sol?plain=1#L1
- **Freezable**: Upgradeable contract that allows for the freezing of accounts
https://github.com/m0-foundation/m-extensions/blob/381237440a0f95d7df95cdb63c87c14aa15c244e/src/components/freezable/Freezable.sol?plain=1#L1
- **Pausable**:
[https://github.com/m0-foundation/m-extensions/blob/381237440a0f95d7df95cdb63c87c14aa15c244e/src/components/pausable/Pausable.sol?plain=1#L1](https://github.com/m0-foundation/m-extensions/blob/381237440a0f95d7df95cdb63c87c14aa15c244e/src/components/pausable/Pausable.sol?plain=1#L1)

## State Variables

### Immutable Variables

| Name | Type | Description |
| --- | --- | --- |
| `minterGateway`  | `address` | Address of the MinterGateway contract |
| `pyusd`  | `address` | Address of the PYUSD Token contract |

### Mutable Variables

| Name | Type | Description |
| --- | --- | --- |
| `latestIndex`  | `uint128` | The latest updated index |
| `latestUpdateTimestamp` | `uint40` | The latest timestamp when the index was updated |
| `totalEarningPrincipal` | `uint112` | Total principal amount of earning accounts |
| `totalEarningSupply` | `uint240` | Total supply of tokens in earning state |
| `totalNonEarningSupply` | `uint240` | Total supply of tokens not earning yield |

### Internal Mappings

| Name | Type | Description |
| --- | --- | --- |
| `_latestRate`  | `uint32` | The latest updated rate |
| `_accounts` | `mapping(address => Account)` | Account balance and earning state |
| `_claimRecipients` | `mapping(address => address)` | Custom claim recipients per account |

## Structs

### Account

Represents an account's balance and yield earning details.

```solidity
struct Account {
    // First Slot
    bool isEarning;           // Whether the account is actively earning yield
    uint240 balance;          // The present amount of tokens held
    // Second slot
    uint112 earningPrincipal; // The earning principal for yield calculations
    bool hasClaimRecipient;   // Whether the account has an explicit claim recipient
    bool hasEarnerDetails;    // Whether the account has earner details
}
```

## Constructor

### `constructor`

```solidity
constructor(
    address minterGateway,
    address pyusd
) ERC20Extended("PayPal USDX", "PYUSDX", 6)

```

Constructs the PYUSDX contract with all immutable parameters.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `minterGateway` | `address` | Address of the MinterGateway contract |
| `pyusd` | `address` | Address of the PYUSD Token contract |

**Reverts:**

- `ZeroMinterGateway` - If `minterGateway` is zero address
- `ZeroPYUSD` - If `pyusd` is zero address

## Initializer

### `initialize`

```solidity
function initialize(address admin, address earnerManager, address forcedTransferManager, address freezeManager, address pauser) public initializer

```

Initializes the upgradeable PYUSDX contract with role-based access control.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `admin` | `address` | Address of the contract admin |
| `earnerManager` | `address` | Address managing the earners |
| `forcedTransferManager` | `address`  | Address that can force transfer frozen funds |
| `freezeManager` | `address` | Address that can freeze/unfreeze accounts |
| `pauser` | `address` | Address that can pause/unpause the contract |

**Reverts:**

- `ZeroAdmin` - If `admin` is zero address
- `ZeroEarnerManager`  - If `earnerManager` is zero address
- `ZeroForcedTransferManager`  - If `forcedTransferManager` is zero address
- `ZeroFreezeManager`  - If `freezeManager` is zero address
- `ZeroPauser`  - If `pauser` is zero address

**Grants Roles:**

- `DEFAULT_ADMIN_ROLE` to `admin`
- `EARNER_MANAGER_ROLE` to `earnerManager`
- `FORCED_TRANSFER_MANAGER_ROLE` to `forcedTransferManager`
- `FREEZE_MANAGER_ROLE` to `freezeManager`
- `PAUSER_ROLE` to `pauser`

## Core Functions

### `mint`

```solidity
function mint(address account, uint256 amount) external onlyMinterGateway;
```

Mints PYUSDX. Can only be called by MinterGateway.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account receiving the minted PYUSDX |
| `amount` | `uint256` | Amount of PYUSDX to mint (converted to uint240) |

**Modifiers:**

- `onlyMinterGateway` - Ensures caller is the MinterGateway

**Requirements:**

- Contract must not be paused
- `account` must not be frozen
- `amount` must be > 0

**Behavior:**

- Mints `amount` PYUSDX to `recipient`
- If `account` is an earner, adds to earning supply
- If `account` is not an earner, adds to non-earning supply

**Emits:**

- `Transfer(address(0), account, amount)`

### `burn`

```solidity
function burn(address account, uint256 amount) external onlyMinterGateway;
```

Burns PYUSDX. Can only be called by MinterGateway.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account from which PYUSDX is burnt. |
| `amount` | `uint256` | Amount of PYUSDX to burn (converted to uint240) |

**Modifiers:**

- `onlyMinterGateway` - Ensures caller is the MinterGateway

**Requirements:**

- Contract must not be paused
- `account` must not be frozen
- `amount` must be > 0

**Behavior:**

- Burns `amount` PYUSDX from `account`
- If `account` is an earner, subtract from earning supply
- If `account` is not an earner, subtract from non-earning supply

**Emits:**

- `Transfer(account, address(0), amount)`

### `transfer` (inherited from ERC20Extended)

```solidity
function transfer(address recipient_, uint256 amount_) external returns (bool)
```

Standard ERC20 transfer with freezing and pausing checks.

**Requirements:**

- Contract must not be paused
- `msg.sender` must not be frozen
- `recipient_` must not be frozen
- `msg.sender` must have sufficient balance

**Emits:**

- `Transfer(msg.sender, recipient_, amount_)`

**Special Behavior:**

- If sender and recipient have different earning states, affects total supplies
- Updates earning principals when transferring between earners

### `transferFrom` (inherited from ERC20Extended)

```solidity
function transferFrom(address sender_, address recipient_, uint256 amount_) external returns (bool)
```

ERC20 transferFrom with allowance, freezing, and pausing checks.

**Requirements:**

- Contract must not be paused
- `msg.sender` must have sufficient allowance (or infinite)
- `sender_` must not be frozen
- `msg.sender` must not be frozen
- `recipient_` must not be frozen
- `sender_` must have sufficient balance

**Emits:**

- `Transfer(sender_, recipient_, amount_)`
- `Approval(sender_, msg.sender, newAllowance)` (if allowance not infinite)

### `approve` (inherited from ERC20Extended)

```solidity
function approve(address spender_, uint256 amount_) external returns (bool)
```

Approves `spender_` to spend tokens on behalf of caller.

**Requirements:**

- `msg.sender` must not be frozen
- `spender_` must not be frozen

**Emits:**

- `Approval(msg.sender, spender_, amount_)`

## Yield Management

### `claimFor`

```solidity
function claimFor(address account) external returns (uint240 yield)
```

Claims accrued yield for `account`. Anyone can call on behalf of any account.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to claim yield for |

**Returns:**

| Name | Type | Description |
| --- | --- | --- |
| `yield` | `uint240` | Amount of yield claimed |

**Requirements:**

- Contract must not be paused
- `account` must not be frozen
- `account` must be earning
- Accrued yield must be > 0

**Behavior:**

1. Calculates accrued yield based on current index
2. Updates account balance and total earning supply
3. Transfers yield to claim recipient (account or override)
4. Emits events

**Emits:**

- `Claimed(account, claimRecipient, yield)`
- `Transfer(address(0), account, yield)`
- `Transfer(account, claimRecipient, yield)` (if claim recipient differs)

## Earning Control

### `startEarningFor` (single)

```solidity
function startEarningFor(address account) external
```

Starts yield earning for a single account.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to start earning for |

**Requirements:**

- `account` must not be frozen
- `account` must be approved as earner by EarnerManager
- `account` must not already be earning

**Behavior:**

1. Marks account as earning
2. Records earning principal based on current balance and index
3. Moves balance from non-earning to earning supply

**Emits:**

- `StartedEarning(account)`

### `startEarningFor` (batch)

```solidity
function startEarningFor(address[] calldata accounts) external
```

Starts yield earning for multiple accounts.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `accounts` | `address[]` | Accounts to start earning for |

**Requirements:**

- Contract earning must be enabled

**Behavior:**

- Iterates through accounts and calls `_startEarningFor` for each

**Emits:**

- `StartedEarning(account)` for each account successfully started

### `stopEarningFor` (single)

```solidity
function stopEarningFor(address account) external
```

Stops yield earning for a single account. Claims yield first.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to stop earning for |

**Requirements:**

- `account` must be removed as earner by EarnerManager
- `account` must be earning

**Behavior:**

1. Claims all accrued yield for `account`
2. Marks account as not earning
3. Moves balance from earning to non-earning supply

**Emits:**

- `Claimed(account, claimRecipient, yield)` (if yield > 0)
- `StoppedEarning(account)`

### `stopEarningFor` (batch)

```solidity
function stopEarningFor(address[] calldata accounts) external
```

Stops yield earning for multiple accounts.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `accounts` | `address[]` | Accounts to stop earning for |

**Behavior:**

- Iterates through accounts and calls `_stopEarningFor` for each

**Emits:**

- `StoppedEarning(account)` for each account successfully stopped

## Account Management

### `setClaimRecipient`

```solidity
function setClaimRecipient(address claimRecipient) external onlyEarnerManager
```

Sets a custom recipient for the caller's yield claims.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `claimRecipient` | `address` | Address to receive claimed yield (address(0) to clear) |

**Behavior:**

- Updates internal mapping for caller's claim recipient
- Sets `hasClaimRecipient` flag based on whether `claimRecipient` is non-zero

**Emits:**

- `ClaimRecipientSet(msg.sender, claimRecipient)`

## View Functions

### `accruedYieldOf`

```solidity
function accruedYieldOf(address account) public view returns (uint240 yield)
```

Returns the accrued but unclaimed yield for an account.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to query |

**Returns:**

- `yield` - Accrued yield (0 if account not earning)

### `balanceOf`

```solidity
function balanceOf(address account) public view returns (uint256 balance)
```

Returns the token balance of an account (excluding accrued yield).

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to query |

**Returns:**

- `balance` - Current balance (excluding accrued yield)

### `balanceWithYieldOf`

```solidity
function balanceWithYieldOf(address account) external view returns (uint256 balance)
```

Returns the token balance including any accrued yield.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to query |

**Returns:**

- `balance` - Balance plus accrued yield

**Note:** Claiming yield may not result in this balance if yield is redirected to a claim recipient.

### `earningPrincipalOf`

```solidity
function earningPrincipalOf(address account) external view returns (uint112 earningPrincipal)

```

Returns the earning principal of an account.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to query |

**Returns:**

- `earningPrincipal` - Principal amount used for yield calculations

### `claimRecipientFor`

```solidity
function claimRecipientFor(address account) public view returns (address recipient)
```

Returns the recipient of yield claims for an account.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to query |

**Returns:**

- `recipient` - Claim recipient (override if set, otherwise `account`)

**Priority:**

1. Locally set claim recipient
2. Registrar-based override
3. Account itself

### `currentIndex`

```solidity
function currentIndex() public view returns (uint128 index)
```

Returns the current WrappedM index for yield calculations.

**Returns:**

- `index` - Current index

**Code:** [https://github.com/MZero-Labs/protocol/blob/b42fe5bc13b14202c684f78aaa15be284664834d/src/MToken.sol?plain=1#L166-L182](https://github.com/MZero-Labs/protocol/blob/b42fe5bc13b14202c684f78aaa15be284664834d/src/MToken.sol?plain=1#L166-L182)

### `isEarning`

```solidity
function isEarning(address account) external view returns (bool isEarning)
```

Returns whether an account is currently earning yield.

**Parameters:**

| Name | Type | Description |
| --- | --- | --- |
| `account` | `address` | Account to query |

**Returns:**

- `isEarning` - True if account is earning

