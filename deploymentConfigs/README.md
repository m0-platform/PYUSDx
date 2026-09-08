# Deployment Configs

This directory holds the reviewable, non-secret deployment configuration, one JSON file per chain:

```
deploymentConfigs/<chainid>/protocol.json          # the core stack, read by DeployAll
deploymentConfigs/<chainid>/<extension-name>.json  # one MultiMint extension, read by DeployMultiMint
```

`protocol.json` uses `example-protocol.json` as its template; see [protocol configuration](#deployment-configuration) below. The first section covers extension configs.

## Extension Deployment Configs

Per-extension deployment configuration for MultiMint extensions, one JSON file per extension
per chain:

```
deploymentConfigs/<chainid>/<extension-name>.json
```

`<extension-name>` is the internal handle passed to the deploy script as `EXTENSION_NAME`. It
seeds the CREATE3 salt (so it determines the deployed address, deterministically per
deployer + name) and is the key under which the address is recorded in
`deployments/<chainid>.json`. It is **not** the on-chain ERC20 name/symbol.

The handle must be unique per chain and is used **verbatim** — casing and whitespace are part
of the salt, so `concusd` and `Concrete USD` are different extensions at different addresses.
Match the handle already recorded in `deployments/<chainid>.json` when redeploying or
configuring an existing extension; chain 1 uses `Concrete USD`. Quote any handle containing
spaces on the command line (`EXTENSION_NAME="Concrete USD"`).

Committing the file and reviewing it in a PR **is** the deployment review: every address and
cap that will go on chain is in this one document.

### Workflow

1. Collect the client's role addresses and initial collateral list (assets + caps) in their
   deployment request.
2. Add `deploymentConfigs/<chainid>/<name>.json` and open a PR for review.
3. After merge, deploy:

   ```bash
   make deploy-multi-mint-mainnet EXTENSION_NAME="<name>"
   ```

   The script sets the initial asset caps atomically in the deploy run — the extension is
   immediately wrappable and never blocked waiting on the external asset cap manager.
   SwapFacility registration is automatic (the factory records the extension type).

4. Post-deploy (M0-internal, separate signer): the PYUSDX earner manager enrolls the extension
   for yield via `pyusdx.setAccountInfo(extension, earnerRateBps, feeRateBps, claimRecipient)`.

### Schema

See `example.json` for a complete template.

| Field                         | Type      | Notes                                                                                                                                                                                   |
| ----------------------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `extensionName`               | string    | Must match the file name / `EXTENSION_NAME` (copy-paste guard).                                                                                                                         |
| `tokenName`                   | string    | On-chain ERC20 name.                                                                                                                                                                    |
| `tokenSymbol`                 | string    | On-chain ERC20 symbol.                                                                                                                                                                  |
| `roles.admin`                 | address   | `DEFAULT_ADMIN_ROLE` — controls all role assignment.                                                                                                                                    |
| `roles.assetCapManager`       | address   | May add/update/disable collateral asset caps after deploy.                                                                                                                              |
| `roles.freezeManager`         | address   | May freeze/unfreeze accounts.                                                                                                                                                           |
| `roles.pauser`                | address   | May pause/unpause the extension.                                                                                                                                                        |
| `roles.versionManager`        | address   | May pin/unpin the beacon implementation version.                                                                                                                                        |
| `roles.yieldRecipient`        | address   | Receives all extension yield.                                                                                                                                                           |
| `roles.yieldRecipientManager` | address   | May change the yield recipient.                                                                                                                                                         |
| `assets[]`                    | array     | Initial collateral assets, registered at deploy time. Must be non-empty.                                                                                                                |
| `assets[].symbol`             | string    | Human label for review only — not read by the script.                                                                                                                                   |
| `assets[].address`            | address   | The collateral token.                                                                                                                                                                   |
| `assets[].cap`                | uint      | Max collateral **balance** the extension may hold, in the asset's own decimals (e.g. $100M USDC = `100000000000000`). Set generously: the cap bounds total deposits, not per-swap size. |
| `replaceAssetWhitelist`       | address[] | Optional. Callers allowed to `replaceAsset` (swap PYUSDX in for held collateral). Empty/omitted = everyone allowed.                                                                     |

Note: there is no per-extension proxy admin. Extensions are beacon proxies — upgrade control
sits with M0's `ExtensionBeacon`; the client-side lever is `roles.versionManager` (version
pinning). If a deployment request lists a "Proxy Admin", map that conversation accordingly.

