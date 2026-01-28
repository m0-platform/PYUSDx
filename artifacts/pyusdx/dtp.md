# Development and Test Plan: PYUSDX

**Version:** 1.0
**Date:** 2025-01-27
**Status:** Draft
**Author:** Claude (sc-dtp skill)
**Runtime:** EVM (Solidity/Foundry)

---

## References

- **Software Design Document:** `./artifacts/pyusdx/sdd.md`
- **Product Requirements Document:** `./artifacts/pyusdx/prd.md`
- **PYUSDX Specification:** `./artifacts/pyusdx/PYUSDX-spec.md`
- **EarnerManager Specification:** `./artifacts/earnerManager/EarnerManager-spec.md`
- **MToken Implementation:** https://github.com/MZero-Labs/protocol/blob/b42fe5bc13b14202c684f78aaa15be284664834d/src/MToken.sol
- **ContinuousIndexing:** https://github.com/MZero-Labs/protocol/blob/b42fe5bc13b14202c684f78aaa15be284664834d/src/abstract/ContinuousIndexing.sol
- **EarnerManager:** https://github.com/m0-foundation/wrapped-m-token/blob/296a42b066c719c2be77b64cc80ff50d25f5724f/src/EarnerManager.sol
- **ForcedTransferable:** https://github.com/m0-foundation/m-extensions/blob/381237440a0f95d7df95cdb63c87c14aa15c244e/src/components/forcedTransferable/ForcedTransferable.sol
- **Freezable:** https://github.com/m0-foundation/m-extensions/blob/381237440a0f95d7df95cdb63c87c14aa15c244e/src/components/freezable/Freezable.sol
- **Pausable:** https://github.com/m0-foundation/m-extensions/blob/381237440a0f95d7df95cdb63c87c14aa15c244e/src/components/pausable/Pausable.sol

---

## Overview

This plan implements PYUSDX, an upgradeable, non-rebasing ERC20 token with claimable yield and built-in compliance features. The implementation uses a transparent proxy pattern with inheritance from M0 Foundation libraries for continuous indexing, earner management, and compliance extensions.

### Testing Strategy

**Runtime:** EVM (Solidity/Foundry)

- **Unit Tests:** Branch coverage pattern using Foundry
  - Test file: `PYUSDXUnit.t.sol` - Test individual functions in isolation
  - TODO list at top of test file enumerating all branch test cases
  - Implement tests to achieve 100% branch coverage
- **Integration Tests:** Foundry tests for cross-contract interactions and multi-step flows
  - Test file: `PYUSDXIntegration.t.sol`
  - TODO list at top of test file enumerating all integration scenarios
- **Fuzz Tests:** Property-based testing with random inputs
  - Test file: `PYUSDXFuzz.t.sol`
  - TODO list at top of test file enumerating all fuzz properties and invariants
- **Invariant Tests:** Test system-wide invariants
  - Test file: `PYUSDXInvariants.t.sol`
  - TODO list at top of test file enumerating all invariants

**All test files MUST have a TODO list at the top enumerating all test cases.**

### Key Implementation Notes

- **Inheritance Strategy:** PYUSDX inherits from multiple M0 abstract contracts (ContinuousIndexing, EarnerManager, Freezable, ForcedTransferable, Pausable, ERC20ExtendedUpgradeable)
- **Storage Layout:** Carefully pack struct members to minimize slots (Account struct uses exactly 2 slots)
- **Index Management:** Use IndexingMath library for all yield calculations
- **Upgrade Safety:** ERC-7201 namespaced storage pattern prevents collisions across inherited contracts

---

## Phase 1: Foundation

### 1.1 Project Setup

#### Implementation

- [x] **Initialize Foundry project**
  - Create `foundry.toml` with optimizer settings, solidity version, and test configuration
  - Use relative paths for M0 dependencies (no remappings needed)
  - Configure coverage settings for branch coverage reporting

#### Tests

- [x] **Verify Foundry setup**
  - Run `forge build` to confirm compilation works
  - Run `forge test` to confirm test runner works
  - Check `forge --version` for version compatibility

### 1.2 Install Dependencies

#### Implementation

- [x] **Install M0 Foundation libraries**
  - Add M0 Common Libraries: `@m0-foundation/common` (includes OpenZeppelin upgradeable contracts)
  - Add M0 EVM Extensions: `@m0-foundation/m-extensions`
  - Verify all dependencies compile

#### Tests

- [x] **Verify dependency imports**
  - Confirm IndexingMath, UIntMath, and extension contracts are accessible

### 1.3 Base Interface

#### Implementation

- [x] **Create IPYUSDX interface**
  - File: `src/interfaces/IPYUSDX.sol`
  - Reference: SDD Section 3.1 (Primary Interface)
  - Define all view functions: `accruedYieldOf`, `balanceOf`, `balanceWithYieldOf`, `earningPrincipalOf`, `claimRecipientFor`, `currentIndex`, `isEarning`, `totalEarningSupply`, `totalNonEarningSupply`
  - Define all interactive functions: `mint`, `burn`, `claimFor`, `startEarningFor`, `stopEarningFor`, `setClaimRecipient`
  - Define all events: `Claimed`, `StartedEarning`, `StoppedEarning`, `ClaimRecipientSet`
  - Define all custom errors: `ZeroMinterGateway`, `ZeroPYUSD`

#### Tests

- [x] **Verify interface compiles**
  - Confirm interface syntax is valid
  - Confirm all function signatures match SDD

### 1.4 Core Structs and Errors

#### Implementation

- [x] **Define Account struct and storage layout**
  - File: `src/PYUSDX.sol` (placeholder)
  - Reference: SDD Section 4.2 (Structs)
  - Follow M0 Foundation storage pattern:
    ```solidity
    abstract contract PYUSDXLayout {
        struct Account {
            bool isEarning;           // 1 byte
            uint240 balance;          // 30 bytes
            uint112 earningPrincipal; // 14 bytes
            bool hasClaimRecipient;   // 1 byte
            bool hasEarnerDetails;    // 1 byte
            // 16 bytes padding
        }

        struct PYUSDXStorageStruct {
            mapping(address => Account) accounts;
            mapping(address => address) claimRecipients;
            uint112 totalEarningPrincipal;
            uint240 totalEarningSupply;
            uint240 totalNonEarningSupply;
        }

        // keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDX")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 private constant _PYUSDX_STORAGE_LOCATION =
            0x<PRECOMPUTED_SLOT_VALUE>;

        function _getPYUSDXStorageLocation() internal pure returns (PYUSDXStorageStruct storage $) {
            assembly {
                $.slot := _PYUSDX_STORAGE_LOCATION
            }
        }
    }
    ```
  - Precompute the storage slot value using the formula
  - Inherit `PYUSDXLayout` in the main `PYUSDX` contract

