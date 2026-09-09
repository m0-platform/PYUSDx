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

How a chain's desired configuration is written, what `DeployAll` does with it, and what it records.

Two things changed:

- **Protocol configuration moved from `.env` to per-chain JSON.** `deploymentConfigs/<chainId>/protocol.json`
  is now the single reviewable statement of a chain's non-secret protocol settings — the roles, rate
  limits and endpoint. Other non-secret inputs stay where they are (`EXTENSION_NAME`, `PEERS`,
  `FORCE_REPLAY`, the `CHAIN` alias), and `PRIVATE_KEY` and the RPC URLs stay in the existing `op run`
  secret workflow.
- **The deployment record tracks both extension beacon proxies.** `deployments/<chainId>.json` now carries
  `yieldToOneBeacon` and `multiMintBeacon` alongside the other core addresses.

### Protocol configuration

#### Where it lives

```
deploymentConfigs/<chainId>/protocol.json
```

`deploymentConfigs/example-protocol.json` is the template — copy it for a new chain. Set
`PROTOCOL_CONFIG` to point the script at a different file; its `chainId` must still match the chain
being deployed to.

Committing the file and reviewing it in a PR **is** the deployment review: every address, role and
rate limit that will go on chain is in one document, and the diff is readable. That is the reason for
the move — a `.env` file is untracked, per-machine, and silently different between two people running
the same `make deploy-*` target.

