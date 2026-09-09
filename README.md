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

Configure and propose targets build the same plan and send only settings that differ from the chain.
The plan labels settings `[plan]`, `[skip]`, or `[current state unreadable]`. Unreadable settings stay
planned. An unchanged run broadcasts nothing and writes no Safe batch; any older export is stale.

### Portal and LayerZeroBridgeAdapter

Each peer plan checks the bridge chain ID, peer adapter, supported/default adapter and payload gas
limit. `setBridgeChainId` runs before `setPeer` because changing an existing mapping clears the peer;
the plan restores it even if it matched before the mapping changed.

A mapping that would displace another peer in the same batch fails with `ConflictingBridgeChainId`.
Configure the displaced peer first in a separate run. Displacement of a chain outside the batch is
shown in the plan, including the mapping and peer it will clear.

### LayerZero ULN configuration

Reruns compare the adapter's own `getAppUlnConfig` on the send/receive libraries, including DVN order.
The endpoint's effective config can inherit matching defaults; that does not mean the adapter has
pinned its security configuration. Explicitly no optional DVNs uses `NIL_DVN_COUNT` (255), which the
effective view normalizes to zero. If the app-level getter is unavailable, the route remains planned.

### Replay override

Use `FORCE_REPLAY=true` to send every setting regardless of equality. Reads and plan output remain:

```bash
make configure-portal-mainnet FORCE_REPLAY=true
make propose-configure-lz-adapter-mainnet FORCE_REPLAY=true
```

Signer requirements remain `OPERATOR_ROLE` on Portal and adapter for Portal configuration, and the
adapter's LayerZero delegate for ULN configuration.

### Tests

```bash
forge test --match-path 'test/unit/configure/*Rerun*.t.sol'
forge test --match-path 'test/integration/Configure*Integration.t.sol' # requires MAINNET_RPC_URL
```

The suites cover unchanged and partial reruns, drift, mapping side effects, forced replay and
proposal parity. Fork tests check real Portal/adapter behavior and the ULN app-level getter.

## Multisig alerts

Safe proposals reuse [`safe-utils`](https://github.com/m0-foundation/safe-utils) for batching,
signing and submission, and [`foundry-slack`](https://github.com/m0-platform/foundry-slack) for
Block Kit and transport. Local code handles offline export, mode selection and message content.

### Two modes

| Mode               | Result                                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------- |
| Default            | Export `safe/<chainId>-<name>.json` for Safe Transaction Builder; no submission or alert. |
| `SAFE_SUBMIT=true` | Export, queue one MultiSend transaction, then optionally alert after acceptance.          |
| `DRY_RUN=true`     | Export only, even when submission was requested.                                          |

### Setup

| Variable            | Purpose                                                              |
| ------------------- | -------------------------------------------------------------------- |
| `SAFE_SUBMIT`       | `true` enables service submission; unset/false keeps offline export. |
| `SAFE_MULTISIG`     | Safe executor; required for submission and for migration proposals.  |
| `PRIVATE_KEY`       | Proposer signing key; needed for submission.                         |
| `SLACK_WEBHOOK_URL` | Optional incoming webhook; unset/empty skips alerts.                 |
| `DRY_RUN`           | `true` suppresses submission and alerts.                             |

Keep credentials in the existing 1Password workflow, for example
`SLACK_WEBHOOK_URL="op://vault/item/field"`. Use unquoted `true`/`false` in `.env` because Make reads
these flags too. The propose targets enable `--ffi` and need `curl`; Make applies command-line
`DRY_RUN` and `SAFE_SUBMIT` after secret injection. The webhook URL is never logged.

```bash
make propose-configure-portal-mainnet DRY_RUN=true SAFE_SUBMIT=true # inspect export
make propose-configure-portal-mainnet SAFE_SUBMIT=true             # queue reviewed batch
```

### Failure semantics

The export is written and read back before submission. Empty batches and failed read-back abort.
Unchanged reruns return before export. Submission requires a nonzero Safe and a proposer key.

| Submission result        | Recovery                                                                            |
| ------------------------ | ----------------------------------------------------------------------------------- |
| 2xx                      | Proposal accepted; review and sign in Safe.                                         |
| Non-2xx                  | Inspect `Safe.ProposeTransactionFailed(status, response)`, fix rejection and retry. |
| Status 0 / lost response | Outcome unknown: inspect the Safe queue at the current nonce before retrying.       |

Queuing does not advance the on-chain nonce. Blindly retrying can create competing proposals at that
nonce. Without `--ffi`, no request is issued. There are no automatic retries.

Alert transport errors are caught after proposal acceptance. **Do not rerun the proposal to retry an
alert**; share its `safeTxHash` with signers or retry only the notification. The payload is logged.
`foundry-slack` discards the webhook response, so “sent” does not confirm delivery; check the channel.

### What the alert contains

Chain, Safe, nonce, proposer, MultiSend operation, full `safeTxHash`, export path and a signing link
where supported. Up to 20 call targets/selectors are listed, with a count of the rest. Review call
arguments in Safe.

#### Chain coverage

The pinned library controls service support; `SafeAppConfig` controls web-app links:

| Chain            | ID       | Can submit | Signing link |
| ---------------- | -------- | ---------- | ------------ |
| Ethereum         | 1        | yes        | `eth`        |
| Arbitrum         | 42161    | yes        | `arb1`       |
| Monad            | 143      | yes        | `monad`      |
| Base             | 8453     | yes        | `base`       |
| Sepolia          | 11155111 | yes        | `sep`        |
| Base Sepolia     | 84532    | yes        | `basesep`    |
| Monad Testnet    | 10143    | yes        | no           |
| Arbitrum Sepolia | 421614   | no         | no           |

Use offline export on Arbitrum Sepolia; submission raises `Safe.ApiKitUrlNotFound(421614)`.

### Testing

```bash
forge test --match-path 'test/unit/configure/SafeProposer*.t.sol'
```

Tests cover export, mode gating, proposal rejection, alert failure containment and message content
without issuing real proposals or alerts. PYUSDX's live proposal-to-Slack flow has not been verified.
For a live check, use a testnet Safe and throwaway channel, confirm the queue's nonce/hash, signing
link and message, then confirm `DRY_RUN=true` produces neither submission nor alert.

### Known limitations

- The HTTP dependency has no request timeout. If interrupted, inspect the queue before retrying.
- Library batching packs zero-value calls; `ProposalValueNotSupported` rejects valued calls.
- The pinned Safe client sends no API-key authorization header. Authentication support belongs in
  the shared client if the service requires it.

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