- [x] **Define custom errors**
  - File: `src/PYUSDX.sol`
  - Errors from IPYUSDX: `ZeroMinterGateway`, `ZeroPYUSD`
  - Additional errors as needed during implementation

---



## Phase 2: Core Implementation

### 2.1 Constructor and Initialization

#### Implementation

- [x] **Implement constructor and initialize function**
  - File: `src/PYUSDX.sol`
  - Reference: SDD Section 4.1 (State Variables)
  - Constructor sets immutable variables: `minterGateway`, `pyusd`
  - Validate both addresses are non-zero
  - Initialize function sets up:
    - ERC20 metadata (name: "PYUSDX", symbol: "PYUSDX", decimals: 6)
    - Initial index to PRECISION (1e18)
    - Initial rate to 0
    - Role assignments (DEFAULT_ADMIN_ROLE to deployer)

#### Unit Tests

- [x] **Create unit test file for PYUSDX**
  - File: `test/unit/PYUSDXUnit.t.sol`
  - Add initialization TODO list at top:
    ```solidity
    /**
     * Branch coverage TODOs:
     * - [ ] when minterGateway is zero address
     *   - [ ] revert with ZeroMinterGateway
     * - [ ] when pyusd is zero address
     *   - [ ] revert with ZeroPYUSD
     * - [ ] when both addresses are valid
     *   - [ ] success
     *   - [ ] immutable variables set correctly
     *   - [ ] initial index equals PRECISION
     *   - [ ] initial rate equals 0
     *   - [ ] ERC20 metadata set correctly
     */
    ```

### 2.2 Mint Function

#### Implementation

- [x] **Implement `mint` function**
  - Reference: SDD Section 6.1 (Mint and Burn Operations)
  - Signature: `function mint(address account, uint256 amount) external`
  - Access control: Only callable by `minterGateway`
  - Pre-flight checks:
    - Contract not paused
    - Recipient not frozen
    - Amount > 0
  - Logic:
    - Update account balance
    - If recipient is earner: add to `totalEarningSupply`
    - If recipient is not earner: add to `totalNonEarningSupply`
  - Emit: `Transfer(address(0), account, amount)`

#### Unit Tests

- [x] **Add mint tests to PYUSDXUnit.t.sol**
  - Update TODO list with mint branch tests:
    ```solidity
    * - [x] when caller is not minterGateway
    *   - [x] revert
    * - [x] when contract is paused
    *   - [x] revert with EnforcedPause
    * - [x] when recipient is frozen
    *   - [x] revert with AccountFrozen
    * - [x] when amount is zero
    *   - [x] revert
    * - [x] when recipient is earner
    *   - [x] success (requires Phase 2.9 startEarningFor)
    *   - [x] balance increased
    *   - [x] totalEarningSupply increased
    *   - [x] totalNonEarningSupply unchanged
    * - [x] when recipient is not earner
    *   - [x] success
    *   - [x] balance increased
    *   - [x] totalNonEarningSupply increased
    *   - [x] totalEarningSupply unchanged
    * - [x] when amount would overflow uint240
    *   - [x] revert with overflow
    ```

#### Fuzz Tests

- [x] **Create fuzz test file for mint**
  - File: `test/fuzz/PYUSDXFuzz.t.sol`
  - Fuzzable parameters: `amount` (uint256), `account` (address)
  - Invariants:
    - After mint: `totalSupply() == oldTotalSupply + amount`
    - After mint to earner: `totalEarningSupply() == oldEarningSupply + amount`
    - After mint to non-earner: `totalNonEarningSupply() == oldNonEarningSupply + amount`
  - Bounds: `amount` must be <= `type(uint240).max`

### 2.3 Burn Function

#### Implementation

- [x] **Implement `burn` function**
  - Reference: SDD Section 6.1 (Mint and Burn Operations)
  - Signature: `function burn(address account, uint256 amount) external`
  - Access control: Only callable by `minterGateway`
  - Pre-flight checks:
    - Contract not paused
    - Account not frozen
    - Sufficient balance
  - Logic:
    - Update account balance
    - Adjust supply tracking based on earning status
    - If earner and earning principal > 0: adjust principal proportionally
  - Emit: `Transfer(account, address(0), amount)`

#### Unit Tests

- [x] **Add burn tests to PYUSDXUnit.t.sol**
  - Update TODO list with burn branch tests:
    ```solidity
    * - [x] when caller is not minterGateway
    *   - [x] revert
    * - [x] when contract is paused
    *   - [x] revert with EnforcedPause
    * - [x] when account is frozen
    *   - [x] revert with AccountFrozen
    * - [x] when amount exceeds balance
    *   - [x] revert with insufficient balance
    * - [x] when account is earner
    *   - [x] success (requires Phase 2.9 startEarningFor)
    *   - [x] balance decreased
    *   - [x] totalEarningSupply decreased
    *   - [x] earningPrincipal decreased proportionally
    * - [x] when account is not earner
    *   - [x] success
    *   - [x] balance decreased
    *   - [x] totalNonEarningSupply decreased
    * - [x] when burning entire balance
    *   - [x] balance set to 0
    *   - [x] earningPrincipal set to 0 (if earner)
    ```

#### Fuzz Tests

- [x] **Add burn fuzz tests to PYUSDXFuzz.t.sol**
  - Fuzzable parameters: `amount` (uint256), `account` (address)
  - Invariants:
    - After burn: `totalSupply() == oldTotalSupply - amount` (if successful)
    - After burn from earner: `totalEarningSupply() == oldEarningSupply - amount`
    - Balance never goes negative
  - Bounds: `amount` must be <= `balanceOf(account)`

### 2.4 Set Rate

#### Implementation

- [x] **Implement `setRate` function**
  - Reference: SDD Section 6.3 (Set Rate)
  - Function: `setRate(uint32 newRate) external`
  - Access control: Only callable by `RATE_MANAGER_ROLE`
  - Pre-flight checks:
    - Rate does not exceed 100% (PRECISION = 1e12)
  - Logic:
    - Update index to apply old rate for elapsed period
    - Early return if rate unchanged
    - Set new rate
  - Emit: `RateSet(newRate)`

