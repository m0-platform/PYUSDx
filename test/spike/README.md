# Spike: converting an ExtensionBeaconProxy to self-managed (UUPS) upgrades

Question: can a single deployed MultiMint instance leave the shared ExtensionBeacon and manage its own
upgrades without redeploying the proxy? Answer: yes. `BeaconToUUPS.t.sol` performs the conversion
end to end against the real `ExtensionBeacon`, `ExtensionBeaconProxy`, and `MultiMint`.

## Why it works

`ExtensionBeaconProxy._implementation()` reads the ERC-1967 implementation slot first and only falls back to
the beacon when that slot is zero. `Extension.pinVersion()` writes that slot. So a pinned proxy is already a
plain ERC-1967 proxy, and any implementation that can rewrite the slot from inside a delegatecall (UUPS)
takes over upgrade control. Nothing about the proxy bytecode has to change.

## The path (three transactions)

1. M0 `BEACON_MANAGER_ROLE`: `registerImplementation(bridge)` on the MultiMint beacon, and in the same
   batch `registerImplementation(currentMultiMint)` again so `latest` is unchanged. The bridge is
   MultiMint plus an `upgradeToAndCall` gated by the extension's own `VERSION_MANAGER_ROLE`.
2. Extension `VERSION_MANAGER_ROLE`: `pinVersion(bridgeVersion)`. Proxy flips to direct mode.
3. Extension `VERSION_MANAGER_ROLE`: `upgradeToAndCall(anyERC1822Implementation, data)`. From here M0 is
   out of the loop. The test does this twice: to a self-managed MultiMint, and to a `StandaloneToken`
   with no Extension base at all (issuer mint/burn), with balances, allowances, metadata, and roles intact.

## What breaks or needs care

- Contract size. MultiMint is 24,252 bytes at the repo's 2,933 optimizer runs, 324 bytes under EIP-170.
  Every bridge variant tried (OZ `UUPSUpgradeable`, a hand-rolled minimal one, with pin/unpin removed)
  lands 1.3 to 2.0 KB over. At 200 runs everything fits with about 2 KB to spare. The bridge needs its own
  compile profile, or MultiMint has to shed code first. `via_ir` makes it worse.
- The beacon is shared. Registering the bridge makes it `latest` for every beacon-mode MultiMint until the
  original is re-registered, and afterwards it remains a pinnable version for all of them. The scoped
  variant (`MultiMintLeanBridge` with an `allowedProxy` immutable) closes that: one bridge per departing
  extension.
- `upgradeToAndCall` reverts in beacon mode (OZ's `onlyProxy` reads the empty implementation slot), so
  pinning is a hard prerequisite, not a nicety.
- The bridge alone is not a one-way door. `unpinVersion` still works on it and returns the proxy to the
  beacon. The implementation the owner installs next should override both pin functions.
- Once UUPS, the next target must answer `proxiableUUID()`. Plain MultiMint is rejected.
- Backing does not move by itself. After leaving, the PYUSDX and any USDC/PYUSD held by the contract are
  ordinary balances under the new code's control. The migration of that backing (unwrap, redeem at the
  issuer, re-collateralize) is a separate operation the new implementation has to expose.
- `ExtensionFactory.isApprovedExtension` keeps returning true for the address, so the real SwapFacility
  would still route into code M0 no longer controls. `registerExtension(addr, NONE)` by
  `FACTORY_MANAGER_ROLE` should be part of the exit. Not exercised here (tests use `MockSwapFacility`).
- The test contracts exceed the size limit at the default profile, so a `--sizes` build that includes
  `test/` will fail. They are spike material, not deployables.

## Running

```
forge test --match-path test/spike/BeaconToUUPS.t.sol
FOUNDRY_OPTIMIZER_RUNS=200 forge test --match-path test/spike/BeaconToUUPS.t.sol
forge build --sizes | grep MultiMint
```