## Deployment configuration

How `DeployAll` is configured, and what it records.

Two things changed:

- **Protocol configuration moved from `.env` to per-chain JSON.** `deploymentConfigs/<chainId>/protocol.json`
  is now the single reviewable source for every non-secret input to a core deploy. `PRIVATE_KEY` and the
  RPC URLs stay in the existing `op run` secret workflow.
- **The deployment record tracks both extension beacon proxies.** `deployments/<chainId>.json` now carries
  `yieldToOneBeacon` and `multiMintBeacon` alongside the other core addresses.

### Protocol configuration

#### Where it lives

```
deploymentConfigs/<chainId>/protocol.json
```

`deploymentConfigs/example-protocol.json` is the annotated template — copy it for a new chain. Set
`PROTOCOL_CONFIG` to point the script at a different file; its `chainId` must still match the chain
being deployed to.

Committing the file and reviewing it in a PR **is** the deployment review: every address, role and
rate limit that will go on chain is in one document, and the diff is readable. That is the reason for
the move — a `.env` file is untracked, per-machine, and silently different between two people running
the same `make deploy-*` target.

#### Workflow

1. Copy `deploymentConfigs/example-protocol.json` to `deploymentConfigs/<chainId>/protocol.json` and
   fill in the chain's role addresses, rate limits and LayerZero endpoint.
2. Add a new chain to both fixed-size chain lists in `DeployAllConfigTests._chainIds()` (and its caller array type) and `DeploymentRecordTests.test_checkedInRecords_carryBackfilledBeacons` (updating each array length) and run `forge test --match-path "test/unit/deploy/*.t.sol"`. Review the file and test result in a PR; the gas-report workflow also runs the suite.
3. Dry-run against the target chain and read the `protocol config` block the script prints — it echoes
   every value that a broadcast would use:

   ```bash
   make deploy-base DRY_RUN=true
   ```

4. Deploy:

   ```bash
   make deploy-base
   ```

`DeployAll` fails immediately, before deploying anything, if the file is missing, if its `chainId` does
not match the chain, if a required key is absent, or if any value fails validation.

#### Schema