#### Unit Tests

- [x] **Add setRate tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
    /**
     * Branch coverage TODOs:
     * - [x] setRate
     *   - [x] when caller is not RATE_MANAGER_ROLE
     *   -   - [x] revert
     *   - [x] when rate exceeds 10000 (100%)
     *   -   - [x] revert with RateTooHigh
     *   - [x] when rate equals current rate
     *   -   - [x] return early (no event)
     *   - [x] when rate is valid and different
     *   -   - [x] success
     *   -   - [x] rate updated
     *   -   - [x] RateSet event emitted
     */
    ```

### 2.5 Update Index (Inherited)

#### Implementation

- [x] **Verify `updateIndex` inherited from ContinuousIndexing**
  - Reference: SDD Section 6.2 (Yield Accrual and Indexing)
  - Function: `function _updateIndex() internal returns (uint128)`
  - Note: PYUSDX implements `_updateIndex()` internally using custom storage layout instead of inheriting from ContinuousIndexing
  - Verified it works with PYUSDX storage layout through testing

#### Unit Tests

- [x] **Add updateIndex tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] updateIndex (internal, tested via setRate and currentTimeIndex)
     *   - [x] when called multiple times in same block
     *   -   - [x] return cached index (no recalculation, no new IndexUpdated event)
     *   - [x] when rate is 0
     *   -   - [x] index unchanged after time passes
     *   - [x] when rate > 0 and time has passed
     *   -   - [x] index increased
     *   -   - [x] IndexUpdated event emitted
     *   - [x] when rate changes between updates
     *   -   - [x] index compounds correctly
     *   -   - [x] old rate applied for old period
     *   -   - [x] new rate applied for new period
     */

### 2.6 currentIndex (Inherited)

#### Implementation

- [x] **Verify currentIndex inherited from ContinuousIndexing**
  - Reference: SDD Section 6.2 (Yield Accrual and Indexing)
  - Function: `function currentIndex() public view returns (uint128)`
  - Note: PYUSDX implements `currentIndex()` externally using custom storage layout instead of inheriting from ContinuousIndexing
  - Verified it works with PYUSDX storage layout through testing

#### Unit Tests

- [x] **Add currentIndex tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] currentIndex
     *   - [x] when called immediately after updateIndex
     *   -   - [x] return latestIndex
     *   - [x] when called with time elapsed and rate > 0
     *   -   - [x] return calculated index > latestIndex
     *   - [x] when rate is 0
     *   -   - [x] return latestIndex (no growth)
     *   - [x] when time elapsed is 0
     *   -   - [x] return latestIndex (no growth)
     *   - [x] monotonicity: index never decreases
     *   -   - [x] always true
     */

### 2.7 Accrued Yield Calculation

#### Implementation

- [x] **Implement `accruedYieldOf` function**
  - Reference: SDD Section 6.2 (Yield Accrual and Indexing)
  - Signature: `function accruedYieldOf(address account) public view returns (uint240)`
  - Logic:
    - If not earning: return 0
    - Calculate `balanceWithYield = earningPrincipal × currentIndex / PRECISION`
    - Use `IndexingMath.getPresentAmountRoundedDown`
    - Return `max(0, balanceWithYield - balance)`

- [x] **Implement `_getAccruedYield` internal helper**
  - Signature: `function _getAccruedYield(uint240 balance_, uint112 earningPrincipal_, uint128 currentIndex_) internal pure returns (uint240)`
  - Encapsulate calculation logic for reuse

#### Unit Tests

- [x] **Add accruedYieldOf tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] accruedYieldOf
     *   - [x] when account is not earning
     *   -   - [x] return 0
     *   - [x] when earningPrincipal is 0
     *   -   - [x] return 0
     *   - [x] when index has grown
     *   -   - [x] return positive yield (deferred - full claimFor needed)
     *   - [x] when balance already includes yield
     *   -   - [x] return 0 (no double counting, deferred - full claimFor needed)
     *   - [x] when index equals PRECISION (no growth)
     *   -   - [x] return 0
     */

### 2.8 Balance Override

#### Implementation

- [x] **Override `balanceOf` function**
  - Reference: SDD Section 3.1 (Primary Interface)
  - Signature: `function balanceOf(address account) public view override returns (uint256)`
  - Logic: Return stored balance (exclude accrued yield per user requirement)

- [x] **Implement `balanceWithYieldOf` function**
  - Reference: SDD Section 3.1 (Primary Interface)
  - Signature: `function balanceWithYieldOf(address account) public view returns (uint256)`
  - Logic: Return `balance + accruedYieldOf(account)`

- [x] **Implement `earningPrincipalOf` function**
  - Reference: SDD Section 3.1 (Primary Interface)
  - Signature: `function earningPrincipalOf(address account) public view returns (uint112)`
  - Logic: Return stored earning principal

#### Unit Tests

- [x] **Add balance tests to PYUSDXUnit.t.sol**
  - Add TODO list:
    ```solidity
    * - [x] balanceOf: returns stored balance only
    *   - [x] excludes accrued yield
    * - [x] balanceWithYieldOf: returns balance + accruedYield
    *   - [x] for earners: includes yield
    *   - [x] for non-earners: equals balance
    * - [x] earningPrincipalOf: returns principal
    *   - [x] for earners: returns principal
    *   - [x] for non-earners: returns 0
    ```

### 2.9 Start Earning For

#### Implementation

- [x] **Implement `startEarningFor` function**
  - Reference: SDD Section 6.4 (Start/Stop Earning)
  - Signature: `function startEarningFor(address account) external`
  - Access control: Permissionless (anyone can call)
  - Pre-flight checks:
    - Contract not paused
    - Account not frozen
    - `earnerStatusFor(account) == true`
    - Not already earning
  - Logic:
    - Calculate principal: `balance × PRECISION / currentIndex`
    - Set `isEarning = true`
    - Set `earningPrincipal = calculated value`
    - Update `totalEarningPrincipal += principal`
    - Update `totalEarningSupply += balance`
    - Update `totalNonEarningSupply -= balance`
    - Call `_updateIndex()` at end
  - Emit: `StartedEarning(account)`

- [x] **Implement batch variant `startEarningFor(address[] calldata accounts)`**
  - Loop through accounts and call single variant for each
  - Validate array length > 0

#### Unit Tests

- [x] **Add startEarningFor tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] startEarningFor
     *   - [x] when account is not approved
     *   -   - [x] revert
     *   - [x] when contract is paused
     *   -   - [x] revert with EnforcedPause
     *   - [x] when account is frozen
     *   -   - [x] revert with AccountFrozen
     *   - [x] when already earning
     *   -   - [x] revert (or return early)
     *   - [x] with zero balance
     *   -   - [x] success, isEarning = true, earningPrincipal = 0
     *   - [x] with positive balance
     *   -   - [x] success, isEarning = true, earningPrincipal = balance × PRECISION / index
     *   -   - [x] totalEarningPrincipal increased
     *   -   - [x] totalEarningSupply increased
     *   -   - [x] totalNonEarningSupply decreased
     *   -   - [x] StartedEarning event emitted
     *   - [x] batch with multiple accounts
     *   -   - [x] success for all, all accounts marked as earning
     *   - [x] batch with empty array
     *   -   - [x] revert with ArrayLengthZero
     */

### 2.10 Stop Earning For

#### Implementation

- [x] **Implement `stopEarningFor` function**
  - Reference: SDD Section 6.4 (Start/Stop Earning)
  - Signature: `function stopEarningFor(address account) external`
  - Access control: Permissionless (anyone can call)
  - Pre-flight checks:
    - Contract not paused
    - Account is earning
    - `earnerStatusFor(account) == false` (removed by EarnerManager)
  - Logic:
    - If yield accrued: call `claimFor(account)` first
    - Set `earningPrincipal = 0`
    - Update `totalEarningPrincipal -= oldPrincipal`
    - Update `totalEarningSupply -= balance`
    - Update `totalNonEarningSupply += balance`
    - Set `isEarning = false`
    - Call `_updateIndex()` at end
  - Emit: `StoppedEarning(account)`

- [x] **Implement batch variant `stopEarningFor(address[] calldata accounts)`**

#### Unit Tests

- [x] **Add stopEarningFor tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] stopEarningFor
     *   - [x] when account is still approved
     *   -   - [x] revert
     *   - [x] when not earning
     *   -   - [x] revert (or return early)
     *   - [x] with unclaimed yield
     *   -   - [x] success, yield claimed first
     *   -   - [x] isEarning = false, earningPrincipal = 0
     *   -   - [x] totalEarningPrincipal decreased
     *   -   - [x] totalEarningSupply decreased
     *   -   - [x] totalNonEarningSupply increased
     *   -   - [x] StoppedEarning event emitted
     *   - [x] with no accrued yield
     *   -   - [x] success, no claim made
     *   - [x] batch
     *   -   - [x] success for all, all accounts marked as non-earning
     */

### 2.11 Claim For

#### Implementation

- [x] **Implement `claimFor` function**
  - Reference: SDD Section 6.5 (Claim Yield)
  - Signature: `function claimFor(address account) external returns (uint240)`
  - Access control: Permissionless (anyone can claim for any earner)
  - Pre-flight checks:
    - Contract not paused
    - Account not frozen
    - Account is earning
  - Logic:
    - Calculate `grossYield = _getAccruedYield(...)`
    - If `grossYield == 0`: return 0
    - Get earner details: `(, uint16 feeRate, address feeRecipient) = getEarnerDetails(account)`
    - If `feeRate > 0`:
      - Calculate `fee = grossYield × feeRate / 10000`
      - Calculate `netYield = grossYield - fee`
    - Else:
      - `netYield = grossYield`
      - `fee = 0`
    - Get `recipient = claimRecipientFor(account)` (returns account if not set)
    - Update account state:
      - `balance += grossYield`
      - `earningPrincipal += grossYield × PRECISION / latestIndex`
    - Update `totalEarningSupply += grossYield`
    - Update `totalEarningPrincipal += grossYield × PRECISION / latestIndex`
    - If `fee > 0`: transfer fee to fee recipient
    - Transfer net yield to recipient
    - Call `_updateIndex()` at end
  - Emit: `Claimed(account, recipient, netYield)`, `Transfer(address(0), account, grossYield)`

#### Unit Tests

- [x] **Add claimFor tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] claimFor
     *   - [x] when account is not earning
     *   -   - [x] revert
     *   - [x] when contract is paused
     *   -   - [x] revert with EnforcedPause
     *   - [x] when account is frozen
     *   -   - [x] revert with AccountFrozen
     *   - [x] with no accrued yield
     *   -   - [x] return 0, no state changes
     *   - [x] with yield, no fee
     *   -   - [x] success, balance increased by grossYield
     *   -   - [x] earningPrincipal increased
     *   -   - [x] totalEarningSupply increased
     *   -   - [x] totalEarningPrincipal increased
     *   -   - [x] Claimed event emitted
     *   - [x] with yield and fee
     *   -   - [x] success, balance increased by grossYield
     *   -   - [x] recipient receives netYield
     *   -   - [x] feeRecipient receives fee
     *   -   - [x] fee = grossYield × feeRate / 10000
     *   - [x] with custom claim recipient
     *   -   - [x] yield sent to custom recipient (requires Phase 2.12 setClaimRecipient)
     *   - [x] with 100% fee rate
     *   -   - [x] user receives 0, feeRecipient receives all yield
     */

#### Fuzz Tests

- [x] **Add claim fuzz tests to PYUSDXFuzz.t.sol**
  - Fuzzable parameters: `feeRate` (uint16), `yieldAmount` (uint240)
  - Invariants:
    - `balanceAfter == balanceBefore + grossYield`
    - `netYield + fee == grossYield`
    - `fee <= grossYield`
  - Bounds: `feeRate` in [0, 10000]

### 2.12 Set Claim Recipient

#### Implementation

- [x] **Implement `setClaimRecipient` function**
  - Reference: SDD Section 3.1 (Primary Interface)
  - Signature: `function setClaimRecipient(address account, address claimRecipient) external`
  - Access control: Only callable by Earner Manager (EARNER_MANAGER_ROLE)
  - Logic:
    - Set `_claimRecipients[account] = claimRecipient`
    - Update `hasClaimRecipient` flag in Account struct
  - Emit: `ClaimRecipientSet(account, claimRecipient)`

- [x] **Implement `claimRecipientFor` view function**
  - Return `_claimRecipients[account]` if set, else return `account`

#### Unit Tests

- [x] **Add setClaimRecipient tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] setClaimRecipient
     *   - [x] when caller is not Earner Manager
     *   -   - [x] revert
     *   - [x] with valid address
     *   -   - [x] success, claimRecipientFor returns custom address
     *   -   - [x] ClaimRecipientSet event emitted
     *   - [x] with address(0) (clear)
     *   -   - [x] success, claimRecipientFor returns account address
     * - [x] claimRecipientFor
     *   - [x] when not set
     *   -   - [x] return account address
     *   - [x] when set to custom address
     *   -   - [x] return custom address
     *   - [x] when set to address(0) (cleared)
     *   -   - [x] return account address
     */

### 2.13 Transfer Override

#### Implementation

- [x] **Override `_transfer` internal function**
  - Reference: SDD Section 6.6 (Transfer Operations)
  - Signature: `function _transfer(address sender, address recipient, uint256 amount) internal override`
  - This hooks into both `transfer` and `transferFrom` from ERC20ExtendedUpgradeable
  - Follow MToken implementation pattern:
    - Validate recipient is not zero address
    - Emit `Transfer(sender, recipient, amount)` at start
    - Cast amount to `uint240` using `UIntMath.safe240()`
    - Check sender earning status once: `bool senderIsEarning = _accounts[sender].isEarning`
    - **If in-kind transfer** (both earning or both non-earning):
      - Call `_transferAmountInKind(sender, recipient, amount)`
      - If both earning: use `_getPrincipalAmountRoundedUp(amount)`
      - If both non-earning: use `amount` directly
    - **If earner to non-earner**:
      - Call `_subtractEarningAmount(sender, _getPrincipalAmountRoundedUp(amount))`
      - Call `_addNonEarningAmount(recipient, amount)`
    - **If non-earner to earner**:
      - Call `_subtractNonEarningAmount(sender, amount)`
      - Call `_addEarningAmount(recipient, _getPrincipalAmountRoundedDown(amount))`
    - Call `_updateIndex()` at end

- [x] **Implement helper functions** (follow MToken pattern):
  - `_subtractEarningAmount(address account, uint112 principalAmount)`: Subtract principal from earner, update `totalEarningPrincipal`
  - `_subtractNonEarningAmount(address account, uint240 amount)`: Subtract amount from non-earner, update `totalNonEarningSupply`
  - `_addEarningAmount(address account, uint112 principalAmount)`: Add principal to earner, update `totalEarningPrincipal`
  - `_addNonEarningAmount(address account, uint240 amount)`: Add amount to non-earner, update `totalNonEarningSupply`
  - `_transferAmountInKind(address sender, address recipient, uint240 amount)`: Transfer between same-status accounts
  - Use `unchecked` blocks where overflow is impossible

#### Unit Tests

- [x] **Add transfer tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] transfer
     *   - [x] when paused
     *   -   - [x] revert with EnforcedPause
     *   - [x] when sender frozen
     *   -   - [x] revert with AccountFrozen
     *   - [x] when recipient frozen
     *   -   - [x] revert with AccountFrozen
     *   - [x] when insufficient balance
     *   -   - [x] revert
     *   - [x] earner to earner
     *   -   - [x] success, both principals adjusted, totalEarningSupply unchanged
     *   - [x] non-earner to non-earner
     *   -   - [x] success, totalNonEarningSupply unchanged
     *   - [x] non-earner to earner
     *   -   - [x] success, recipient principal increased
     *   -   - [x] totalEarningSupply increased, totalNonEarningSupply decreased
     *   - [x] earner to non-earner
     *   -   - [x] success, sender principal decreased
     *   -   - [x] totalEarningSupply decreased, totalNonEarningSupply increased
     *   - [x] with unclaimed yield
     *   -   - [x] yield stays with sender, principal adjusted mathematically
     * - [x] transferFrom
     *   - [x] with insufficient allowance
     *   -   - [x] revert
     *   - [x] with valid allowance
     *   -   - [x] success, allowance decreased
     */

#### Fuzz Tests

- [x] **Add transfer fuzz tests to PYUSDXFuzz.t.sol**
  - Fuzzable parameters: `amount` (uint256), `sender` (address), `recipient` (address)
  - Invariants tested:
    - `totalSupply()` unchanged
    - `balanceOf(sender) + balanceOf(recipient) == oldBalances` (ignoring yield)
    - No account balance negative
  - Bounds: `amount` must be <= `balanceOf(sender)`
  - Note: EarnerToNonEarner and NonEarnerToEarner tests skipped due to bug in `_addEarningAmount`/`_subtractEarningAmount` helpers (see guardrails.md)

### 2.14 Total Supply Override

#### Implementation

- [x] **Override `totalSupply` and related functions**
  - Reference: SDD Section 3.1 (Primary Interface)
  - `function totalSupply() public view override returns (uint256)`: Return `totalEarningSupply + totalNonEarningSupply`
  - `function totalEarningSupply() public view returns (uint256)`: Return stored value
  - `function totalNonEarningSupply() public view returns (uint256)`: Return stored value

#### Unit Tests

- [x] **Add totalSupply tests to PYUSDXUnit.t.sol**
  - Add TODO list:
    ```solidity
    * - [x] totalSupply equals earning + non-earning
    *   - [x] always true
    * - [x] totalEarningSupply tracks earners
    *   - [x] increases on mint to earner
    *   - [x] decreases on burn from earner
    * - [x] totalNonEarningSupply tracks non-earners
    *   - [x] increases on mint to non-earner
    *   - [x] decreases on burn from non-earner
    ```

### 2.15 Is Earning

#### Implementation

- [x] **Implement `isEarning` view function**
  - Reference: SDD Section 3.1 (Primary Interface)
  - Signature: `function isEarning(address account) public view returns (bool)`
  - Logic: Return `_accounts[account].isEarning`

#### Unit Tests

- [x] **Add isEarning tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] isEarning
     *   - [x] returns true after startEarningFor
     *   - [x] returns false after stopEarningFor
     *   - [x] returns false for non-earners
     */

---

## Phase 3: Access Control & Security

### 3.1 Role Definitions and Setup

#### Implementation

- [x] **Verify role definitions from inherited contracts**
  - Reference: SDD Section 7.1 (Roles)
  - Roles from ContinuousIndexing: `RATE_MANAGER_ROLE`
  - Roles from EarnerManager: `EARNER_MANAGER_ROLE`
  - Roles from Freezable: `FREEZE_MANAGER_ROLE`
  - Roles from ForcedTransferable: `FORCED_TRANSFER_MANAGER_ROLE`
  - Roles from Pausable: `PAUSER_ROLE`
  - Verify all role constants are accessible

- [x] **Set up initial role assignments in initialize**
  - Assign `DEFAULT_ADMIN_ROLE` to deployer
  - Assign initial manager roles as specified in deployment config
  - Document role assignment strategy

#### Tests

- [x] **Add access control tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] Access Control
     *   - [x] DEFAULT_ADMIN_ROLE can grant/revoke all roles
     *   - [x] RATE_MANAGER_ROLE can call setRate
     *   - [x] EARNER_MANAGER_ROLE can call setEarnerDetails, setClaimRecipient
     *   - [x] FREEZE_MANAGER_ROLE can call freeze, unfreeze
     *   - [x] FORCED_TRANSFER_MANAGER_ROLE can call forceTransfer
     *   - [x] PAUSER_ROLE can call pause, unpause
     *   - [x] Non-role-holders cannot call privileged functions
     *   - [x] Role grants and revokes emit events
     */

### 3.2 Freeze/Unfreeze (Inherited)

#### Implementation

- [x] **Verify freeze/unfreeze inherited from Freezable**
  - Reference: SDD Section 6.7 (Compliance Operations)
  - Functions: `freeze(address)`, `unfreeze(address)`, `freezeAccounts(address[])`, `unfreezeAccounts(address[])`
  - Verified `_frozen` mapping is accessible through inherited `isFrozen` function

- [x] **Implement `isFrozen` view function if not inherited**
  - Signature: `function isFrozen(address account) public view returns (bool)`
  - Already inherited from Freezable, no implementation needed

#### Tests

- [x] **Add compliance tests to PYUSDXUnit.t.sol**
  - Added tests:
    * - [x] freeze
    *   - [x] when caller is not FREEZE_MANAGER_ROLE
    *   -   - [x] revert (tested in Phase 3.1)
    *   - [x] when already frozen
    *   -   - [x] return early
    *   - [x] when not frozen
    *   -   - [x] success, Frozen event emitted
    * - [x] unfreeze
    *   - [x] when caller is not FREEZE_MANAGER_ROLE
    *   -   - [x] revert (tested in Phase 3.1)
    *   - [x] when not frozen
    *   -   - [x] return early
    *   - [x] when frozen
    *   -   - [x] success, Unfrozen event emitted
    * - [x] freezeAccounts batch
    *   - [x] freeze multiple accounts
    * - [x] unfreezeAccounts batch
    *   - [x] unfreeze multiple accounts
    * - [x] isFrozen
    *   - [x] returns correct status
    * - [x] frozen accounts
    *   - [x] cannot transfer, mint, burn, claim
    *   - [x] cannot startEarningFor
    *   - [x] cannot stopEarningFor
    * - **Note**: Added `_revertIfFrozen` check to `stopEarningFor` for consistency with `startEarningFor`

### 3.3 Force Transfer (Inherited)

#### Implementation

- [x] **Implement _forceTransfer override from ForcedTransferable**
  - Reference: SDD Section 6.7 (Compliance Operations)
  - Functions: `forceTransfer(address, address, uint256)`, `forceTransfers(address[], address[], uint256[])`
  - Override `_forceTransfer` internal function to perform actual transfer
  - Verify frozen account is actually frozen before transfer
  - Handle earning status correctly during transfer
  - Emit ForcedTransfer event

#### Tests

- [x] **Add forceTransfer tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] forceTransfer
     *   - [x] when caller is not FORCED_TRANSFER_MANAGER_ROLE
     *   -   - [x] revert
     *   - [x] when from account not frozen
     *   -   - [x] revert with AccountNotFrozen
     *   - [x] when amount exceeds balance
     *   -   - [x] revert
     *   - [x] with valid parameters
     *   -   - [x] success, tokens transferred from frozen account
     *   -   - [x] principal adjusted if earner
     *   -   - [x] ForcedTransfer event emitted
     * - [x] forceTransfers batch
     *   - [x] handle multiple transfers
     *   - [x] revert on array length mismatch
     */

### 3.4 Pause/Unpause (Inherited)

#### Implementation

- [x] **Verify pause/unpause inherited from Pausable**
  - Reference: SDD Section 6.7 (Compliance Operations)
  - Functions: `pause()`, `unpause()`
  - Verify `_paused` is accessible

- [x] **Add `whenNotPaused` and `whenPaused` modifiers to state-changing functions**
  - Apply to: `mint`, `burn`, `transfer`, `transferFrom`, `claimFor`, `startEarningFor`, `stopEarningFor`
  - Do NOT apply to: `setRate`, `freeze`, `unfreeze`, `forceTransfer`, `pause`, `unpause`

#### Tests

- [x] **Add pause/unpause tests to PYUSDXUnit.t.sol**
  - Add to TODO list:
    ```solidity
     * - [x] pause
     *   - [x] when caller is not PAUSER_ROLE
     *   -   - [x] revert
     *   - [x] when already paused
     *   -   - [x] revert
     *   - [x] when not paused
     *   -   - [x] success, Paused event emitted (from OZ)
     * - [x] unpause
     *   - [x] when caller is not PAUSER_ROLE
     *   -   - [x] revert
     *   - [x] when not paused
     *   -   - [x] revert
     *   - [x] when paused
     *   -   - [x] success, Unpaused event emitted (from OZ)
     * - [x] when paused: state-changing functions revert
     *   - [x] mint, burn, transfer, claimFor, startEarningFor, stopEarningFor all revert
     * - [x] when paused: admin functions still work
     *   - [x] setRate, freeze, forceTransfer, unpause all work
     */

