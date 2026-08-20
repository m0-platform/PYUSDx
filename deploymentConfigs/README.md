# Extension Deployment Configs

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