| Field                                           | Type    | Notes                                                                                        |
| ----------------------------------------------- | ------- | -------------------------------------------------------------------------------------------- |
| `chainId`                                       | uint    | Must match the chain being deployed to (copy-paste guard).                                   |
| `pyusdx.name` / `pyusdx.symbol`                 | string  | On-chain ERC20 name and symbol. Non-empty.                                                   |
| `pyusdx.admin`                                  | address | Final `DEFAULT_ADMIN_ROLE` holder, and the initial owner of the PYUSDX proxy's `ProxyAdmin`. |
| `pyusdx.pauser`                                 | address | `PAUSER_ROLE`.                                                                               |
| `pyusdx.freezeManager`                          | address | `FREEZE_MANAGER_ROLE`.                                                                       |
| `pyusdx.forcedTransferManager`                  | address | `FORCED_TRANSFER_MANAGER_ROLE`.                                                              |
| `pyusdx.earnerManager`                          | address | Enrolls extensions for yield; also gets its own mint rate limit.                             |
| `pyusdx.rateManager`                            | address | Final `RATE_LIMIT_MANAGER_ROLE` holder.                                                      |
| `pyusdx.earnerManagerRateLimit.capacity`        | uint128 | Bucket size for the earner manager, in PYUSDX base units (6 decimals). Non-zero.             |
| `pyusdx.earnerManagerRateLimit.refillPerSecond` | uint128 | Refill rate. Must not exceed `capacity`.                                                     |
| `issuerGateway.admin`                           | address | `DEFAULT_ADMIN_ROLE` on the gateway.                                                         |
| `issuerGateway.operator`                        | address | `OPERATOR_ROLE` — proposes mints and burns.                                                  |
| `issuerGateway.executor`                        | address | `EXECUTOR_ROLE` — executes matured mint proposals.                                           |
| `issuerGateway.mintDelay`                       | uint32  | Seconds before a mint proposal becomes executable. May be `0`.                               |
| `issuerGateway.mintTTL`                         | uint32  | Seconds a matured proposal stays executable. Must be non-zero.                               |
| `issuerGateway.rateLimit.capacity`              | uint128 | Non-zero.                                                                                    |
| `issuerGateway.rateLimit.refillPerSecond`       | uint128 | Must not exceed `capacity`.                                                                  |
| `swapFacility.admin` / `swapFacility.pauser`    | address | Roles on the SwapFacility.                                                                   |
| `extensionFactory.admin`                        | address | `DEFAULT_ADMIN_ROLE` on the factory and on both extension beacons.                           |
| `extensionFactory.factoryManager`               | address | `FACTORY_MANAGER_ROLE` on the factory and on both extension beacons.                         |
| `portal.admin` / `portal.pauser`                | address | Roles on the Portal.                                                                         |
| `portal.operator`                               | address | `OPERATOR_ROLE` — the signer the `configure-portal-*` targets need.                          |
| `portal.fallbackRecipient`                      | address | Receives tokens whose delivery cannot be completed. Non-zero.                                |
| `portal.rateLimit.capacity`                     | uint128 | Non-zero.                                                                                    |
| `portal.rateLimit.refillPerSecond`              | uint128 | Must not exceed `capacity`.                                                                  |
| `layerZeroBridgeAdapter.endpoint`               | address | The chain's LayerZero V2 `EndpointV2`. Non-zero.                                             |
| `layerZeroBridgeAdapter.admin`                  | address | `DEFAULT_ADMIN_ROLE` on the adapter.                                                         |
| `layerZeroBridgeAdapter.operator`               | address | `OPERATOR_ROLE` and the LayerZero delegate the `configure-lz-adapter-*` targets need.        |

Each component’s `admin` is also the initial owner of that component’s `ProxyAdmin`, granting upgrade authority. `extensionFactory.admin` owns the factory’s ProxyAdmin and both beacon proxy admins. The pauser fields do not grant upgrade authority.

Numbers may be written as JSON numbers or as quoted decimal strings — quote anything above 2^53 so it
survives tooling that reads the file as double-precision JSON.

#### Validation

Every address is rejected if zero, and `pyusdx.name` / `pyusdx.symbol` are rejected if empty. Beyond
that, three checks exist because the corresponding contract would otherwise revert deep inside a
partially completed deploy:

- **`mintTTL` must be non-zero.** `IssuerGateway._setMintTTL` reverts with `ZeroMintTTL`.
- **Every rate-limit `capacity` must be non-zero.** `DeployAll` sets all three limits with
  `enabled = true`, and `RateLimiter.setRateLimit` reverts with `InvalidRateLimitConfig` on a zero
  capacity. This is the most likely configuration mistake to inherit from the old `.env` defaults,
  which shipped `*_RATE_LIMIT_CAPACITY=0`.
- **`refillPerSecond` must not exceed `capacity`.** A bucket that refills faster than it can hold is
  an unlimited bucket written to look limited.

`refillPerSecond` of `0` and `mintDelay` of `0` are both legitimate and accepted.

Out-of-range numbers fail with an explicit message (`.issuerGateway.mintTTL exceeds uint32`) rather
than silently truncating on the cast.

#### Migrating from `.env`

The variables below are no longer read by `DeployAll`. Move their values into the chain's
`protocol.json` and delete them from `.env`. Nothing else in `.env` changes: `PRIVATE_KEY`, the
`*_RPC_URL` entries, the verifier URLs and the extension-script variables all stay where they are.