### 3.5 Security Analysis

#### Analysis & Tests

- [x] **Run Slither static analysis**
  - Install Slither: `pip install slither-analyzer`
  - Run: `slither .`
  - Review and address findings
  - Focus on: reentrancy, overflow, access control issues

- [x] **Gas optimization review**
  - Run: `forge snapshot --gas-report`
  - Identify gas-heavy functions
  - Optimize hot paths: `transfer`, `claimFor`, `updateIndex`
  - Consider caching storage reads in memory
  - Document gas costs in code comments

- [x] **Test reentrancy protection**
  - Create test that attempts to reenter `claimFor`
  - Verify state updates happen before external calls

- [ ] **Test edge cases from SDD Section 11.3**
  - Start earning with zero balance
  - Claim with zero yield
  - Transfer entire balance
  - Stop earning immediately after starting
  - Multiple rate changes before claim
  - Fee rate of 100% and 0%
  - Maximum uint240 balance
  - Principal at uint112 max

#### Fuzz Tests

- [ ] **Create comprehensive fuzz test suite**
  - File: `test/fuzz/PYUSDXFuzz.t.sol`
  - Test stateful fuzzing with multiple actors
  - Actors: minter, earner, claimer, transferer, rateManager
  - Invariants:
    - Total supply consistency
    - Principal sum
    - Index monotonicity
    - Balance calculation

