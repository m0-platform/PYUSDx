# Deployment Configs

This directory holds the reviewable, non-secret **desired configuration** — what each chain's suite is
meant to look like — one JSON file per chain:

```
deploymentConfigs/<chainid>/protocol.json          # the core stack, read by DeployAll and the role-migration scripts
deploymentConfigs/<chainid>/<extension-name>.json  # one MultiMint extension, read by DeployMultiMint
```

`protocol.json` uses `example-protocol.json` as its template; see [protocol configuration](#deployment-configuration) below. The first section covers extension configs.

Three artefacts carry a chain through its lifecycle. Keep them apart:

| Artefact                                    | What it is                                                                                                                                      | Who writes it                                                       |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `deploymentConfigs/<chainid>/protocol.json` | **Desired state.** The roles, rate limits and endpoint the chain is meant to carry. Reviewed in a PR; the same file feeds deploy and migration. | People, in a PR.                                                    |
| `deployments/<chainid>.json`                | **Contract addresses.** Where the suite lives on that chain. Says nothing about who holds a role.                                               | `DeployAll` and the extension deploy scripts, on a broadcast run.   |
| The chain                                   | **Actual active state.** The only authority on who holds what right now.                                                                        | Every transaction ever sent, including ones this repo did not send. |

The migration scripts compare the first against the third. Nothing here keeps the first true on its own.

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

### Protocol configuration

`deploymentConfigs/<chainId>/protocol.json` holds non-secret protocol settings shared by deployment
and role migration. Before deployment, use initial holders (usually the deployer); afterwards, edit
the role addresses to the reviewed migration targets. Git history and broadcast receipts preserve
launch inputs. `deployments/<chainId>.json` records contract addresses, and chain reads establish
actual state. Credentials remain in the `op run` workflow.

#### Workflow

1. Copy `deploymentConfigs/example-protocol.json` for a new chain and fill in addresses and limits.
   `PROTOCOL_CONFIG` may select another file; its `chainId` must match the target chain.
2. Add the chain to `DeployAllConfigTests._chainIds()` and
   `DeploymentRecordTests.test_checkedInRecords_carryBackfilledBeacons`, updating their fixed array
   sizes. Run `forge test --match-path 'test/unit/deploy/*.t.sol'` and review the config diff.
3. Run `make deploy-base DRY_RUN=true` and inspect the printed protocol config.
4. Run `make deploy-base` to deploy. Use the corresponding target for other networks.

Missing files/keys, a wrong chain ID and invalid values fail before deployment.

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

Addresses and token name/symbol must be nonzero/nonempty. `mintTTL` and rate-limit capacities must be
positive; refill rates cannot exceed capacity. Zero refill and zero mint delay are allowed. Numeric
values outside their declared uint32/uint128 range are rejected before casting.

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

The eight deployed-chain configs were seeded from `DeployAll` broadcast receipts, then reconciled
against reviewed role-migration intent and read-only chain evidence. Keep current reviewed addresses
here; preserve launch history in Git and receipts.

If reviewed intent differs from the chain, retain the intended target and document the pending work.
Flag unexplained differences for review. `verify-roles` reports the authority gap without a signer;
use direct reads for settings outside its [scope](#what-is-covered).

##### Current baseline and verification

The eight configs were reconciled against reviewed intent and read-only chain evidence at the blocks
below, then checked with `VerifyRoles` (read-only, no key, no `--broadcast`). Chains 1, 143 and 42161
carry the MoonPay and M0 Main V2 authority assignments recorded in `plans/m0-migration.md` and
`plans/moonpay-migration.md` (historical branch, `ef94b21`); the rest retain their bootstrap holders.
The [deployments-by-chain notes](https://app.notion.com/p/PYUSDX-Deployments-by-Chain-3c9858df176a811a9985f0ca8ec54111) and linked [role-transfer receipts](https://app.notion.com/p/3bb858df176a80a4bbd8db1bb364167c) corroborate these mainnet handovers. Keep migration notes and verification evidence here or in the linked records; protocol JSON contains configuration values only.

Per those runbooks the deployer is deliberately **not** retired — it keeps `PAUSER` on SwapFacility and
Portal, `OPERATOR` on Portal and the LayerZero adapter, the endpoint delegate and Portal's
`fallbackRecipient` — so those fields name the deployer by intent, not by omission.

| Chain          | Evidence block | Verified at   | Public RPC used for verification              | `VerifyRoles` result |
| -------------- | -------------- | ------------- | --------------------------------------------- | -------------------- |
| Ethereum 1     | 25939479       | 25939479      | `https://eth.drpc.org`                        | 2 outstanding        |
| Monad 143      | 103311789      | 103311789     | `https://rpc.monad.xyz`                       | clean 0/32/32        |
| Arbitrum 42161 | 503349206      | **503355815** | `https://arb1.arbitrum.io/rpc`                | clean 0/35/35        |
| Base 8453      | 51081965       | 51081965      | `https://mainnet.base.org`                    | clean 0/32/32        |
| Sepolia        | 11667620       | 11667620      | `https://ethereum-sepolia-rpc.publicnode.com` | clean 0/32/32        |
| Arb. Sepolia   | 307054552      | **307061985** | `https://sepolia-rollup.arbitrum.io/rpc`      | clean 0/32/32        |
| Monad testnet  | 61031690       | 61031690      | `https://testnet-rpc.monad.xyz`               | clean 0/32/32        |
| Base Sepolia   | 46592362       | 46592362      | `https://sepolia.base.org`                    | clean 0/32/32        |

`0/32/32` is planned / already applied / inspected; 42161 inspects 35 because it also carries a
`pyusdxPortalOFTWrapper`. Reproduce any row with the config path made explicit:

```bash
PROTOCOL_CONFIG="$PWD/deploymentConfigs/8453/protocol.json" \
  forge script script/migrate/VerifyRoles.s.sol:VerifyRoles \
  --rpc-url https://mainnet.base.org --fork-block-number 51081965 --skip test --non-interactive
```

Some public providers could not serve the evidence blocks. The bold verification blocks are newer
reads; the table identifies the blocks and providers actually used, not a freshness guarantee.

##### The Ethereum gap

Ethereum is the one chain that does not verify clean, and the shortfall is the one
`plans/moonpay-migration.md` already records against mainnet — "earner-manager bucket still missing,
MoonPay must fix". Two obligations remain, both `setRateLimit` on PYUSDX and both needing
`RATE_LIMIT_MANAGER_ROLE`, which MoonPay holds:

- the incoming earner manager `0x3141…B78e` has no bucket (`0/0`), and
- the superseded deployer bucket `5000000000000 / 2500000000` is still live.

`verify-roles` reports `MigrationIncomplete(2)` with both actions deferred to that role holder. The
config states the intended `5000000000000 / 2500000000` for the incoming manager regardless: zeroing it
to match the chain would retire a real obligation by editing a document, and this repository does not
execute the fix.

##### Additional testnet holder awaiting review

On Sepolia (11155111) and Arbitrum Sepolia (421614),
`0x77bab32f75996de8075eba62aea7b1205cf7e004` also holds IssuerGateway `OPERATOR_ROLE` and
`EXECUTOR_ROLE`, alongside the deployer. Log discovery and direct membership reads confirmed this
additional address. Its intended retention or removal is unresolved.

The files retain the bootstrap targets; this section records the discrepancy. They do not
add the extra address to `migration.outgoingHolders`: doing so would prescribe removal without a
reviewed decision. Each role field currently names one target, so it cannot describe two retained
holders. Resolve this intent before using those files for a role migration.

The passing verifier rows for these two chains cover configured targets and the listed outgoing
holder only. They are **not** evidence of a complete holder inventory or a resolved baseline for those
gateway roles. Other chains' candidate checks also do not rule out unknown holders.

### Role migration

Edit the deployed chain's role addresses and outgoing holders in `protocol.json`, then review the diff.
The scripts compare that intent with the chain:

```bash
$EDITOR deploymentConfigs/8453/protocol.json
make migrate-roles-base DRY_RUN=true # simulate for the configured PRIVATE_KEY
make migrate-roles-base              # send what this signer is authorized to send
make verify-roles-base               # read-only, no key; fails while obligations remain
```

A dry run still needs the signer key and reports only what that signer can execute.
`verify-roles` reports all outstanding obligations independently of the signer.

#### Two migration-only blocks

`DeployAll` reads its keys one at a time and ignores everything else, so both blocks are optional for a
deploy and a config written before them still deploys unchanged. The migration scripts require the
first one.

| Field                       | Type      | Notes                                                                               |
| --------------------------- | --------- | ----------------------------------------------------------------------------------- |
| `migration.outgoingHolders` | address[] | The holders being migrated away from. Required, non-empty, no zero entries.         |
| `portalOFTWrapper.admin`    | address   | Required only when `deployments/<chainId>.json` records a `pyusdxPortalOFTWrapper`. |
| `portalOFTWrapper.operator` | address   | Same.                                                                               |

List known former/current holders explicitly: AccessControl is not enumerable and these scripts do
not scan role logs. Each listed address is checked against every migrated role, retaining roles for
which it remains the configured target. Superseded earner buckets are retired, but current issuers
keep theirs; unreadable issuer membership aborts planning.

#### What is covered

The migration covers named roles and `DEFAULT_ADMIN_ROLE` on PYUSDX, IssuerGateway, SwapFacility,
ExtensionFactory, both beacons, Portal, LayerZeroBridgeAdapter and the recorded base PortalOFTWrapper.
It also covers `earnerManager`, `fallbackRecipient`, the earner bucket, ProxyAdmin ownership and the
LayerZero delegate. Beacons use `extensionFactory` holders; each ProxyAdmin follows its component's
`admin`.

Preflight requires deployed code, valid suite wiring, the configured endpoint, and preserved PYUSDX
`ISSUER_ROLE` membership for IssuerGateway and Portal. A recorded wrapper requires its config block.

**Outside this migration and verification:**

- Individual extension instances and per-token OFT wrappers.
- Token name/symbol, mint delay/TTL, and IssuerGateway/Portal rate-limit settings. They remain deployment
  inputs; editing them on a live chain needs a separate operation. Only the earner bucket is migrated.

The base wrapper is deployed separately using `PORTAL_OFT_WRAPPER_ADMIN` / `PORTAL_OFT_WRAPPER_OPERATOR`;
its JSON block supplies migration targets. See the [wrapper runbook](../README.md#portal-oft-wrapper-decision-and-runbook).

#### Signers, and resuming across several holders

Each holder runs the migration with its current authority. Unsendable work is `[defer]`; if nothing
outstanding is executable, the run fails with `NothingExecutable`. Newly granted authority is used
on a later invocation. Ordering preserves:

- Roles needed by earlier outstanding work; default-admin handover comes last.
- The incoming earner bucket before switching `earnerManager`.
- Delegate restoration after LayerZero operator revocation, which clears the delegate even on renounce.

```bash
make migrate-roles-base # outgoing holders: grants, revokes, buckets, ProxyAdmin transfers
make migrate-roles-base # incoming holders: remaining manager/delegate work
make verify-roles-base
```

Split authorities may need more runs. The incoming LayerZero operator must restore the delegate after
revocation. ProxyAdmin ownership transfers in one step and needs no acceptance transaction.

#### Safe multisig

`make propose-migrate-roles-<chain>` writes `safe/<chainId>-migrate-roles.json` for import into the
Safe Transaction Builder, using the same `SAFE_SUBMIT` / `SAFE_MULTISIG` / alert setup as the
configuration proposals ([README.md#multisig-alerts](../README.md#multisig-alerts)). The plan is built
for `SAFE_MULTISIG` — the Safe is what executes the calls, so the Safe's authority decides what can be
batched; building it for the proposer would queue calls the Safe cannot execute. Queuing a batch is not
a completed handover: only `verify-roles`, run after the Safe has executed, says the migration is done.

#### What verification can and cannot prove

`verify-roles` requires an empty migration plan and fails with `MigrationIncomplete` while work remains.
Unreadable state cannot pass. A pass covers the configured targets and listed outgoing holders at the
block read; it does not approve those targets or verify settings outside the migration scope.

Unknown holders are invisible because AccessControl is not enumerable. A full holder inventory needs
historical `RoleGranted`/`RoleRevoked` logs and current membership checks outside these scripts. Resolve
the [additional testnet holder](#additional-testnet-holder-awaiting-review) before migrating those roles.

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

`DeployAll` writes both beacon addresses on every fresh deployment.

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

Both addresses were checked against successful CREATE3 broadcast receipts and the factory's immutable
beacon getters on all eight chains:

```bash
cast call 0x25c8aFfC5a63D8E047c12918C0438ABA5aA09c2A "yieldToOneBeacon()(address)" --rpc-url <chain>
cast call 0x25c8aFfC5a63D8E047c12918C0438ABA5aA09c2A "multiMintBeacon()(address)" --rpc-url <chain>
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
