# Deployment configs

This directory stores deployment inputs and role-migration targets. Deployed contract addresses
are recorded separately in `deployments/<chainId>.json`.

```text
deploymentConfigs/<chainId>/protocol.json          # Protocol deployment and role migration
deploymentConfigs/<chainId>/<full token name>.json # MultiMint deployment and extension role migration
```

Start with [example.json](example.json) for MultiMint or
[example-protocol.json](example-protocol.json) for the protocol. Replace the example addresses
and values before use. Keep credentials in the [1Password setup](../README.md#environment).
Editing a config does not update deployed contracts. Apply changes with the relevant script.

## Extension deployment configs

Use the full ERC20 token name for the filename stem, `extensionName`, `tokenName`, and
`EXTENSION_NAME`. Set all four explicitly when copying the example. Use `tokenSymbol` only
for the ERC20 symbol.

`EXTENSION_NAME` is the CREATE3 salt input and the deployment-record key. Casing and spaces
affect the deployed address. Keep the existing name when working with a deployed extension,
and quote names containing spaces, such as `EXTENSION_NAME="Concrete USD"`.

### Workflow

1. Collect the client's role addresses, collateral token addresses, and asset caps.
2. Add `deploymentConfigs/<chainId>/<full token name>.json` and review the values in a PR.
3. After merge, deploy on the selected chain. For Ethereum mainnet:

   ```bash
   make deploy-multi-mint-mainnet EXTENSION_NAME="<full token name>"
   ```

   The deployment sets the initial asset caps and registers the extension with SwapFacility.

4. The PYUSDX earner manager enrolls the extension for yield with
   `pyusdx.setAccountInfo(extension, earnerRateBps, feeRateBps, claimRecipient)`.
   This is a separate post-deployment operation.

### Schema

[example.json](example.json) shows the JSON structure. These fields control the extension:

| Field                         | Meaning                                                                                                                                                                     |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `extensionName`, `tokenName`  | Full ERC20 name. Both must match `EXTENSION_NAME` and the filename stem.                                                                                                    |
| `roles.admin`                 | Holds `DEFAULT_ADMIN_ROLE` and manages role assignments.                                                                                                                    |
| `roles.assetCapManager`       | Adds, changes, or disables collateral asset caps.                                                                                                                           |
| `roles.freezeManager`         | Freezes and unfreezes accounts.                                                                                                                                             |
| `roles.pauser`                | Pauses and unpauses the extension.                                                                                                                                          |
| `roles.versionManager`        | Pins or unpins the extension's implementation version.                                                                                                                      |
| `roles.yieldRecipient`        | Receives the extension's yield.                                                                                                                                             |
| `roles.yieldRecipientManager` | Changes the yield recipient.                                                                                                                                                |
| `assets`                      | Initial collateral list. Must contain at least one asset.                                                                                                                   |
| `assets[].symbol`             | A label for reviewers. The script does not read it.                                                                                                                         |
| `assets[].address`            | Collateral token address.                                                                                                                                                   |
| `assets[].cap`                | Maximum collateral balance, in that asset's base units. For six-decimal USDC, 100 million USDC is `100000000000000`. This limits the total balance, not an individual swap. |
| `replaceAssetWhitelist`       | Addresses allowed to call `replaceAsset` to exchange PYUSDX for held collateral. Omit it or use `[]` to allow any caller.                                                   |

Extensions use beacon proxies and have no individual ProxyAdmin. The beacon manager registers
new implementation versions. Each extension's `roles.versionManager` can pin it to a registered
version or unpin it to follow the latest version. Pinned extensions do not follow new versions.

### Extension role migration

Edit `roles` in the extension config and add the required `migration.outgoingHolders` array.
Use an empty array to retain existing holders:

```json
{
  "migration": { "outgoingHolders": [] }
}
```

List an address to remove its superseded roles. MultiMint requires `assetCapManager`;
omit that field for YieldToOne. YieldToOne deployment reads environment variables; create
a JSON config with its token name, roles, and migration block before migrating its roles.
Keep the filename stem, `extensionName`, `tokenName`, and `EXTENSION_NAME` equal.

Run `migrate-extension-roles`, then `verify-extension-roles`, passing `CHAIN` and
`EXTENSION_NAME` as shown in the [extension migration commands](../README.md#migrate-extension-roles).
`DRY_RUN=true` simulates the migration; omitting it broadcasts transactions.

Outgoing signers renounce their own superseded roles without needing admin authority.
They keep those roles until the incoming holders have them.

Reruns skip completed changes. The script warns and skips changes the signer cannot make;
rerun with a signer holding the required role. It retains old roles if the yield recipient
cannot be updated. If the executing admin is listed for removal, it is removed last.
Changing the yield recipient may pay accrued yield to the previous recipient.

Verification fails while changes remain. It checks configured targets and listed outgoing
holders, without discovering additional holders.

## Deployment configuration

### Protocol configuration

`protocol.json` supplies roles and settings to `DeployAll` and the protocol role-migration
scripts. For a new deployment, set the initial role holders. For an existing deployment,
edit the role addresses to the migration targets and review the diff before applying it.
Only the settings listed under [migration scope](#what-is-covered) change during migration.

Protocol deployment settings come from JSON. Keep `PRIVATE_KEY`, RPC URLs, verifier URLs,
and environment variables used by other scripts in the existing `.env` and `op run` setup.

#### Workflow

1. Copy `deploymentConfigs/example-protocol.json` to
   `deploymentConfigs/<chainId>/protocol.json`. Set `chainId`, addresses, and limits for that chain.
   Use `PROTOCOL_CONFIG` to select a different file if needed; its `chainId` must still match.
2. Run the [config tests](#tests) and review the diff. The tests discover chain configs
   from this directory; no chain list needs updating.
3. Simulate deployment, inspect the printed config, then deploy. For Base, using
   `deploymentConfigs/8453/protocol.json`:

   ```bash
   make deploy-base DRY_RUN=true
   make deploy-base
   ```

   For another supported network, use its `deploy-*` target from the [Makefile](../Makefile).
   A new network also needs an RPC alias and a deployment target before these commands apply.

Missing files or required keys, an incorrect chain ID, and invalid values fail before deployment.

#### Schema

[example-protocol.json](example-protocol.json) defines the file structure. The following
notes explain permissions and values that need care when filling it in:

| Field                             | Meaning                                                                                            |
| --------------------------------- | -------------------------------------------------------------------------------------------------- |
| `chainId`                         | Must match the target chain.                                                                       |
| `pyusdx.name`, `pyusdx.symbol`    | Nonempty ERC20 name and symbol.                                                                    |
| Each component's `admin`          | Holds `DEFAULT_ADMIN_ROLE` and initially owns the component's ProxyAdmin, which controls upgrades. |
| `pyusdx.earnerManager`            | Enrolls extensions for yield and receives a mint rate limit.                                       |
| `pyusdx.rateManager`              | Holds `RATE_LIMIT_MANAGER_ROLE`.                                                                   |
| `pyusdx.earnerManagerRateLimit`   | Earner-manager mint limit, in PYUSDX base units with six decimals.                                 |
| `issuerGateway.operator`          | Proposes mints and burns.                                                                          |
| `issuerGateway.executor`          | Executes matured mint proposals.                                                                   |
| `issuerGateway.mintDelay`         | Seconds before a mint proposal can execute. Zero is allowed.                                       |
| `issuerGateway.mintTTL`           | Seconds a matured mint proposal remains executable. Must be positive.                              |
| `extensionFactory.admin`          | Also holds the admin role on both beacons and owns their ProxyAdmins.                              |
| `extensionFactory.factoryManager` | Holds `FACTORY_MANAGER_ROLE` on the factory and `BEACON_MANAGER_ROLE` on both beacons.             |
| `portal.operator`                 | Holds the role required by `configure-portal-*`.                                                   |
| `portal.fallbackRecipient`        | Receives tokens whose delivery cannot be completed. Must be nonzero.                               |
| `layerZeroBridgeAdapter.endpoint` | The chain's LayerZero V2 endpoint address.                                                         |
| `layerZeroBridgeAdapter.operator` | Holds the adapter operator role and is the LayerZero delegate used by `configure-lz-adapter-*`.    |

The `pauser`, `freezeManager`, and `forcedTransferManager` fields assign their corresponding
roles. Pauser roles do not grant upgrade authority.

#### Validation

Use nonzero addresses and nonempty token names and symbols. Rate-limit capacities and
`mintTTL` must be positive. A refill rate cannot exceed its capacity; zero refill and zero
mint delay are allowed. Mint delay and TTL must fit `uint32`; rate-limit values must fit `uint128`.

Numbers may be JSON numbers or quoted decimal strings. Quote integers above `2^53` to
preserve them in tooling that uses double-precision numbers.

### Role migration

Review the target role addresses and outgoing holders in the deployed chain's `protocol.json`.
For Base:

```bash
$EDITOR deploymentConfigs/8453/protocol.json
make migrate-roles-base DRY_RUN=true
make migrate-roles-base
make verify-roles-base
```

The first migration command simulates using the configured `PRIVATE_KEY`. The second broadcasts
changes that signer can make. Verification is read-only, needs no signer key, and reports
remaining changes regardless of the signer's permissions.

#### Migration fields

`DeployAll` ignores `migration` and `portalOFTWrapper`. For role migration:

| Field                       | Requirement                                                                                                                                                       |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `migration.outgoingHolders` | Optional list of holders whose superseded roles and earner buckets should be removed. Omit it or use `[]` to retain existing holders. Zero addresses are invalid. |
| `portalOFTWrapper.admin`    | Required when `deployments/<chainId>.json` records a `pyusdxPortalOFTWrapper`.                                                                                    |
| `portalOFTWrapper.operator` | Required under the same condition.                                                                                                                                |

An empty outgoing-holder list does not prevent changes to ProxyAdmin ownership, the earner
manager and its incoming bucket, the fallback recipient, or the LayerZero delegate.
These still move to their configured targets.

List known outgoing holders explicitly. The scripts do not discover holders from role logs.
A listed holder retains any role for which it is still the configured target. Migration
removes superseded earner buckets but preserves buckets for current issuers. If issuer
membership cannot be read, planning stops.

#### What is covered

Protocol role migration covers named roles and `DEFAULT_ADMIN_ROLE` on PYUSDX, IssuerGateway,
SwapFacility, ExtensionFactory, both beacons, Portal, LayerZeroBridgeAdapter, and the recorded
base PortalOFTWrapper. It also updates `earnerManager`, the earner bucket, `fallbackRecipient`,
ProxyAdmin owners, and the LayerZero delegate. Beacon roles use the `extensionFactory` holders;
each ProxyAdmin follows its component's `admin`.

Before planning changes, the scripts check deployed code, suite wiring, the configured
endpoint, and PYUSDX `ISSUER_ROLE` membership for IssuerGateway and Portal.

Protocol migration and verification do not cover:

- Individual extension instances or per-token OFT wrappers. Use the
  [extension migration](#extension-role-migration) for extension instances.
- Token names and symbols, mint delay and TTL, or IssuerGateway and Portal rate limits.
  These are deployment inputs. Changing them on a deployed chain requires a separate operation.
  Only the earner bucket is part of role migration.

The base PortalOFTWrapper is deployed separately using `PORTAL_OFT_WRAPPER_ADMIN` and
`PORTAL_OFT_WRAPPER_OPERATOR`. Its JSON block supplies migration targets.
See the [wrapper documentation](../README.md#portal-oft-wrapper).

#### Signers and reruns

One signer may not hold every required role. The script marks changes it cannot execute
as `[defer]` and fails with `NothingExecutable` if it cannot make any remaining change.
Permissions granted during a run become available to the planner on a later invocation.

1. Set the `PRIVATE_KEY` reference in the existing 1Password setup to an outgoing holder.
   Simulate with `make migrate-roles-base DRY_RUN=true`, inspect the plan, then run
   `make migrate-roles-base`.
2. For remaining changes, select a holder of the required role. Update the `PRIVATE_KEY`
   reference to that signer and repeat the simulation and execution. This may be an incoming
   holder that received a role in the previous run.
3. Repeat for other required signers, then run `make verify-roles-base`.

The migration keeps roles needed for pending work and hands over default-admin roles last.
It configures the incoming earner bucket before changing `earnerManager`. Revoking or
renouncing a LayerZero operator role clears the delegate, so the incoming operator must
restore it afterwards. ProxyAdmin ownership transfers in one step without an acceptance transaction.

#### Safe multisig

`make propose-migrate-roles CHAIN=<rpc-alias>` writes `safe/<chainId>-migrate-roles.json`
for the Safe Transaction Builder. Set `SAFE_MULTISIG` to the Safe that holds the required roles.
The plan uses the Safe's permissions to select transactions.

See [multisig setup](../README.md#multisig-alerts) for export, `SAFE_SUBMIT`, and alerts.
After the Safe executes the batch, run `verify-roles` to check for remaining changes.

#### Verification limits

`verify-roles` fails with `MigrationIncomplete` while changes remain. Unreadable state also
fails verification. A pass checks configured targets and listed outgoing holders at the
block read. It does not establish that the targets are correct or that no other holders exist.

To find additional holders, inspect historical `RoleGranted` and `RoleRevoked` events and
check current membership. Review unexpected holders before deciding whether to retain them
or add them to `migration.outgoingHolders`.

### Deployment records

`DeployAll` records shared beacon addresses as `yieldToOneBeacon` and `multiMintBeacon` in
`deployments/<chainId>.json`. Individual extension addresses are stored in the
`extensionNames` and `extensionAddresses` arrays, keyed by `EXTENSION_NAME`.

Existing records must include all fields written by the deployment scripts. Use the zero
address for an undeployed component, including `pyusdxPortalOFTWrapper`. Missing fields
cause reads and updates to fail; review and repair an incomplete record before rerunning.

The beacon manager can register new extension versions. The beacon contract itself has a
separate ProxyAdmin owned by `extensionFactory.admin`. Registering a version and upgrading
the beacon contract require different permissions.

### Tests

The deployment unit tests check config validation, checked-in chain configs, and deployment
record handling. They require no RPC connection:

```bash
forge test --match-path "test/unit/deploy/*.t.sol"
```
