# PYUSDX

PYUSDX is an upgradeable ERC20 stablecoin protocol built by [M0 Labs](https://www.m0.xyz). It implements non-rebasing yield mechanics with claimable yield via continuous indexing, compliance features (freezing, forced transfers, pausing), token-bucket rate limiting on mints, a multi-extension platform for branded wrapper tokens, and cross-chain bridging through a Portal with pluggable bridge adapters.

## Architecture

```
src/
├── PYUSDX.sol                    Core ERC20 token (6 decimals, claimable yield, compliance)
├── IPYUSDX.sol                   Token interface
├── abstract/
│   └── RateLimiter.sol           Token-bucket rate limiting mixin
├── core/
│   └── IssuerGateway.sol         Time-delayed mint/burn gateway with proposal lifecycle
├── platform/
│   ├── Extension.sol             Base wrapper token (wrap PYUSDX -> extension, unwrap back)
│   ├── ExtensionBeacon.sol       Beacon for upgradeable extensions
│   ├── ExtensionBeaconProxy.sol  Beacon proxy for extension instances
│   ├── ExtensionFactory.sol      Factory for deploying extension tokens
│   └── projects/
│       ├── YieldToOne.sol        Extension routing all yield to a single recipient
│       └── MultiMint.sol         Extension accepting multiple stablecoin collaterals
├── swap/
│   └── SwapFacility.sol          Swap between PYUSDX and extension tokens
└── portal/
    ├── Portal.sol                Cross-chain bridging with pluggable adapters
    └── bridgeAdapters/
        └── layerZero/            LayerZero V2 bridge adapter
```

### Key Contracts

| Contract                   | Description                                                                                                                                                                                              |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **PYUSDX**                 | Core token. Non-rebasing ERC20 with per-account earning rates, claimable yield via continuous indexing, fee collection, compliance controls, and rate-limited minting. Uses ERC-7201 namespaced storage. |
| **IssuerGateway**          | Operators propose mints with a configurable delay; executors finalize them after the delay window. Direct burn for operators. Proposals expire after a TTL.                                              |
| **Extension**              | Base class for branded PYUSDX wrappers. Beacon proxy pattern for upgradeability with version pinning.                                                                                                    |
| **YieldToOne**             | Extension where all accrued yield is minted to a designated recipient.                                                                                                                                   |
| **MultiMint**              | Extension accepting multiple ERC20 assets (e.g. USDC, USDT, PYUSDX) with per-asset caps. Always unwraps to PYUSDX.                                                                                       |
| **ExtensionFactory**       | Deploys YieldToOne and MultiMint extensions via beacon proxies. Manages implementations per extension type.                                                                                              |
| **SwapFacility**           | Atomic swaps between any two extensions, or PYUSDX into an extension. Supports ERC-2612 permit.                                                                                                          |
| **Portal**                 | Cross-chain token transfers via configurable bridge adapters. Separate send/receive pause controls.                                                                                                      |
| **LayerZeroBridgeAdapter** | Bridge adapter implementation for LayerZero Endpoint V2.                                                                                                                                                 |
| **RateLimiter**            | Token-bucket rate limiting mixin with a packed 2-slot Bucket struct.                                                                                                                                     |

## Development

### Prerequisites

- [Foundry](https://github.com/foundry-rs/foundry) (Solc 0.8.34, Cancun EVM)
- [Node.js](https://nodejs.org/) >= 18
- [lcov](https://github.com/linux-test-project/lcov) (for coverage reports)
- [Slither](https://github.com/crytic/slither) (for static analysis)

### Installation

```bash
git clone --recurse-submodules https://github.com/m0-foundation/PYUSDX.git
cd PYUSDX
npm install
```

### Environment

```bash
cp .env.example .env
```

Fill in the required values. See `.env.example` for the full list of configuration variables including RPC URLs, deployer key, and role addresses.

### Compile

```bash
npm run compile
```

### Test

```bash
npm test                  # all tests
npm run test-fuzz         # fuzz tests
npm run test-integration  # integration tests
npm run test-invariant    # invariant tests
```

Run a specific test contract or test case:

```bash
forge test --mc <TestContractName>
forge test --mt <testCaseName>
```

### Coverage

```bash
npm run coverage
open coverage/index.html
```

### Gas Report

```bash
npm run test-gas
```

### Static Analysis

```bash
npm run slither
```

### Code Quality

[Prettier](https://prettier.io) and [Solhint](https://protofire.github.io/solhint/) are enforced via [Husky](https://typicode.github.io/husky/) pre-commit hooks.

```bash
npm run prettier      # format
npm run solhint       # lint
npm run solhint-fix   # auto-fix
```

### Documentation

Forge-generated docs served locally:

```bash
npm run doc           # http://localhost:4000
```

Protocol specification PDFs are available in the `docs/` directory.

## Deployment & Operations

Operational scripts in `script/` are driven through the `Makefile`. Secrets are injected at run time with the [1Password CLI](https://developer.1password.com/docs/cli/) via `op run --env-file=".env"`, so `.env` can store secret values as `op://` references (e.g. `PRIVATE_KEY="op://vault/item/field"`). Each command selects a network through the `CHAIN` variable, which resolves to a `[rpc_endpoints]` alias in `foundry.toml` and its matching `*_RPC_URL`.

`deploymentConfigs/<chainId>/protocol.json` is the chain's **desired configuration** of the non-secret protocol settings — roles, rate limits and the LayerZero endpoint. `DeployAll` reads it to install the initial holders, and the role-migration scripts read the same file as the end state to move the deployed suite towards; `PROTOCOL_CONFIG` can select another file with a matching `chainId`. Keep it distinct from `deployments/<chainId>.json`, which records deployed contract addresses only, and from the chain, which is the only authority on who holds a role now. Validate and review it before deploying or migrating. Credentials remain in the secret workflow. See [configuration migration and beacon records](deploymentConfigs/README.md#deployment-configuration).

Any deploy, configure or bridge command accepts `DRY_RUN=true`, which simulates against the target chain and sends nothing (e.g. `make configure-portal-sepolia DRY_RUN=true`). The `propose-*` targets export a Safe batch by default. `SAFE_SUBMIT=true` additionally queues it on the Safe transaction service; `DRY_RUN=true` suppresses submission and alerts.

| Network       | `CHAIN` alias      | Chain ID   | LayerZero EID |
| ------------- | ------------------ | ---------- | ------------- |
| Ethereum      | `mainnet`          | `1`        | `30101`       |
| Arbitrum      | `arbitrum`         | `42161`    | `30110`       |
| Monad         | `monad`            | `143`      | `30390`       |
| Base          | `base`             | `8453`     | `30184`       |
| Sepolia       | `sepolia`          | `11155111` | `40161`       |
| Arb. Sepolia  | `arbitrum-sepolia` | `421614`   | `40231`       |
| Monad testnet | `monad-testnet`    | `10143`    | `40442`       |
| Base Sepolia  | `base-sepolia`     | `84532`    | `40245`       |
| Anvil         | `localhost`        | `31337`    | —             |

### Build (production)

```bash
npm run build
```

### Deploy

Deploys the full core stack (PYUSDX, IssuerGateway, SwapFacility, ExtensionBeacon/Factory, Portal, LayerZeroBridgeAdapter) via `script/deploy/DeployAll.s.sol`, reading roles and protocol settings from `deploymentConfigs/<chainId>/protocol.json`. For a new chain (including local chain 31337), prepare a matching file from `deploymentConfigs/example-protocol.json` first; see [the configuration runbook](deploymentConfigs/README.md#deployment-configuration). At deploy time the file holds the **initial** holders — commonly the deployer across most role fields — and is edited to the intended end state afterwards, which is what [Migrate roles](#migrate-roles) then reads. Artifacts, including both beacon proxy addresses, are written to `deployments/<chainId>.json`, which the configure and bridge commands consume; that record carries addresses only, never role holders.

```bash
anvil                 # local only, in a separate shell
make deploy-local     # or: npm run deploy-local
make deploy-mainnet
make deploy-arbitrum
make deploy-monad
make deploy-base
make deploy-sepolia   # or: npm run deploy-sepolia
make deploy-monad-testnet
make deploy-base-sepolia
```

Individual extensions have their own targets. `EXTENSION_NAME` is the internal handle recorded in `deployments/<chainId>.json`; MultiMint additionally reads roles and asset caps from `deploymentConfigs/<chainId>/<EXTENSION_NAME>.json` ([schema](deploymentConfigs/README.md)).

```bash
make deploy-yield-to-one-mainnet EXTENSION_NAME="<name>"
make deploy-multi-mint-mainnet EXTENSION_NAME="<name>"
make configure-multi-mint-asset-cap-mainnet EXTENSION_NAME="<name>" ASSET=<address> ASSET_CAP=<amount>
```

Swap `-mainnet` for `-arbitrum`, `-sepolia` or `-local`.

### Configure the Portal

Wires each peer chain on the Portal and LayerZeroBridgeAdapter (peer adapter, bridge chain id, supported/default adapter, payload gas limit). The signer must hold `OPERATOR_ROLE` on the Portal and the adapter. The script prints planned/skipped settings and submits only changes; an unchanged rerun does nothing. See [rerun behavior and the explicit replay override](#configuration-reruns). `PEERS` is a Solidity `uint32[]` of remote chain IDs; it defaults per target and can be overridden with `PEERS='[...]'`.

```bash
make configure-portal-mainnet     # wires Arbitrum (42161) + Monad (143) + Base (8453) as peers
make configure-portal-arbitrum    # wires Ethereum (1) + Monad (143) as peers
make configure-portal-monad       # wires Ethereum (1) + Arbitrum (42161) as peers
make configure-portal-base        # wires Ethereum (1) as peer
make configure-portal-local
```

Peering is reciprocal: adding a chain means re-running the configure target on every existing peer as well as on the new chain.

### Configure LayerZero security

Applies the LayerZero V2 ULN/DVN `setConfig` for each peer route. The signer must be the adapter's LayerZero delegate. As with the Portal target, the script prints planned/skipped routes and submits only the routes whose config the adapter does not already pin; see [rerun behavior and the explicit replay override](#configuration-reruns).

Routes between Ethereum, Arbitrum and Base pin the LayerZero default stack of `[LayerZero Labs, Google]`. Google runs no DVN on Monad, so every Monad route uses `[LayerZero Labs, Nethermind]` instead; testnet routes use `[LayerZero Labs]` alone.

```bash
make configure-lz-adapter-mainnet
make configure-lz-adapter-arbitrum
make configure-lz-adapter-monad
make configure-lz-adapter-base
make configure-lz-adapter-local
```

### Propose via Safe multisig

When the Portal/adapter roles are held by a multisig, the `propose-*` variants write a Safe Transaction Builder batch to `safe/<chainId>-*.json` (no broadcast) for import into the Safe UI. They carry the same transactions the direct targets would broadcast, so an unchanged rerun writes no batch and asks no one to sign. Set `SAFE_SUBMIT=true` and `SAFE_MULTISIG` to queue the batch, with optional `SLACK_WEBHOOK_URL` alerts after acceptance; see [setup and failure handling](#multisig-alerts).

```bash
make propose-configure-portal-mainnet
make propose-configure-portal-arbitrum
make propose-configure-portal-monad
make propose-configure-portal-base
make propose-configure-lz-adapter-mainnet
make propose-configure-lz-adapter-arbitrum
make propose-configure-lz-adapter-monad
make propose-configure-lz-adapter-base
```

### Migrate roles

Hands the deployed suite over from the holders it launched with to the holders named in the chain's `deploymentConfigs/<chainId>/protocol.json`. Editing that file is the whole migration definition — no second address list, no script edits. The scripts read the file as the desired state and the chain as the actual state, and do exactly the difference. The full flow, schema and limits are in [the role migration runbook](deploymentConfigs/README.md#role-migration).

Review the config diff before running anything: it is the only stage where the intended end state is decided, since a plan executes whatever the file says and `verify-roles` then passes on it. Where the file and the chain differ, write the latest reviewed intent into the file and let the migration close the gap; a difference no reviewed record explains is an unknown change to flag for review, not something to settle by copying the chain into the file.

```bash
$EDITOR deploymentConfigs/8453/protocol.json   # desired holders + migration.outgoingHolders
make migrate-roles-base DRY_RUN=true           # print the plan, send nothing
make migrate-roles-base                        # send what this signer may send
make verify-roles-base                         # passes only when nothing is outstanding
make propose-migrate-roles-base                # or: Safe batch for the multisig that holds authority
```

Covers `DEFAULT_ADMIN_ROLE` and every named role across PYUSDX, the IssuerGateway, the SwapFacility, the ExtensionFactory, both extension beacons, the Portal, the LayerZeroBridgeAdapter and any deployed PortalOFTWrapper, plus the `earnerManager` and `fallbackRecipient` singletons, the earner-manager rate-limit bucket and every `ProxyAdmin` owner. Deployed **extension instances are not covered** — their holders live in the per-extension configs and are verified by `DeployMultiMint`.

The plan itself is built from `staticcall`s, but the two read-only paths differ. `verify-roles` is signer-independent: it plans with no executor, reads no key, and reports the whole gap whoever runs it. `migrate-roles DRY_RUN=true` is not — `DRY_RUN=true` only drops `--broadcast`, so the script still reads `PRIVATE_KEY`, stages against that signer's current on-chain authority, and reverts `NothingExecutable` when work is outstanding and that signer can send none of it. It answers what _this_ signer could send, not what remains overall.

Only the calls the signer's current authority allows are broadcast; the rest print as `[defer]` with the authority each needs, so a suite whose authority is split across holders is migrated by each of them running the target in turn. `verify-roles` is the only thing that declares the handover complete, and a pass is bounded by the covered scope above, by the block it read, and by the non-enumerable `AccessControl` — it cannot see a holder granted outside `migration.outgoingHolders`. One genuine follow-up exists: changing the LayerZero adapter's operator clears the endpoint delegate, and only the incoming operator can restore it.

### Bridge PYUSDX cross-chain

Bridges PYUSDX through the Portal using the default bridge adapter (`script/execute/Bridge.s.sol`). `AMOUNT` is in base units (6 decimals); `RECIPIENT` is optional and defaults to the signer. The signer must hold the PYUSDX being bridged and enough native gas for the LayerZero fee, which is quoted automatically.

```bash
make bridge-mainnet-to-arbitrum AMOUNT=1000000
make bridge-arbitrum-to-mainnet AMOUNT=1000000 RECIPIENT=0x1111111111111111111111111111111111111111
make bridge-mainnet-to-monad    AMOUNT=1000000
make bridge-monad-to-mainnet    AMOUNT=1000000
make bridge-mainnet-to-base     AMOUNT=1000000
make bridge-base-to-mainnet     AMOUNT=1000000
make bridge-local-to-arbitrum   AMOUNT=1000000
```

## Deployment workflow runbooks

- [Protocol JSON configuration and beacon deployment records](deploymentConfigs/README.md#deployment-configuration)
- [Establishing a deployed chain's desired-state baseline](deploymentConfigs/README.md#configuration-for-already-deployed-chains)
- [Role migration: deploy, edit the JSON, migrate, verify](deploymentConfigs/README.md#role-migration)
- [Configuration reruns and planned changes](#configuration-reruns)
- [Safe submission and optional multisig alerts](#multisig-alerts)
- [INT-466 validation evidence](#deployment-workflow-validation)
- [OFT wrapper purpose, deployment and quote/send example](#portal-oft-wrapper-decision-and-runbook)

## CI

Gas-report and coverage workflows run on pushes to `main` and pull requests. The standalone fuzz, integration and invariant workflow definitions are currently commented out:

| Workflow               | Description                                                                   |
| ---------------------- | ----------------------------------------------------------------------------- |
| `coverage.yml`         | Build + test coverage (reported on PRs via lcov)                              |
| `test-gas.yml`         | Gas report (diff reported on PRs)                                             |
| `test-fuzz.yml`        | Disabled standalone workflow; run fuzz tests locally (10,000 CI-profile runs) |
| `test-integration.yml` | Disabled standalone workflow; included in full-suite runs                     |
| `test-invariant.yml`   | Disabled standalone workflow; included in full-suite runs (CI depth 250)      |

Repository secrets required: `MNEMONIC_FOR_TESTS`, `MAINNET_RPC_URL`.

## License

BUSL-1.1

## Configuration reruns

### What changed

`ConfigurePortal`, `ConfigureLayerZero` and their `Propose*` counterparts used to emit every peer-setting transaction on every run. Wiring three peers meant fifteen Portal/adapter calls and six LayerZero `setConfig` calls whether or not the chain already carried them, so a rerun to add one peer re-sent the settings of every other peer, and a Safe batch to add one route asked signers to review transactions that changed nothing.

The builders now inspect the live contracts first and emit only the settings that differ. A rerun against an unchanged chain broadcasts nothing and writes no Safe batch. Adding a peer emits that peer's settings alone. Changing a route — a redeployed peer adapter, a new gas limit, a rotated DVN — emits only the settings that changed.

### How a setting is decided

Every intended setting becomes a `PlannedAction`: the transaction, a description, and whether the chain already carries it (`script/libraries/ConfigurationPlan.sol`). `ConfigurationPlan.compact` drops the applied ones; what is left is what gets broadcast or proposed.

The current value of each setting is read with a raw `staticcall` that reports failure instead of reverting (`script/libraries/StateReader.sol`), with basic length and head-offset checks before decoding. **A setting is skipped only when its current value was read successfully and matches.** A missing contract, a missing getter, truncated data or a non-standard head offset leave the setting planned and mark its plan line `[current state unreadable]`. Unknown state is never treated as applied. A long response with malformed inner ABI offsets or scalar encoding can still fail decoding and abort the run; it is never skipped as matching.

#### Portal and LayerZeroBridgeAdapter

Five settings per peer, each compared against its own getter, in this order:

| Transaction                                                         | Compared against                                           |
| ------------------------------------------------------------------- | ---------------------------------------------------------- |
| `adapter.setBridgeChainId(peerChainId, eid)`                        | `adapter.getBridgeChainId(peerChainId)`                    |
| `adapter.setPeer(peerChainId, peerAdapter)`                         | `adapter.getPeer(peerChainId)`                             |
| `portal.setSupportedBridgeAdapter(peerChainId, localAdapter, true)` | `portal.supportedBridgeAdapter(peerChainId, localAdapter)` |
| `portal.setPayloadGasLimit(peerChainId, gasLimit)`                  | `portal.payloadGasLimit(peerChainId)`                      |
| `portal.setDefaultBridgeAdapter(peerChainId, localAdapter)`         | `portal.defaultBridgeAdapter(peerChainId)`                 |

The comparison is per setting, not per peer: a peer whose adapter side is wired but whose Portal side is not emits the three Portal calls and nothing else.

##### Why `setBridgeChainId` comes before `setPeer`

`BridgeAdapter.setBridgeChainId` maintains a 1-1 mapping between internal chain IDs and bridge chain IDs, and it enforces that by deleting whatever the assignment displaces. When a chain's mapping moves off a non-zero value, **that chain's peer is cleared as a side effect** — the adapter refuses to combine a stale peer with an updated bridge chain ID, so sends revert with `UnsupportedChain` until the operator re-asserts the peer.

That interacts badly with skipping. A route configured against a superseded endpoint ID — the situation LayerZero's Monad EID migration produced — has a correct peer and a stale mapping. Sending `setPeer` first and then `setBridgeChainId` writes the peer and immediately wipes it; skipping `setPeer` because it already matched wipes it and never puts it back. Either way the run reports success and leaves the route unusable.

So the planner does two things:

1. **Orders the mapping before the peer.** `setBridgeChainId` is always the first call for a peer and `setPeer` the second.
2. **Re-asserts the peer whenever the mapping change ahead of it will clear it** — that is, whenever the mapping is moving off a non-zero value, or the current mapping could not be read at all. Those plan lines are marked `[re-asserted: the bridge chain ID change clears it]`. A first assignment (the current mapping is zero) displaces nothing, so a matching peer stays skipped.

`test/unit/configure/ConfigurePortalRerunExecution.t.sol` executes the plan against stateful adapter and Portal mocks that mirror the real setters and asserts the final `getPeer`/`getBridgeChainId`, because a calldata-only test cannot catch this class of bug.

##### Conflicting bridge chain IDs

Claiming a bridge chain ID that a _different_ internal chain currently holds deletes that chain's mapping and peer too. `LayerZeroConfig` maps every supported chain to a distinct endpoint ID, so two peers in one run cannot legitimately target the same one — which is why no reordering within a run is needed to protect one peer from another.

If the claimed endpoint ID is held by another chain **in the same run**, the planner refuses the batch with `ConflictingBridgeChainId(peerChainId, conflictingChainId, bridgeChainId)`. It does not reorder recovery transactions automatically. Configure the displaced holder first in a separate single-peer run, then configure the claiming peer; review both plans. `FORCE_REPLAY` does not bypass this guard.

When the holder is **outside** the run, the mapping change is permitted and the plan explicitly warns that it also clears that chain's mapping and peer. Review this collateral change before proceeding; configure any route that must remain active separately.

#### LayerZero ULN configuration

Two settings per peer — one `endpoint.setConfig` on the send library, one on the receive library — each compared against **the adapter's own stored ULN config on that library**, read with `getAppUlnConfig(oapp, remoteEid)` (`script/interfaces/IUln302Like.sol`).

This is deliberately not `endpoint.getConfig`, and the distinction matters more here than anywhere else in the flow:

- `endpoint.getConfig` returns the _effective_ config. For any field an OApp has left unset, ULN302 substitutes the library default, so an unconfigured route reads back as a fully populated config.
- PYUSDX pins LayerZero's own default stack on several routes by design — `[LayerZero Labs, Google]` on Ethereum ↔ Arbitrum ↔ Base, with confirmations matching each chain's on-chain default. On those routes the effective config of a _never-configured_ adapter is identical to what the script intends to set.
- Comparing against the effective config would therefore report a brand-new chain as already configured and the route would never be pinned at all — leaving its security stack free to move whenever LayerZero changes a default.

The two views also differ in encoding. The intended config marks "no optional DVNs" with `NIL_DVN_COUNT` (255), which is how ULN302 is told _explicitly none_ rather than _inherit the default_; the effective read normalises that back to `0`. `test/integration/ConfigureLayerZeroIntegration.t.sol` asserts exactly that normalisation on a mainnet fork. The app-level read has no such normalisation: ULN302 stores the config as submitted, so an unchanged rerun reads back byte-identical to what the previous run wrote, and equality can be strict — confirmations, both DVN counts, the optional threshold, and both DVN lists in order.

If a message library does not answer `getAppUlnConfig`, the route stays planned and its plan line says `[current state unreadable]`. That degradation is safe (nothing is skipped on a guess) and visible (an operator seeing every route planned with that marker knows the read, not the state, is the problem).

### Reading the output

Both builders print the full plan before anything is submitted:

```
Portal configuration plan (chain 1):
  [skip] adapter.setBridgeChainId(42161 -> 30110)
  [skip] adapter.setPeer(42161 -> 0x1234…)
  [plan] portal.setSupportedBridgeAdapter(42161 -> 0xabcd…)
  [plan] portal.setPayloadGasLimit(42161 -> 500000)
  [plan] portal.setDefaultBridgeAdapter(42161 -> 0xabcd…)
  planned / already applied / inspected: 3 2 5
```

`[skip]` lines are settings the chain already carries; `[plan]` lines are what will be sent. Review the plan before signing or broadcasting: a `[plan]` line on a route you believe is configured means the on-chain value drifted, and a `[skip]` line on a route you believe is new means the deployment record and the chain disagree.

When nothing needs to change:

- `ConfigurePortal` / `ConfigureLayerZero` print `Every inspected setting is already applied; nothing broadcast.` and return **before** `vm.startBroadcast`. No transaction is signed and `PRIVATE_KEY` is not even read.
- `ProposeConfigurePortal` / `ProposeConfigureLayerZero` print the equivalent line and return **before** `_writeSafeBatch`. No Safe batch file is written, no batch alert is sent, and the multisig is not asked to sign anything.

An unchanged proposal run leaves any older export on disk intact and prints a stale-export warning. Do not import that older file as the result of the current run.

Direct execution and Safe proposal build the same plan through the same `_planPeers` and compact it the same way, so the batch a signer reviews is exactly the set of transactions a direct run would broadcast.

### Replay override

Set `FORCE_REPLAY=true` to re-send every setting regardless of current state:

```bash
FORCE_REPLAY=true make configure-portal-mainnet
FORCE_REPLAY=true make propose-configure-lz-adapter-mainnet
```

The override skips the comparison, not the read: the plan still prints, every line reads `[plan]`, and the resulting batch is the full pre-INT-471 wiring. Use it when the on-chain state is trusted less than the intent — after an incident, after a proxy upgrade whose storage you have not re-verified, or to reproduce a historical batch. It is not the normal path: a forced rerun re-sends transactions the chain does not need, which costs gas and asks signers to approve no-ops.

`FORCE_REPLAY` is read with `vm.envOr("FORCE_REPLAY", false)`, so leaving it unset is the safe default.

### Roles are unchanged

The rerun logic changes only which transactions are built. The signer requirements are the same as before: `OPERATOR_ROLE` on both the Portal and the LayerZeroBridgeAdapter for `configure-portal`, and the adapter's LayerZero delegate for `configure-lz-adapter`. The plan is built with `staticcall`s that need no permissions, so a caller without the role still gets an accurate plan — it will simply revert when the transactions execute. Reading the plan is a safe way to check what a rerun would do before arranging a signer.

### Tests

| File                                                      | Covers                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `test/unit/configure/ConfigurePortalReruns.t.sol`         | Unconfigured, fully configured, partially configured, new peer alongside a configured peer, redeployed peer adapter, drifted gas limit, changed bridge chain ID (including peer re-assertion, first assignment and unreadable mapping), rotated local adapter, unreadable state, plan output, `FORCE_REPLAY`, direct/proposal parity                                                                                                                                                                                                                                                |
| `test/unit/configure/ConfigurePortalRerunExecution.t.sol` | The plan executed against stateful adapter and Portal mocks: first run then empty rerun, adding a second peer, a changed bridge chain ID keeping the peer, the peer-first ordering that loses it, `FORCE_REPLAY`, and both conflicting-bridge-chain-ID cases                                                                                                                                                                                                                                                                                                                        |
| `test/unit/configure/ConfigureLayerZeroReruns.t.sol`      | Never-configured route, pinned route, config inherited from library defaults (both the optional and required DVN-count forms), changed confirmations, changed DVN set, changed DVN count, new peer alongside a pinned peer, library without `getAppUlnConfig`, unexpected return shape, `FORCE_REPLAY`, direct/proposal parity                                                                                                                                                                                                                                                      |
| `test/integration/ConfigureRerunsIntegration.t.sol`       | The same behaviour against the real Portal, adapter and live ULN302 libraries on a mainnet fork. Requires `MAINNET_RPC_URL`; run with `make integration`                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `test/integration/MigrateRolesIntegration.t.sol`          | Role migration against a real core stack deployed by the production deploy path on a mainnet fork: preflight failures (missing/codeless deployment, empty or zero outgoing holder, wrapper deployed without config, broken issuer wiring, endpoint mismatch), an unauthorised signer staging nothing, the full deploy-defaults → edited JSON → migrate → verify → no-op rerun path, resume across three separate authority holders, the earner-bucket ordering, the LayerZero delegate wipe and its deferred restore, preserved issuer roles and buckets, and batch/executor parity |
| `test/integration/MigrateRolesEntrypoints.t.sol`          | The `MigrateRoles` / `VerifyRoles` / `ProposeMigrateRoles` entry points themselves, against a real core stack plus a real PortalOFTWrapper on a mainnet fork, driven by an actual `protocol.json` and deployment record on disk: deploy defaults verify clean, edited JSON fails verification, migrate as each current holder, verify passes, rerun changes nothing; config for the wrong chain, a zero desired holder, a signer that can send nothing, a propose run with no Safe, and the exported Safe batch replayed off disk to the same chain state as a direct run           |

The unit suites serve current state through `vm.mockCall` on the getters the builders staticcall, so they cover the decision logic without a fork. The fork suite is what proves the ULN302 `getAppUlnConfig` read itself behaves as assumed.

## Multisig alerts

The `Propose*` configuration scripts can queue their batch on the Safe transaction service and
announce it to a Slack webhook, so a signer learns a proposal is waiting without watching a terminal.

Both are opt-in. By default a propose run does exactly what it always did: write an offline Safe
Transaction Builder export and nothing else.

`script/configure/SafeProposerBase.sol` is composition only. Queuing, the per-chain transaction
service and `MultiSendCallOnly` tables, `MultiSend` packing and signing belong to
[`lib/safe-utils`](https://github.com/m0-foundation/safe-utils); the Block Kit payload and its
transport belong to [`lib/foundry-slack`](https://github.com/m0-platform/foundry-slack). What is
left in this repo is the mode gating, the offline export, the message content and the Safe web-app
link map — the same split as
[`evm-m-suite-deployment/script/ProposeBase.sol`](https://github.com/m0-foundation/evm-m-suite-deployment/blob/main/script/ProposeBase.sol).

### Two modes

| Mode                                        | What happens                                                                                                  | Network | Alert                     |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------- | ------------------------- |
| **Offline export** (default)                | Writes `safe/<chainid>-<name>.json` for manual import into the Safe Transaction Builder.                      | none    | **never**                 |
| **Service submission** (`SAFE_SUBMIT=true`) | Writes the same export, then queues the batch as one `MultiSend` Safe transaction on the transaction service. | yes     | after the service accepts |

The offline export never alerts, and that is deliberate. A file on disk is not a proposal the Safe
has accepted — nobody has claimed a nonce, nothing has been signed, and there is no `safeTxHash` for
a signer to match against their wallet.

`DRY_RUN=true` bypasses submission entirely, so it also sends no alert. The export is the only
output, which is the same no-network-side-effects promise the deploy and configure targets make.

### Setup

| Variable            | Needed for           | Notes                                                                                                                                         |
| ------------------- | -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `SAFE_SUBMIT`       | Submission           | `true` opts in; `false` or unset selects offline export.                                                                                      |
| `SAFE_MULTISIG`     | Submission           | The Safe to queue on. Submission fails with `SafeMultisigNotSet` if it is missing.                                                            |
| `PRIVATE_KEY`       | Submission           | The proposer. Registered with `vm.rememberKey` so `Safe.sign` can sign the `safeTxHash`; the service recovers the sender from that signature. |
| `SLACK_WEBHOOK_URL` | The alert            | An incoming-webhook URL. Unset or empty means no alert is built or sent; the proposal still goes through.                                     |
| `DRY_RUN`           | Bypassing submission | `true` skips submission and alerts; `false` or unset permits submission only when `SAFE_SUBMIT=true`.                                         |

`SLACK_WEBHOOK_URL` is a credential — treat it like `PRIVATE_KEY`. Add it to `.env` as a 1Password
reference (`SLACK_WEBHOOK_URL="op://vault/item/field"`) so `op run` injects it the same way.
The settings are listed in `.env.example`. Use unquoted `true`/`false` for `SAFE_SUBMIT` and `DRY_RUN` in `.env`, since Make reads them too. The webhook URL is never logged or included in an alert payload.

Both propose targets enable `--ffi`, which both libraries need to shell out to `curl`. Tests keep FFI
disabled by default. The Makefile applies `DRY_RUN` and `SAFE_SUBMIT` after secret injection, so
command-line choices take precedence over `.env`.

```bash
## Export and inspect the batch without submitting or alerting.
make propose-configure-portal-mainnet DRY_RUN=true SAFE_SUBMIT=true

## Queue the reviewed configuration on the Safe specified in .env.
make propose-configure-portal-mainnet SAFE_SUBMIT=true
make propose-configure-lz-adapter-mainnet SAFE_SUBMIT=true
```

Review the plan before queueing: submission creates a signing request, while execution still
requires the Safe's signatures.

### Order of operations

1. An empty batch reverts with `EmptyTransactionBatch`. A rerun that finds every setting already
   applied returns before this (see `ProposeConfigurePortal`), so an unchanged rerun is silent.
2. The export is written, then read back and compared byte for byte. A mismatch reverts with
   `SafeBatchNotPersisted`.
3. If `SAFE_SUBMIT` is not `true`, the run stops here. **No alert.**
4. If `DRY_RUN=true`, the run stops here. **No alert.**
5. `Safe.proposeTransactions` reads the Safe's nonce and `getTransactionHash(...)` over the script's
   RPC connection, packs the calls into one `MultiSendCallOnly.multiSend` under `DelegateCall`,
   signs it with `PRIVATE_KEY` and POSTs it to the transaction service. It reverts on anything but
   a 2xx — see [Failure semantics](#failure-semantics).
6. The `safeTxHash` and the claimed nonce are logged.
7. Only then is the alert built and posted.

### Failure semantics

#### A failed request is not proof of a failed proposal

`Safe.proposeTransactions` reverts with `Safe.ProposeTransactionFailed(status, response)` whenever
the service does not answer 2xx. `status` is what distinguishes the two cases that matter:

| `status` | What happened                                                         | Is it queued? | What to do                                                                                                               |
| -------- | --------------------------------------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------ |
| 2xx      | Accepted.                                                             | yes           | Nothing. Signers have the proposal.                                                                                      |
| non-2xx  | The service rejected it; `response` carries its body.                 | no            | Fix the cause and propose again.                                                                                         |
| `0`      | `curl` got no answer at all — timeout, dropped or refused connection. | **unknown**   | **Open the Safe and look for a pending transaction at the current nonce.** Propose again only if it is genuinely absent. |

**Never rerun a propose target on the assumption that a transport error meant failure.** Queuing does
not advance the Safe's on-chain nonce — that only moves when a transaction is executed — so a second
submission of the same batch lands at the _same_ nonce as the first, and signers are left with two
competing entries to disentangle.

Without `--ffi` the run reverts inside the `vm.ffi` cheatcode before any request is issued; nothing
is queued. There are no automatic retries anywhere in this path.

#### An alert failure never affects the proposal

Once the service has accepted, the proposal exists, and nothing downstream may claim otherwise. The
Slack call is wrapped in a narrow `try` boundary — `Slack.send` goes out through `vm.ffi`, which
reverts outright when the run has no `--ffi` and when `curl` exits non-zero — so every notification
failure is logged and swallowed:

| Situation                                  | Result                                                 |
| ------------------------------------------ | ------------------------------------------------------ |
| `SLACK_WEBHOOK_URL` unset or empty         | Alert skipped. Proposal queued.                        |
| `--ffi` not passed, or no `curl` on `PATH` | Alert failed and logged. Proposal queued.              |
| Webhook request errored                    | Alert failed and logged. Proposal queued.              |
| Request issued                             | Alert reported as **sent**, not delivered — see below. |

There is deliberately **no retry**, and the failure message deliberately does **not** send anyone
back to the propose target — doing so is exactly how a missed notification becomes a duplicate
proposal. When an alert fails, the run says so, repeats that the proposal is queued, and tells the
operator to retry the notification only or to pass the `safeTxHash` to signers by hand. The payload
is logged before sending precisely so that is possible.

**Delivery is never confirmed.** `Slack._post` discards `curl`'s output, so the webhook's response
status is not visible to the script. A `200` and a `404` from Slack are indistinguishable here, and
the logs say "sent", never "delivered". Confirm the message landed in the channel.

### What the alert contains

- **Chain** — EIP-3770 short name and chain ID, or the bare ID on a chain no Safe app serves.
- **Safe**, **Nonce**, **Proposer** — the `SAFE_MULTISIG`, the nonce the proposal claimed (queuing
  does not advance the Safe's on-chain nonce, so this is what a signer will see pending), and the
  address derived from `PRIVATE_KEY`.
- **Operation** — `DelegateCall (MultiSend)`, which is how the Safe executes the batch.
- **Calls** — one line per call: target and selector. No ABI decoding; a signer verifies arguments in
  the Safe UI. At most 20 are listed and the rest are reduced to `+N more`, because a Block Kit
  section caps at 3000 characters.
- **safeTxHash** — rendered in full, never truncated. Matching it against what their wallet shows is
  a signer's whole job.
- **Signing link** — `https://app.safe.global/transactions/tx?safe=<short>:<safe>&id=multisig_<safe>_<hash>`,
  which opens that exact transaction ready to sign. Omitted, rather than emitted dead, on a chain no
  Safe app serves.
- **Export path** — the batch file, so the same wiring can also be reviewed offline.

#### Chain coverage

Submission and links are answered by two separate maps, because the two sets genuinely differ:
`safe-utils`'s own tables (a transaction service and a `MultiSendCallOnly` exist) and
`script/config/SafeAppConfig.sol` (a Safe web app serves the chain). The second stays local
deliberately — gating links on the submodule would let a pin decide which alerts carry one.

| Chain            | ID       | Can submit | Signing link     |
| ---------------- | -------- | ---------- | ---------------- |
| Ethereum         | 1        | yes        | yes (`eth`)      |
| Arbitrum         | 42161    | yes        | yes (`arb1`)     |
| Monad            | 143      | yes        | yes (`monad`)    |
| Base             | 8453     | yes        | yes (`base`)     |
| Sepolia          | 11155111 | yes        | yes (`sep`)      |
| Base Sepolia     | 84532    | yes        | yes (`basesep`)  |
| Monad Testnet    | 10143    | yes        | no — no Safe app |
| Arbitrum Sepolia | 421614   | no         | no               |

On Arbitrum Sepolia, `SAFE_SUBMIT=true` reverts with `Safe.ApiKitUrlNotFound(421614)`; use the
offline export there.

### Testing

Unit tests. No network, no webhook, no `--ffi`:

```sh
forge test --match-path 'test/unit/configure/SafeProposer*.t.sol'
```

- `test/unit/configure/SafeProposer.t.sol` — the offline export a propose run produces by default.
- `test/unit/configure/SafeProposerAlert.t.sol` — mode gating (export-only never submits or alerts;
  dry run bypasses both), acceptance and rejection, missing Safe, missing webhook, alert failure
  containment, the payload itself (Block Kit shape, every field, escaping, truncation, signing link,
  unmapped chain), the value guard, and that the documented chain coverage matches what `safe-utils`
  actually answers for.
- `test/unit/configure/SafeProposerAlertEnvironment.t.sol` — that all four settings are read from the
  environment. A separate file holding one test: forge shares one process environment across a whole
  run and may interleave the tests within a suite, so these variables need exactly one writer to stay
  deterministic.

The two library-facing seams — `SafeProposerBase._submitSafeProposal` around
`Safe.proposeTransactions`, and `_postAlert` around `Slack.send` — are what
`test/harness/SafeProposerAlertHarness.sol` substitutes, so **no test issues a real proposal or a
real alert**. One test opts back into the production `try` boundary with `--ffi` off, to prove an
unavailable transport is contained rather than fatal. `test/harness/SafeProposerHarness.sol` is
pinned to export-only for the same reason. What the libraries do internally — `MultiSend` packing,
request bodies, signature encoding, JSON escaping — is covered by their own suites and is not
reasserted here.

#### End-to-end check (INT-430)

INT-430 already validated a real mainnet proposal to the Engineering multisig from
`evm-m-suite-deployment`; this is the equivalent for PYUSDX and has **not** been run live. To do it:

1. Point `SLACK_WEBHOOK_URL` at a throwaway channel and `SAFE_MULTISIG` at a testnet Safe you control.
2. `SAFE_SUBMIT=true`, on Sepolia or Base Sepolia, with `--ffi`.
3. Confirm the proposal appears in the Safe queue at the nonce and `safeTxHash` the alert reports,
   that the signing link opens it, and that the Slack message actually arrived — the script cannot
   tell you.
4. Repeat with `DRY_RUN=true` and confirm nothing is queued and nothing is posted.

Rejection paths worth exercising live, since only their handling is unit-tested: a `SAFE_MULTISIG`
that is not a Safe on that chain, and a `PRIVATE_KEY` that is not one of its owners. Both should
revert with `Safe.ProposeTransactionFailed` and send no alert.

### Known limitations

- **No delivery confirmation for alerts.** `foundry-slack` discards the webhook response, as above.
- **No request timeouts.** `solidity-http` invokes `curl` without `--connect-timeout` or
  `--max-time`, so a black-holed transaction service hangs the run rather than failing it. Interrupt
  it and check the Safe queue; do not assume nothing was queued.
- **Batched proposals cannot carry value.** `Safe.getProposeTransactionsTargetAndData` packs every
  call at zero value, while the offline export carries whatever the plan built. Rather than let the
  two diverge silently, `TransactionHelper.propose` reverts with `ProposalValueNotSupported` on a
  valued call. Every configuration call this repo proposes is value-free today.
- **One batched transaction, not a per-call option.** `ProposeBase` also offers
  `_proposeIndividually`; PYUSDX's two configure proposals only ever need the batched form.
- **Submission is opt-in.** In `evm-m-suite-deployment` a propose script only ever queues on the
  service. PYUSDX's propose targets have always produced an offline export, and that stays the
  default so no existing runbook changes behaviour under someone's feet.
- **Safe API-key authentication.** Requests carry no `Authorization` header, matching `safe-utils` as
  it stands. If Safe begins requiring a key, submission will start failing with a
  `ProposeTransactionFailed(401, ...)` and the header belongs upstream, not here.

## Portal OFT wrapper decision and runbook

### Decision

`pyusdxPortalOFTWrapper` is the proxy for a **send-only OFT facade for base PYUSDX**. Deploy it on a source chain when Stargate/LayerZero Value Transfer API consumers need an `IOFT` interface for PYUSDX. Direct Portal integrations do not need it. A wrapper is not needed merely to receive a transfer: the receive path is `LayerZeroBridgeAdapter → Portal.receiveMessage`, followed by minting PYUSDX or wrapping the destination extension.

Each instance exposes exactly one immutable `token()` and pins one Portal and LayerZero adapter. Every extension exposed through OFT therefore needs a separate implementation and proxy, even when it shares the Portal. A base-token instance cannot expose an extension by changing a destination mapping. The mapping selects the **destination token**, never the destination wrapper.

The send path is `caller → wrapper.send → Portal.sendToken → LayerZeroBridgeAdapter`. The wrapper pulls the tokens from its caller and approves Portal for the amount. On direct calls the holder approves the wrapper. In the Value Transfer API flow the holder approves the TransferDelegate, which transfers to LZMultiCall; LZMultiCall then approves and calls the wrapper. Portal's sender identity is the wrapper, not the original holder. Keep wrappers unfrozen and account for this router identity when introducing caller-based policies. Do not transfer tokens to a wrapper outside `send`; those transfers are not credited and there is no rescue function.

### Required instances and recorded rollout

The tracked deployment files at baseline `25e270f` record the following base-token wrappers. These are repository records, not a fresh verification of deployed code or configuration.

| Source chain | Chain ID | Recorded proxy                               | Action                                                                                    |
| ------------ | -------- | -------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Ethereum     | 1        | `0x7C527fc6E5f23acC81981BF9033E36C325E7f9C2` | Verify identity, roles and supported routes before onboarding                             |
| Arbitrum     | 42161    | `0x7C527fc6E5f23acC81981BF9033E36C325E7f9C2` | Verify independently on this chain                                                        |
| Monad        | 143      | Zero address                                 | Resolve/deploy and configure under INT-416                                                |
| Base         | 8453     | Zero address                                 | Deploy only if an OFT consumer is being onboarded; suite launch alone does not require it |

[INT-416](https://linear.app/mzero/issue/INT-416/ensure-portaloftwrapper-is-deployed-on-ethereum-arbitrum-and-monad) explicitly tracks Ethereum, Arbitrum and Monad and was still Backlog when read on 8 September 2026. For each approved extension/chain combination, inventory a separate wrapper and route map before exposing it. Zero or absent deployment fields do not prove a contract has never been deployed: reconcile broadcasts and chain state before creating another instance.

### Deployment and configuration

1. Verify the source deployment's PYUSDX, Portal and LayerZero adapter addresses and code. Confirm the represented token, decimals and symbol. `DeployAll` does not deploy the OFT wrapper; use `script/deploy/DeployPortalOFTWrapper.s.sol`.
2. Supply `PORTAL_OFT_WRAPPER_ADMIN` and `PORTAL_OFT_WRAPPER_OPERATOR` using the existing script workflow. Leave `PORTAL_OFT_WRAPPER_TOKEN` empty for base PYUSDX; set it to the extension address for an extension instance. Credentials continue through the existing secret workflow. Preview with `make deploy-portal-oft-wrapper CHAIN=<alias> DRY_RUN=true` before broadcasting. `ScriptBase` suppresses deployment-file writes in Forge script dry-run context; never treat simulated addresses as live deployment evidence.
3. After deployment, verify proxy/implementation code, immutable `token()`, `portal()`, `layerZeroBridgeAdapter()`, decimals, proxy admin and `DEFAULT_ADMIN_ROLE`/`OPERATOR_ROLE`. The script saves base instances under `pyusdxPortalOFTWrapper`; extension instances use `<tokenSymbol>PortalOFTWrapper`. Check symbol uniqueness to avoid overwriting another extension's record.
4. Configure both Portal and LayerZero transport routes: peer adapter, endpoint-ID/chain-ID mapping, supported adapter, gas limits and the required LayerZero libraries/DVNs/executor. Confirm destination Portal mint/wrap readiness and token compatibility. EVM chain IDs and LayerZero endpoint IDs are different identifiers.
5. As the wrapper operator, call `setDestinationToken(uint32 destinationEid, bytes32 destinationToken)` for every supported destination. Encode an EVM token address as a left-zero-padded bytes32. Use the intended remote PYUSDX or extension token address, not a remote wrapper address. Read back `getDestinationToken(eid)` and the adapter's chain mapping. To withdraw a route, use `removeDestinationToken(eid)`.
6. Quote and simulate the exact send with the intended caller, token approval, recipient and native fee. Reverse sends need their own source wrapper and mappings; receive-only destinations do not.

### Verified local quote/send example

`test/unit/portal/oft/PortalOFTWrapper/quoteThenSend.t.sol` executes this direct-call sequence against the actual wrapper and Portal with a local mock bridge adapter:

```solidity
SendParam memory params = SendParam({
    dstEid: destinationEid,
    to: bytes32(uint256(uint160(recipient))),
    amountLD: amount,
    minAmountLD: amount,
    extraOptions: "",
    composeMsg: "",
    oftCmd: ""
});
MessagingFee memory fee = wrapper.quoteSend(params, false);
token.approve(address(wrapper), amount); // Executed by the holder/caller.
(MessagingReceipt memory message, OFTReceipt memory transfer) =
    wrapper.send{value: fee.nativeFee}(params, fee, refundAddress);
```

Amounts use the represented token's local decimals and must be positive and fit uint128. The flow is 1:1; `minAmountLD` cannot exceed the amount. Pay native fees (`payInLzToken=false`, `lzTokenFee=0`). Extra options, compose messages and OFT commands are ignored: execution gas comes from Portal configuration. Requote near execution because bridge fees may change. The returned GUID is Portal's message ID and nonce is zero; it is not a LayerZero endpoint nonce.

Run `forge test --match-path 'test/unit/portal/oft/PortalOFTWrapper/*.t.sol'`. The local example verifies the quote, allowance/pull, source burn, fee forwarding and zero wrapper token balance. It does not prove live Stargate discovery, mainnet route configuration or destination delivery. Existing `sendViaLZMultiCall.t.sol` and `sendViaLayerZeroBridgeAdapter.t.sol` additionally cover routed calling and adapter integration with mocks.

### Explicit follow-ups

- INT-416: reconcile the three named chain inventories against live code and deployment receipts, then complete missing deployments and route configuration.
- Add a reviewed per-token/per-chain inventory plus idempotent wrapper destination mapping configuration/proposal automation. The current Portal/LayerZero configuration builders do not configure wrapper mappings.
- Replace symbol-derived extension wrapper keys with collision-safe token identity if duplicate symbols must be supported.
- For each newly onboarded consumer, run a small-value cross-chain smoke test and retain source/destination receipts; local unit tests are not that rollout evidence.

## Deployment workflow validation

Evidence for the workflow itself, at the time it was gathered. Not an approval of any chain's desired configuration, not a claim that any chain has been reconciled or migrated, and not a freshness guarantee — re-run the checks rather than citing them.

INT-466 was validated with 962 passing tests across 64 suites, including 156 mainnet-fork integration tests and 64 OFT wrapper tests. A Base fork dry run at block 51,022,201 reached `SIMULATION COMPLETE` without broadcasting. Both beacon addresses were matched to successful CREATE3 receipts on all eight chains and cross-checked with factory reads. No live deployment, Safe proposal or Slack message was sent.
