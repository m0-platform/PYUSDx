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

| Network       | `CHAIN` alias      | Chain ID   | LayerZero EID |
| ------------- | ------------------ | ---------- | ------------- |
| Ethereum      | `mainnet`          | `1`        | `30101`       |
| Arbitrum      | `arbitrum`         | `42161`    | `30110`       |
| Monad         | `monad`            | `143`      | `30390`       |
| Sepolia       | `sepolia`          | `11155111` | `40161`       |
| Arb. Sepolia  | `arbitrum-sepolia` | `421614`   | `40231`       |
| Monad testnet | `monad-testnet`    | `10143`    | `40442`       |
| Anvil         | `localhost`        | `31337`    | —             |

### Build (production)

```bash
npm run build
```

### Deploy

Deploys the full core stack (PYUSDX, IssuerGateway, SwapFacility, ExtensionBeacon/Factory, Portal, LayerZeroBridgeAdapter) via `script/deploy/DeployAll.s.sol`, reading role and config addresses from `.env`. Artifacts are written to `deployments/<chainId>.json`, which the configure and bridge commands consume.

```bash
anvil                 # local only, in a separate shell
make deploy-local     # or: npm run deploy-local
make deploy-mainnet
make deploy-arbitrum
make deploy-monad
make deploy-sepolia   # or: npm run deploy-sepolia
make deploy-monad-testnet
```

Individual extensions have their own targets. `EXTENSION_NAME` is the internal handle recorded in `deployments/<chainId>.json`; MultiMint additionally reads roles and asset caps from `extensions/<chainId>/<EXTENSION_NAME>.json` ([schema](extensions/README.md)).

```bash
make deploy-yield-to-one-mainnet EXTENSION_NAME="<name>"
make deploy-multi-mint-mainnet EXTENSION_NAME="<name>"
make configure-multi-mint-asset-cap-mainnet EXTENSION_NAME="<name>" ASSET=<address> ASSET_CAP=<amount>
```

Swap `-mainnet` for `-arbitrum`, `-sepolia` or `-local`.

### Configure the Portal

Wires each peer chain on the Portal and LayerZeroBridgeAdapter (peer adapter, bridge chain id, supported/default adapter, payload gas limit). The signer must hold `OPERATOR_ROLE` on the Portal and the adapter. `PEERS` is a Solidity `uint32[]` of remote chain IDs; it defaults per target and can be overridden with `PEERS='[...]'`.

```bash
make configure-portal-mainnet     # wires Arbitrum (42161) + Monad (143) as peers
make configure-portal-arbitrum    # wires Ethereum (1) + Monad (143) as peers
make configure-portal-monad       # wires Ethereum (1) + Arbitrum (42161) as peers
make configure-portal-local
```

Peering is reciprocal: adding a chain means re-running the configure target on every existing peer as well as on the new chain.

### Configure LayerZero security

Applies the LayerZero V2 ULN/DVN `setConfig` for each peer route. The signer must be the adapter's LayerZero delegate.

Routes between Ethereum and Arbitrum pin the LayerZero default stack of `[LayerZero Labs, Google]`. Google runs no DVN on Monad, so every Monad route uses `[LayerZero Labs, Nethermind]` instead; testnet routes use `[LayerZero Labs]` alone.

```bash
make configure-lz-adapter-mainnet
make configure-lz-adapter-arbitrum
make configure-lz-adapter-monad
make configure-lz-adapter-local
```

### Propose via Safe multisig

When the Portal/adapter roles are held by a multisig, the `propose-*` variants write a Safe Transaction Builder batch to `safe/<chainId>-*.json` (no broadcast) for import into the Safe UI.

```bash
make propose-configure-portal-mainnet
make propose-configure-portal-arbitrum
make propose-configure-portal-monad
make propose-configure-lz-adapter-mainnet
make propose-configure-lz-adapter-arbitrum
make propose-configure-lz-adapter-monad
```

### Bridge PYUSDX cross-chain

Bridges PYUSDX through the Portal using the default bridge adapter (`script/execute/Bridge.s.sol`). `AMOUNT` is in base units (6 decimals); `RECIPIENT` is optional and defaults to the signer. The signer must hold the PYUSDX being bridged and enough native gas for the LayerZero fee, which is quoted automatically.

```bash
make bridge-mainnet-to-arbitrum AMOUNT=1000000
make bridge-arbitrum-to-mainnet AMOUNT=1000000 RECIPIENT=0x1111111111111111111111111111111111111111
make bridge-mainnet-to-monad    AMOUNT=1000000
make bridge-monad-to-mainnet    AMOUNT=1000000
make bridge-local-to-arbitrum   AMOUNT=1000000
```

## CI

GitHub Actions workflows run on push and pull requests:

| Workflow               | Description                                      |
| ---------------------- | ------------------------------------------------ |
| `coverage.yml`         | Build + test coverage (reported on PRs via lcov) |
| `test-gas.yml`         | Gas report (diff reported on PRs)                |
| `test-fuzz.yml`        | Fuzz tests (10,000 runs)                         |
| `test-integration.yml` | Integration tests                                |
| `test-invariant.yml`   | Invariant tests (depth 250)                      |

Repository secrets required: `MNEMONIC_FOR_TESTS`, `MAINNET_RPC_URL`.

## License

BUSL-1.1