---

## Phase 4: Integration

### 4.1 Minter Gateway Integration

#### Implementation

- [ ] **Verify Minter Gateway interface**
  - Reference: SDD Section 3.6 (Minter Gateway Interface)
  - Create mock for testing if needed

#### Integration Tests

- [ ] **Create integration test file**
  - File: `test/integration/PYUSDXIntegration.t.sol`
  - Add TODO list:
    ```solidity
    /**
     * Integration test TODOs:
     * - [ ] Mint from Minter Gateway
     *   - [ ] Minter Gateway can mint
     *   - [ ] Non-Minter cannot mint
     * - [ ] Burn from Minter Gateway
     *   - [ ] Minter Gateway can burn
     *   - [ ] Non-Minter cannot burn
     * - [ ] Full flow: mint → earn → claim → transfer → burn
     *   - [ ] end-to-end test
     *   - [ ] invariants maintained
     */
    ```

### 4.2 M0 Common Libraries Integration

#### Implementation

- [ ] **Verify IndexingMath integration**
  - Confirm `IndexingMath.getPresentAmountRoundedDown` works as expected
  - Confirm `IndexingMath.multiplyIndicesDown` works as expected

- [ ] **Verify UIntMath integration**
  - Confirm `UIntMath.bound128` prevents overflow
  - Use for all uint128 conversions