| Removed `.env` variable                     | JSON path                                       |
| ------------------------------------------- | ----------------------------------------------- |
| `PYUSDX_NAME`                               | `pyusdx.name`                                   |
| `PYUSDX_SYMBOL`                             | `pyusdx.symbol`                                 |
| `PYUSDX_ADMIN`                              | `pyusdx.admin`                                  |
| `PYUSDX_PAUSER`                             | `pyusdx.pauser`                                 |
| `PYUSDX_FREEZE_MANAGER`                     | `pyusdx.freezeManager`                          |
| `PYUSDX_FORCED_TRANSFER_MANAGER`            | `pyusdx.forcedTransferManager`                  |
| `PYUSDX_EARNER_MANAGER`                     | `pyusdx.earnerManager`                          |
| `PYUSDX_RATE_MANAGER`                       | `pyusdx.rateManager`                            |
| `PYUSDX_EARNER_MANAGER_RATE_LIMIT_CAPACITY` | `pyusdx.earnerManagerRateLimit.capacity`        |
| `PYUSDX_EARNER_MANAGER_RATE_LIMIT_REFILL`   | `pyusdx.earnerManagerRateLimit.refillPerSecond` |
| `ISSUER_GATEWAY_ADMIN`                      | `issuerGateway.admin`                           |
| `ISSUER_GATEWAY_OPERATOR`                   | `issuerGateway.operator`                        |
| `ISSUER_GATEWAY_EXECUTOR`                   | `issuerGateway.executor`                        |
| `ISSUER_GATEWAY_MINT_DELAY`                 | `issuerGateway.mintDelay`                       |
| `ISSUER_GATEWAY_MINT_TTL`                   | `issuerGateway.mintTTL`                         |
| `ISSUER_GATEWAY_RATE_LIMIT_CAPACITY`        | `issuerGateway.rateLimit.capacity`              |
| `ISSUER_GATEWAY_RATE_LIMIT_REFILL`          | `issuerGateway.rateLimit.refillPerSecond`       |
| `SWAP_FACILITY_ADMIN`                       | `swapFacility.admin`                            |
| `SWAP_FACILITY_PAUSER`                      | `swapFacility.pauser`                           |
| `FACTORY_ADMIN`                             | `extensionFactory.admin`                        |
| `FACTORY_MANAGER`                           | `extensionFactory.factoryManager`               |
| `PORTAL_ADMIN`                              | `portal.admin`                                  |
| `PORTAL_PAUSER`                             | `portal.pauser`                                 |
| `PORTAL_OPERATOR`                           | `portal.operator`                               |
| `PORTAL_FALLBACK_RECIPIENT`                 | `portal.fallbackRecipient`                      |
| `PORTAL_RATE_LIMIT_CAPACITY`                | `portal.rateLimit.capacity`                     |
| `PORTAL_RATE_LIMIT_REFILL`                  | `portal.rateLimit.refillPerSecond`              |
| `LAYER_ZERO_ENDPOINT`                       | `layerZeroBridgeAdapter.endpoint`               |
| `LAYER_ZERO_BRIDGE_ADAPTER_ADMIN`           | `layerZeroBridgeAdapter.admin`                  |
| `LAYER_ZERO_BRIDGE_ADAPTER_OPERATOR`        | `layerZeroBridgeAdapter.operator`               |

The `make deploy-*` targets no longer forward these variables, so a stale `.env` cannot silently
override the reviewed file.

#### Configuration for already-deployed chains

Each reconstructed file carries an ignored `_provenance` warning. These files preserve initial deployment inputs; they do not track subsequent role transfers.

`deploymentConfigs/{1,143,8453,42161,10143,84532,421614,11155111}/protocol.json` were reconstructed
from the checked-in `broadcast/DeployAll.s.sol/<chainId>/run-latest.json` receipts — the initializer
calldata of each proxy, the `TransparentUpgradeableProxy` constructor's initial owner, the
`LayerZeroBridgeAdapter` implementation's constructor argument, and the three `setRateLimit` calls.

They record **what was deployed**, not necessarily who holds each role today: roles can be, and are
expected to be, transferred to a multisig after a launch. Treat them as history plus a starting point,
and re-review every value against the chain before reusing one for a redeploy.

### Deployment records