What "desired" means moves with the chain. Before deployment the file holds the initial holders
`DeployAll` installs — commonly the deployer across most role fields, since a launch needs one address
that can finish wiring the suite. After deployment it is edited towards the holders the suite should end
up with, and that edit is what the role-migration scripts read (see [role migration](#role-migration)).
On a live chain a diff here is a change of intent for a deployed suite; review it as one.

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

The eight deployed chains — `deploymentConfigs/{1,143,8453,42161,10143,84532,421614,11155111}/protocol.json` —
were **seeded** from the checked-in `broadcast/DeployAll.s.sol/<chainId>/run-latest.json` receipts: the
initializer calldata of each proxy, the `TransparentUpgradeableProxy` constructor's initial owner, the
`LayerZeroBridgeAdapter` implementation's constructor argument, and the three `setRateLimit` calls.

That is where they came from, not what they are for. They are **not frozen deployment snapshots**; Git
history and the broadcast receipts already preserve the original deployment inputs, so the working file
is free to carry current intent instead.

##### Establishing a deployed chain's baseline

A deployed chain's baseline reconciles two sources:

1. **The latest reviewed intent** — the most recent launch record, runbook or review covering that
   value. A historical runbook is evidence of what was intended at the time, not an automatic override
   of what the chain shows now: a later reviewed decision supersedes it, and some retention is
   deliberate (an operator, pauser or fallback recipient kept on the deployer can be a decision rather
   than a leftover).
2. **Read-only on-chain evidence** — reads of the live suite, which say who holds what now and nothing
   about whether that is correct.

Where they agree, the value is settled. Where they differ, write the latest reviewed intent into
`protocol.json`, list the current holder in `migration.outgoingHolders`, and let `migrate-roles` close
the gap — the difference is carried as pending work, not resolved by copying the chain into the file. A
difference no reviewed record explains is an **unknown change: flag it for review** rather than
settling it in either direction. Until a chain's values have been reconciled and reviewed, treat them as
seeded but unconfirmed. All eight have now been through this once — see
[current baseline](#current-baseline-and-verification) below.

`make verify-roles-<chain>` is the fastest read of the gap: no key, read-only, and it lists every
obligation the chain does not carry whoever runs it. `cast call` covers anything outside the migrated
scope. Every migration target parses `migration.outgoingHolders` first, so a missing or empty list fails
preflight with `NoOutgoingHolders` rather than reporting a plan.

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

Two caveats on the RPCs. The hosts above are the ones that actually answered; several public endpoints
refuse an archive fork at a historical block (`403 Archive requests require a personal token`,
`-32000 metadata is not found`), which is why Ethereum was verified through `eth.drpc.org` rather than
the host its evidence was collected from. The two **bold** blocks are fresh: the tested providers could not
serve a fork at those chains' evidence blocks, so verification used the newer blocks shown above.

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

The same `protocol.json` drives the handover from the holders a chain deployed with to the holders it
should end up with. Editing the role addresses in the file _is_ the migration definition — there is no
second target list and no script source to edit. The scripts read the file as the desired state and the
chain as the actual state; everything they do is the difference between the two.

```
make deploy-base                     # deploy with the initial holders
$EDITOR deploymentConfigs/8453/protocol.json   # set the desired holders + migration.outgoingHolders
                                     # review the diff — it is the migration definition
make migrate-roles-base DRY_RUN=true # read the plan without sending anything
make migrate-roles-base              # send what this signer is authorised to send
make verify-roles-base               # passes only when nothing is outstanding
```

Four stages:

| Stage       | What runs                                | Chain writes | Signer                                                                                                                                                                                                                                          |
| ----------- | ---------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Review**  | The `protocol.json` diff, in a PR        | No           | —. The only stage where the intended end state is decided; a plan executes whatever the file says, a wrong address included.                                                                                                                    |
| **Plan**    | `migrate-roles` with `DRY_RUN=true`      | No           | Signer-dependent. `DRY_RUN=true` only drops `--broadcast`; the script still reads `PRIVATE_KEY`, stages against that signer's on-chain authority, and reverts `NothingExecutable` when work is outstanding and that signer can send none of it. |
| **Execute** | `migrate-roles`, once per current holder | Yes          | Sends only what that signer's current on-chain authority allows; the rest print as `[defer]`.                                                                                                                                                   |
| **Verify**  | `verify-roles`                           | No           | Signer-independent — the plan is built with no executor and no key is read. The only thing that declares the handover complete.                                                                                                                 |

So `verify-roles` is the target that reports the gap regardless of who runs it; a dry-run
`migrate-roles` answers a different question — what _this_ signer could send right now.

#### Two migration-only blocks

`DeployAll` reads its keys one at a time and ignores everything else, so both blocks are optional for a
deploy and a config written before them still deploys unchanged. The migration scripts require the
first one.

| Field                       | Type      | Notes                                                                               |
| --------------------------- | --------- | ----------------------------------------------------------------------------------- |
| `migration.outgoingHolders` | address[] | The holders being migrated away from. Required, non-empty, no zero entries.         |
| `portalOFTWrapper.admin`    | address   | Required only when `deployments/<chainId>.json` records a `pyusdxPortalOFTWrapper`. |
| `portalOFTWrapper.operator` | address   | Same.                                                                               |

`migration.outgoingHolders` records **who held the roles before**, which is not derivable any other
way: this suite uses OpenZeppelin's non-enumerable `AccessControl`, so a contract cannot be asked who
holds a role, and these scripts do not scan historical `RoleGranted` logs. Deriving the list from
the signer or from the edited target addresses instead would quietly miss holders. An empty list is
rejected rather than treated as "nothing to remove".

Each listed address is checked against **every** migrated role. An address that is also the configured
holder of a role keeps that role — the config decides who ends up holding what, the outgoing list only
says who to check. Rate-limit buckets are the one exception to a blanket sweep: only a superseded
earner manager's bucket is retired, and any listed address that actually holds `ISSUER_ROLE` keeps its
bucket, because that bucket is what lets it mint. That covers the IssuerGateway and the Portal, which
always hold it, and any issuer granted after deployment. The check is the on-chain role, not a list of
known addresses; a membership that cannot be read fails preflight rather than being guessed either
way.

#### What is covered

Both `DEFAULT_ADMIN_ROLE` and every named role on PYUSDX, the IssuerGateway, the SwapFacility, the
ExtensionFactory, **both extension beacons**, the Portal, the LayerZeroBridgeAdapter and — when
deployed — the PortalOFTWrapper; the `earnerManager` and `fallbackRecipient` singletons; the earner
manager's rate-limit bucket; and every `ProxyAdmin` owner.

The beacons take their holders from the `extensionFactory` block, matching how they are initialised at
deploy time. Each `ProxyAdmin` owner follows that component's own `admin` field, matching the initial
owner passed at deploy time; the beacons' follow `extensionFactory.admin`.

A core or beacon address that is missing from the deployment record, or that holds no code, **fails
preflight** — it is never skipped, because skipping would let a run report a complete handover for a
contract it never touched. A recorded PortalOFTWrapper with no `portalOFTWrapper` block fails the same
way, naming the address. A chain with no wrapper deployed simply has none planned.

**Not covered:**

- Deployed extension instances (YieldToOne, MultiMint and anything else the factory deploys). Their
  holders live in `deploymentConfigs/<chainId>/<extensionName>.json` and are set and verified by
  `DeployMultiMint`.
- Per-token PortalOFTWrappers. Only the base PYUSDX wrapper — the one recorded as
  `pyusdxPortalOFTWrapper` — is in scope. A wrapper for an extension token is recorded as
  `<SYMBOL>PortalOFTWrapper` among the extension entries and is migrated with its extension, not here.
- Everything in `protocol.json` that is not an authority: `issuerGateway.mintDelay`,
  `issuerGateway.mintTTL` and the `issuerGateway.rateLimit` / `portal.rateLimit` capacities. They are
  validated when the file is read and applied at deploy time, but a migration neither reconciles nor
  verifies them. Only the earner manager's bucket is touched, because the handover ordering couples it
  to `setEarnerManager`.

`verify-roles` says nothing about any of these, and a passing run must not be read as having migrated
them.

One file, but not one sync: `protocol.json` states the desired configuration of the whole core suite,
while the migration covers only the authority part of it, listed above. Editing anything outside that
set changes the stated intent and nothing else — no plan line, no `[defer]`, no verification failure.
Changing such a setting on a live chain is a separate operation against the deployed contract; update
the file so intent stays accurate, and do not expect these scripts to notice either way.

The wrapper's own initial holders come from `PORTAL_OFT_WRAPPER_ADMIN` / `PORTAL_OFT_WRAPPER_OPERATOR`
at deploy time (see [README.md](../README.md#portal-oft-wrapper-decision-and-runbook)); `portalOFTWrapper` in this
file is the **desired end state** the migration moves it to, which is deliberately a separate input:
the deploy-time inputs stay in the existing secret/env workflow.

Also deliberately untouched: `ISSUER_ROLE` on the IssuerGateway and the Portal, which is not
represented in the config. Preflight asserts both still hold it, along with the wiring identities
between the recorded contracts and the configured LayerZero endpoint, and refuses to plan anything
against a suite that does not match.

#### Signers, and resuming across several holders

Only the calls the signer can actually send are broadcast. Everything else is listed as `[defer]` with
the authority it needs, and left for that holder's own run. A suite whose authority is split — say the
admin on a multisig and the rate-limit manager on an EOA — is migrated by each holder running
`migrate-roles` in turn until `verify-roles` passes. A signer that can send none of the outstanding
work fails with `NothingExecutable` rather than broadcasting an empty batch and looking successful.

Authority the batch itself grants is not assumed mid-batch: a newly granted holder uses its role on
its **next** invocation. Three orderings are enforced so a resume can never strand the work:

- a role is never revoked while earlier outstanding work on that contract still needs it, which is
  what keeps `DEFAULT_ADMIN_ROLE` until last and the rate-limit manager until the buckets are set;
- `setEarnerManager` waits until the incoming manager's bucket exists, so it is never live without
  one;
- the LayerZero `setDelegate` waits for the operator revoke that clears it.

Both of the last two hand work to the **incoming** holder, so plan for one follow-up run by whoever
the config names. A typical two-round handover on one chain:

```bash
make migrate-roles-base    # as the outgoing admin: grants, revokes, buckets, ProxyAdmin transfers
make migrate-roles-base    # as the NEW admin + LayerZero operator: setEarnerManager, setDelegate
make verify-roles-base     # only now is the handover complete
```

That last one is the only genuine second step in the suite. `LayerZeroBridgeAdapter._revokeRole`
clears the endpoint delegate on **every** successful `OPERATOR_ROLE` revocation — a self-renounce
included — and only an operator can restore it. So when the adapter's operator changes, the delegate
is restored by the **incoming** operator in a later run, and `verify-roles` fails until it is. Nothing
else needs an acceptance step: OpenZeppelin's `ProxyAdmin` is `Ownable`, so upgrade authority moves in
a single `transferOwnership`.

#### Safe multisig

`make propose-migrate-roles-<chain>` writes `safe/<chainId>-migrate-roles.json` for import into the
Safe Transaction Builder, using the same `SAFE_SUBMIT` / `SAFE_MULTISIG` / alert setup as the
configuration proposals ([README.md#multisig-alerts](../README.md#multisig-alerts)). The plan is built
for `SAFE_MULTISIG` — the Safe is what executes the calls, so the Safe's authority decides what can be
batched; building it for the proposer would queue calls the Safe cannot execute. Queuing a batch is not
a completed handover: only `verify-roles`, run after the Safe has executed, says the migration is done.

#### What verification can and cannot prove

`verify-roles` is the migration plan asserted empty — one predicate decides both what still needs doing
and whether anything does, so a check cannot drift from the work. It reads only, needs no signer key,
and fails with `MigrationIncomplete` while anything is outstanding. A getter it cannot read leaves the
obligation outstanding, so unreadable state fails rather than passing quietly.

A pass says: every holder, singleton, bucket, ProxyAdmin owner and delegate in the covered scope
matches this file, and no address in `migration.outgoingHolders` still holds what it was migrated out
of. It does not say that the file is right — it compares the chain to the desired state and never
questions it, so a reviewed but wrong address verifies clean — nor that the settings outside the
migrated scope match, nor that the result still holds: a pass describes the chain at the block it read,
so re-run it rather than citing an old run.

Its one structural limit follows from the non-enumerable `AccessControl`: it can only prove that the
addresses in `migration.outgoingHolders` no longer hold what they were migrated out of. A holder granted
a role outside that list is invisible to it, and no enumeration of current holders is possible here.
Proving the absence of an unknown holder needs the full `RoleGranted`/`RoleRevoked` log history, which
these scripts do not scan — run that scan out of band against an archive RPC if a chain needs it.

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