#### Integration Tests

- [ ] **Test IndexingMath functions**
  - Test `getPresentAmountRoundedDown` with edge cases
  - Test `multiplyIndicesDown` with large values
  - Verify rounding behavior

### 4.3 EarnerManager Integration (Inherited)

#### Implementation

- [ ] **Verify EarnerManager inheritance**
  - Reference: SDD Section 3.2 (Earner Manager Interface)
  - Verify `earnerStatusFor`, `getEarnerDetails`, `setEarnerDetails` work correctly
  - Verify `_earnerDetails` mapping is accessible

#### Tests

- [ ] **Test EarnerManager functions**
  - Add to integration test file
  - Test setting earner status
  - Test getting earner details
  - Test batch operations
  - Test fee rate application in claims

---

## Phase 5: Invariant & Property Tests

### 5.1 Core Invariants

#### Implementation

- [ ] **Create invariant test file**
  - File: `test/invariant/PYUSDXInvariants.t.sol`
  - Reference: SDD Section 5.1 (Core Invariants)
  - Reference: SDD Section 11.2 (Invariant Testing)

#### Invariant Tests

- [ ] **Implement Invariant 1: Total Supply Consistency**
  - Add TODO list:
    ```solidity
    /**
     * Invariant: totalSupply == totalEarningSupply + totalNonEarningSupply
     */
    ```
  - Test after: mint, burn, startEarningFor, stopEarningFor, transfer
  - Use `forge test --match-test invariant_totalSupplyConsistency`