`deployments/<chainId>.json` records the deployed core addresses. Two fields are new:

| Field              | What it is                                                                  |
| ------------------ | --------------------------------------------------------------------------- |
| `yieldToOneBeacon` | The `ExtensionBeacon` proxy behind every YieldToOne extension on the chain. |
| `multiMintBeacon`  | The `ExtensionBeacon` proxy behind every MultiMint extension on the chain.  |

These are **core infrastructure, not extensions**. Every deployed extension is a beacon proxy pointing
at one of these two beacons, so upgrading a beacon's implementation moves every extension of that type
at once. They are top-level keys and never appear in the `extensionNames` / `extensionAddresses` pair,
which continues to hold individual extension proxies keyed by their `EXTENSION_NAME` handle.

`DeployAll` writes both on every fresh deployment. `ScriptBase` exposes them as
`_getYieldToOneBeacon()` and `_getMultiMintBeacon()`, falling back to the `YIELD_TO_ONE_BEACON` /
`MULTI_MINT_BEACON` environment variables when the record has no entry, matching the other core
address getters. These internal helpers currently have no script callers; setting those overrides has no effect on existing entry points.

#### Reading older records

`_readDeployment` reads the record key by key instead of `abi.decode`-ing the whole object, so a record
written before a field existed still loads and the absent field reads as the zero address. Writing to
such a record upgrades it in place without disturbing any core or extension entry already on it.

#### Backfilled chains

Every checked-in record was backfilled with:

```
yieldToOneBeacon  0x4c9989F704b52B230C7C38618CBef171986969e7
multiMintBeacon   0x00B1c02CeBa9dbdccd4fddf822ea6DEAf6e412b3
```

The two addresses are the same on all eight chains because both beacons are deployed through CreateX
with `CREATE3`, by the same deployer, with cross-chain redeploy protection disabled — so the salt, and
therefore the address, is chain-independent.

Each value was established twice, and never guessed:

1. **From the broadcast receipts.** In each `broadcast/DeployAll.s.sol/<chainId>/run-latest.json` (all
   with `status: 0x1`), the `deployCreate3(bytes32,bytes)` call whose salt ends in
   `bytes11(keccak256("PYUSDXYieldToOneBeacon"))` = `0x79ab16825afe7ec19ec4c8` — respectively
   `bytes11(keccak256("PYUSDXMultiMintBeacon"))` = `0x60e79680f90fbd4f6421d7` — creates the proxy.
   The same procedure reproduces the `pyusdx`, `portal`, `swapFacility` and `extensionFactory`
   addresses already on record, which is what makes the mapping trustworthy.
2. **Against the live chain.** `ExtensionFactory.yieldToOneBeacon()` and
   `ExtensionFactory.multiMintBeacon()` are immutable constructor arguments. Reading them from
   `0x25c8aFfC5a63D8E047c12918C0438ABA5aA09c2A` on all eight chains returns exactly these addresses:

   ```bash
   cast call 0x25c8aFfC5a63D8E047c12918C0438ABA5aA09c2A "yieldToOneBeacon()(address)" --rpc-url <chain>
   cast call 0x25c8aFfC5a63D8E047c12918C0438ABA5aA09c2A "multiMintBeacon()(address)"  --rpc-url <chain>
   ```

`DeploymentRecordTests.test_checkedInRecords_carryBackfilledBeacons` pins both values for every chain.

### Tests

| Suite                                     | Covers                                                                                                                                     |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `test/unit/deploy/DeployAllConfig.t.sol`  | Template/schema drift, every checked-in chain config, chain guard, numeric bounds, validation rejections.                                  |
| `test/unit/deploy/DeploymentRecord.t.sol` | Beacons recorded and kept distinct from extensions, legacy records readable, updates preserve core and extension entries, backfill pinned. |

Both are plain unit suites — no fork or RPC needed:

```bash
forge test --match-path "test/unit/deploy/*.t.sol"
```

They write their scratch records under `out/test-deployments/`, which `fs_permissions` in
`foundry.toml` allows and `.gitignore` already excludes, so they never touch `deployments/`.
