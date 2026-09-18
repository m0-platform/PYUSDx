# Extension Deployment Configs

Per-extension deployment configuration for MultiMint extensions, one JSON file per extension
per chain:

```
deploymentConfigs/<chainid>/<extension-name>.json
```

`<extension-name>` must be the full token name, matching `tokenName`, `extensionName` and
`EXTENSION_NAME`. It seeds the CREATE3 salt and is recorded in `deployments/<chainid>.json`.
Do not substitute the token symbol.

The handle must be unique per chain and is used **verbatim** — casing and whitespace are part
of the salt, so `concusd` and `Concrete USD` are different extensions at different addresses.
Match the handle already recorded in `deployments/<chainid>.json` when redeploying or
configuring an existing extension; chain 1 uses `Concrete USD`. Quote any handle containing
spaces on the command line (`EXTENSION_NAME="Concrete USD"`).

Committing the file and reviewing it in a PR **is** the deployment review: every address and
cap that will go on chain is in this one document.

## Workflow

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

## Schema

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

## Role migration

For MultiMint, edit the existing file's role addresses to their desired final holders and add:

```json
"migration": {
  "outgoingHolders": ["0x0000000000000000000000000000000000000001"]
}
```

Replace the example with all known holders that should lose superseded roles. Addresses still desired
for a particular role retain it. Unknown holders cannot be discovered by these scripts because
AccessControl is not enumerable. The list must be non-empty and contain no zero addresses.

YieldToOne uses the same migration file layout: `extensionName`, `tokenName`, `tokenSymbol`, optional
`chainId`, `migration.outgoingHolders`, and these `roles` fields: `admin`, `freezeManager`, `pauser`,
`versionManager`, `yieldRecipientManager`, `yieldRecipient`. Omit `assetCapManager` for YieldToOne;
MultiMint requires it. All desired addresses must be nonzero. This does not change how YieldToOne is deployed.

```bash
make migrate-extension-roles CHAIN=base EXTENSION_NAME="Confidential USD" DRY_RUN=true
make migrate-extension-roles CHAIN=base EXTENSION_NAME="Confidential USD"
make verify-extension-roles CHAIN=base EXTENSION_NAME="Confidential USD"
```

The chain selects the JSON and deployment record automatically. `EXTENSION_CONFIG` optionally overrides
the config path, but the file must still identify the same full token name. Preflight checks the record,
factory registration/type, token metadata and PYUSDX/SwapFacility wiring before changing anything.

Migration grants missing roles, checks membership, updates the yield recipient, then revokes old roles.
The executing admin leaves last. Missing authority is logged and skipped, allowing a later run by another
holder to finish. A pending recipient change retains old roles. A transaction failure or unreadable state
aborts; it is never silently skipped. Direct transactions are not atomic, so verify after mined execution
and rerun if interrupted. Completed changes are skipped.

Changing the yield recipient uses the existing contract setter, which claims accrued yield for the old
recipient unless it is frozen. In that case the contract leaves the pending yield for the new recipient.
Pause/freeze flags, version pins, collateral caps/lists and replace-asset permissions remain unchanged.
Collateral fields in the deployment JSON do not gate migration. Core-suite roles, beacon governance,
PYUSDX earner enrollment and ProxyAdmin ownership are outside this extension migration.

No Safe proposals or JSON exports are generated. The verifier uses the same preflight and fails while
required roles, listed-holder removals or the yield recipient remain outstanding. Tests keep all fixtures
in memory and do not write into deployment/configuration directories.