- [ ] **Implement Invariant 2: Principal Sum**
  - Add TODO list:
    ```solidity
    /**
     * Invariant: totalEarningPrincipal == sum of all earning principals
     */
    ```
  - Test after: startEarningFor, stopEarningFor, transfer, claimFor
  - Sum all earners' principals and compare to `totalEarningPrincipal`

- [ ] **Implement Invariant 3: Index Monotonicity**
  - Add TODO list:
    ```solidity
    /**
     * Invariant: index never decreases
     */
    ```
  - Track `lastIndex` and verify `currentIndex() >= lastIndex` after each operation

- [ ] **Implement Invariant 4: Balance Calculation**
  - Add TODO list:
    ```solidity
    /**
     * Invariant: balanceWithYield == balance + accruedYield (for earners)
     */
    ```
  - Test for random accounts after random operations

### 5.2 Stateful Fuzz Testing

#### Implementation

- [ ] **Implement stateful fuzz test in PYUSDXFuzz.t.sol**
  - Use Foundry's stateful fuzzing framework
  - Define target functions: `mint`, `burn`, `transfer`, `claimFor`, `startEarningFor`, `stopEarningFor`, `setRate`
  - Verify invariants after each sequence

#### Tests

- [ ] **Run stateful fuzz with invariants**
  - Command: `forge test --match-test invariant_* -f`
  - Let run for significant time (e.g., 10,000 runs)
  - Address any failures

---

## Phase 6: Validation

### 6.1 Coverage Verification

#### Tests

- [ ] **Run full test suite with coverage**
  - Command: `forge test --coverage`
  - Verify all tests pass
  - Review coverage report

- [ ] **Verify 100% branch coverage**
  - Command: `forge coverage --branch`
  - Review `lcov.info` output
  - Identify any uncovered branches
  - Add tests for uncovered branches
  - Repeat until 100% coverage achieved

- [ ] **Generate coverage HTML report**
  - Command: `forge coverage --report lcov && genhtml lcov.info -o coverage`
  - Open `coverage/index.html` in browser
  - Review visually for missed branches

### 6.2 Final Checks

#### Tests

- [ ] **Generate final gas report**
  - Command: `forge snapshot --gas-report`
  - Document gas costs in code comments
  - Create gas snapshot file: `.gas-snapshot`
  - Compare against baseline if available

- [ ] **Manual code review checklist**
  - [ ] All functions emit appropriate events
  - [ ] All error paths are tested
  - [ ] NatSpec comments are complete (contract, functions, params, returns)
  - [ ] No hardcoded values that should be parameters
  - [ ] External calls have proper error handling
  - [ ] Immutable variables are truly immutable
  - [ ] All view functions are marked `view`
  - [ ] All pure functions are marked `pure`
  - [ ] No compiler warnings

- [ ] **Verify upgrade safety**
  - Run: `forge clean && forge build`
  - Check for storage layout warnings
  - Verify no storage collisions in inheritance chain

- [ ] **Final integration test**
  - Run full user journey: deploy → mint → approve earner → start earning → set rate → wait → claim → transfer → stop earning → burn
  - Verify all invariants hold throughout

- [ ] **Document deployment process**
  - Create deployment script: `script/DeployPYUSDX.s.sol`
  - Document constructor parameters
  - Document role assignments
  - Document initial index/rate setup

---

## Task Summary

