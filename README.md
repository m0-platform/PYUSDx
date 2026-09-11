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

`deploymentConfigs/<chainId>/protocol.json` supplies roles and settings for deployment and role migration. `deployments/<chainId>.json` records deployed contract addresses. See the [configuration guide](deploymentConfigs/README.md#deployment-configuration).

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

Deploys the core suite using `deploymentConfigs/<chainId>/protocol.json` and saves contract addresses to `deployments/<chainId>.json`. For a new chain, copy `deploymentConfigs/example-protocol.json` and set the chain ID, initial role holders and settings.

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

Use the full token name for `EXTENSION_NAME` and quote names containing spaces. MultiMint reads roles and asset caps from `deploymentConfigs/<chainId>/<EXTENSION_NAME>.json`; see the [schema](deploymentConfigs/README.md).

```bash
make deploy-yield-to-one-mainnet EXTENSION_NAME="<name>"
make deploy-multi-mint-mainnet EXTENSION_NAME="<name>"
make configure-multi-mint-asset-cap-mainnet EXTENSION_NAME="<name>" ASSET=<address> ASSET_CAP=<amount>
```

Swap `-mainnet` for `-arbitrum`, `-sepolia` or `-local`.

### Configure the Portal

Configures Portal and LayerZeroBridgeAdapter peers. The signer needs `OPERATOR_ROLE` on both. `PEERS` is an array of remote EVM chain IDs; override the defaults with `PEERS='[...]'`. [Reruns](#configuration-reruns) send only changed settings.

```bash
make configure-portal-mainnet     # wires Arbitrum (42161) + Monad (143) + Base (8453) as peers
make configure-portal-arbitrum    # wires Ethereum (1) + Monad (143) as peers
make configure-portal-monad       # wires Ethereum (1) + Arbitrum (42161) as peers
make configure-portal-base        # wires Ethereum (1) as peer
make configure-portal-local
```

Peering is reciprocal: adding a chain means re-running the configure target on every existing peer as well as on the new chain.

### Configure LayerZero security

Applies LayerZero V2 ULN/DVN settings for each peer route. The signer must be the adapter's LayerZero delegate. [Reruns](#configuration-reruns) send only changed routes.

Routes between Ethereum, Arbitrum and Base pin the LayerZero default stack of `[LayerZero Labs, Google]`. Google runs no DVN on Monad, so every Monad route uses `[LayerZero Labs, Nethermind]` instead; testnet routes use `[LayerZero Labs]` alone.

```bash
make configure-lz-adapter-mainnet
make configure-lz-adapter-arbitrum
make configure-lz-adapter-monad
make configure-lz-adapter-base
make configure-lz-adapter-local
```

### Propose via Safe multisig

Use `propose-*` when a Safe holds the required roles. By default, these export `safe/<chainId>-*.json` for import into Safe Transaction Builder. Set `SAFE_SUBMIT=true` to queue the proposal; see [submission and alerts](#multisig-alerts).

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

Update the desired holders in `deploymentConfigs/<chainId>/protocol.json` and list holders to remove in `migration.outgoingHolders`. Review the config diff, then:

```bash
make migrate-roles-base DRY_RUN=true    # preview for the current signer
make migrate-roles-base                 # execute that signer's portion
make verify-roles-base                  # check all remaining work; no key needed
make propose-migrate-roles-base         # Safe alternative; requires SAFE_MULTISIG
```

`DRY_RUN=true` still requires a signing key and reverts with `NothingExecutable` if that signer cannot act. Use `verify-roles` for a keyless check.

Each signer executes only the calls they have authority for; other calls are marked `[defer]`. Repeat with the required signers, then verify. After an adapter operator change, the incoming operator must restore the LayerZero delegate.

Verification checks the config, including listed outgoing holders; it cannot discover unlisted role holders. See the [role migration runbook](deploymentConfigs/README.md#role-migration) for scope and ordering. Individual extension instances are outside this migration’s scope.

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

## CI

Pull requests and pushes to `main` run coverage and gas reports. Standalone fuzz, integration and invariant workflows are disabled (`*.yml.disabled`); their tests remain part of full-suite runs.

Repository secrets required: `MNEMONIC_FOR_TESTS`, `MAINNET_RPC_URL`.

## Configuration reruns

Configure and propose targets send only settings that differ from the chain. An unchanged run sends nothing and writes no Safe batch; don't reuse an older export. Unreadable settings remain in the plan for review.

Use `FORCE_REPLAY=true` to resend every setting. If a bridge-chain mapping conflicts with another peer in the batch, configure the displaced peer separately first. Review the plan for displaced peers outside the batch: their mappings will be cleared.

```bash
make configure-portal-mainnet FORCE_REPLAY=true
```

## Multisig alerts

Set `SAFE_MULTISIG` to the Safe holding authority for submission or migration proposals. Offline export is the default; submission also requires `PRIVATE_KEY` and `curl`.

```bash
make propose-configure-portal-mainnet DRY_RUN=true  # inspect without submitting
make propose-configure-portal-mainnet SAFE_SUBMIT=true
```

Set `SLACK_WEBHOOK_URL` through the existing 1Password workflow for optional alerts after acceptance. Use unquoted `true`/`false` for flags in `.env`. `DRY_RUN=true` suppresses submission and alerts.

- Review and sign accepted proposals in Safe; submission does not execute them.
- If submission times out or is interrupted, check the Safe queue before retrying.
- If an alert fails, share the proposal's `safeTxHash`; do not resubmit just to retry the alert.
- Arbitrum Sepolia supports offline export only. Monad Testnet alerts have no signing link.

Submission uses [safe-utils](https://github.com/m0-foundation/safe-utils); alerts use [foundry-slack](https://github.com/m0-platform/foundry-slack).

## Portal OFT wrapper

Deploy a wrapper only when a consumer needs an `IOFT` send interface. Direct Portal integrations and receive-only destinations do not need one. Each represented token needs its own wrapper.

`DeployAll` does not deploy wrappers. Set `PORTAL_OFT_WRAPPER_ADMIN` and `PORTAL_OFT_WRAPPER_OPERATOR`; leave `PORTAL_OFT_WRAPPER_TOKEN` empty for PYUSDX or set it to the extension address.

```bash
make deploy-portal-oft-wrapper CHAIN=mainnet DRY_RUN=true
make deploy-portal-oft-wrapper CHAIN=mainnet
```

Before use, verify the deployed token, Portal, adapter and roles, configure Portal/LayerZero routes, then set each wrapper destination with `setDestinationToken(destinationEid, destinationToken)`. Encode the destination token address as a left-zero-padded `bytes32`, not a wrapper address; the ID is a LayerZero EID, not an EVM chain ID.

Read back routes with `getDestinationToken(eid)`; remove them with `removeDestinationToken(eid)`. Extension wrapper records use token symbols, so check for duplicates before deploying.

Keep wrappers unfrozen: Portal sees the wrapper as the sender. Approve the wrapper, quote the fee, then call `send`. Never transfer tokens directly to it: there is no rescue function. See the [quote/send test](test/unit/portal/oft/PortalOFTWrapper/quoteThenSend.t.sol) for a complete example. Validate each live route with a small transfer before onboarding consumers.

## License

BUSL-1.1
