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

## Deployment

### Build (production)

```bash
npm run build
```

### Deploy locally

Start a local Anvil node, then deploy:

```bash
anvil
npm run deploy-local
```

### Deploy to Sepolia

```bash
npm run deploy-sepolia
```

Deployment scripts are in `script/deploy/`. `DeployAll.s.sol` orchestrates the full deployment of PYUSDX, IssuerGateway, SwapFacility, ExtensionBeacon, and ExtensionFactory with their proxy infrastructure. Separate scripts exist for deploying individual extensions (`DeployYieldToOne.s.sol`, `DeployMultiMint.s.sol`).

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