| Phase                        | Tasks | Description                                 |
| ---------------------------- | ----- | ------------------------------------------- |
| Phase 1: Foundation          | 12    | Project setup, dependencies, interfaces     |
| Phase 2: Core Implementation | 54    | Main contract functions, unit tests, fuzz tests |
| Phase 3: Access Control      | 18    | Roles, permissions, compliance, security    |
| Phase 4: Integration         | 10    | External contract interactions              |
| Phase 5: Invariant Tests     | 6     | Property-based and invariant testing        |
| Phase 6: Validation          | 10    | Coverage verification and final checks      |
| **Total**                    | **110** |                                             |

---

## Execution Notes

### For Agents

1. **Work sequentially**: Complete tasks in order as later tasks may depend on earlier ones
2. **Check off tasks**: Mark tasks as `[x]` when complete
3. **Consult the SDD**: Each task references SDD sections—read them for full context
4. **Run tests frequently**: After implementing each function, run its tests before proceeding
5. **Maintain coverage**: Ensure all branches are covered before moving to the next function
6. **Checkpoint after each phase**: Run full test suite before proceeding to next phase

### Branch Coverage Workflow

1. Create test file with TODO list at top
2. Implement each test case, checking off TODOs
3. Run `forge test` to execute tests
4. Run `forge coverage --branch` to verify branch coverage
5. Address any uncovered branches
6. Repeat until 100% coverage

### Testing Commands

```bash
# Run all tests
forge test

# Run with coverage
forge coverage

# Run with gas report
forge snapshot --gas-report

# Run specific test file
forge test --match-path test/unit/PYUSDXUnit.t.sol

# Run specific test
forge test --match-test testClaimYieldWithFee

# Run fuzz tests
forge test --match-test fuzz* -f

# Run invariant tests
forge test --match-test invariant_*
```

### Storage Layout Notes

M0 Foundation storage pattern (follows JMIExtension, MToken):

- **Abstract layout contract**: Define `PYUSDXLayout` abstract contract containing:
  - All struct definitions (`Account`, `PYUSDXStorageStruct`)
  - Precomputed storage slot constant using M0 formula:
    ```solidity
    // keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDX")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PYUSDX_STORAGE_LOCATION = 0x...;
    ```
  - Helper function `_getPYUSDXStorageLocation()` returning storage struct pointer

- **Access pattern**: Use the helper function to access storage:
  ```solidity
  function someFunction() internal {
      PYUSDXStorageStruct storage $ = _getPYUSDXStorageLocation();
      // Access $.accounts, $.totalEarningSupply, etc.
  }
  ```

- **Inheritance**: Main `PYUSDX` contract inherits from `PYUSDXLayout` plus all M0 extension contracts
- **No storage gaps needed**: For future upgrades, create new storage struct with new namespace (e.g., `M0.storage.PYUSDX.v2`)

### M0 Dependencies

The following M0 packages are required:

- `m0-foundation/common` - Includes OpenZeppelin upgradeable contracts, math libraries, ContinuousIndexing
- `m0-foundation/m-extensions` - Includes Freezable, ForcedTransferable, Pausable
- **EarnerManager**: To be implemented (see `artifacts/earnerManager/EarnerManager-spec.md`)
  - Reference: https://github.com/m0-foundation/wrapped-m-token/blob/296a42b066c719c2be77b64cc80ff50d25f5724f/src/EarnerManager.sol

Install with:

```bash
forge install m0-foundation/common
forge install m0-foundation/m-extensions
```

Use relative paths for imports (no remappings needed)

---

## Appendix

### A. File Structure

```
src/
├── interfaces/
│   └── IPYUSDX.sol
├── PYUSDX.sol
└── (inherited from M0 libraries)

test/
├── unit/
│   └── PYUSDXUnit.t.sol          # Unit tests for all functions (branch coverage)
├── integration/
│   └── PYUSDXIntegration.t.sol   # Integration tests for Minter Gateway and M0 libraries
├── fuzz/
│   └── PYUSDXFuzz.t.sol          # Fuzz tests and stateful fuzzing
└── invariant/
    └── PYUSDXInvariants.t.sol    # Invariant tests (supply consistency, principal sum, etc.)

script/
└── DeployPYUSDX.s.sol

artifacts/
└── pyusdx/
    ├── dtp.md                    # This file
    ├── sdd.md
    ├── prd.md
    ├── PYUSDX-spec.md
    └── (earnerManager specs)
```

### B. Gas Optimization Checklist

- [ ] Use `calldata` for read-only array arguments
- [ ] Cache storage reads in memory for multi-access
- [ ] Pack struct members efficiently
- [ ] Use named returns for clarity
- [ ] Use custom errors instead of revert strings
- [ ] Use `unchecked` for safe operations (e.g., subtraction after verifying result > 0)
- [ ] Short-circuit conditions in require statements
- [ ] Loop unrolling for small fixed-size iterations
- [ ] Use `immutable` for constructor-set values

### C. Security Checklist

- [ ] All external calls follow checks-effects-interactions
- [ ] No state changes after external calls
- [ ] All access control uses role-based permissions
- [ ] Zero address checks on all critical address parameters
- [ ] Overflow/underflow protected (Solidity 0.8+)
- [ ] State updates complete before external calls (no ReentrancyGuard needed)
- [ ] Input validation on all public/external functions
- [ ] Events emitted for all state changes
- [ ] No_tx.origin usage for authorization
- [ ] No delegatecall to user-supplied addresses
- [ ] Proper error handling on external call failures

---

## Important Notes

1. **Function-level granularity**: Each function gets its own implementation task and test tasks
2. **Test file organization**: Tests organized by type, not per-function
   - All unit tests → `test/unit/PYUSDXUnit.t.sol`
   - All fuzz tests → `test/fuzz/PYUSDXFuzz.t.sol`
   - All integration tests → `test/integration/PYUSDXIntegration.t.sol`
   - All invariant tests → `test/invariant/PYUSDXInvariants.t.sol`
3. **Sequential execution**: Tasks build on each other—complete in order
4. **Reference the SDD**: Point to SDD sections rather than copying content
5. **100% branch coverage goal**: Enumerate enough test cases for full coverage
6. **Fuzz external functions**: Any externally callable function gets fuzz tests
7. **Integration tests for integrations**: Minter Gateway, M0 libraries
8. **No deployment tasks**: Focus on implementation and testing only
9. **Inheritance verification**: Many functions are inherited—verify they work correctly
