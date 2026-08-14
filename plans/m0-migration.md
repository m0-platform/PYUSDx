# Multisig migration runbook — remaining M0-owned PYUSDx contracts

Hand the six contracts still controlled by the M0 deployer EOA over to the M0 Main V2
multisig. PYUSDx and IssuerGateway are already done and are **not** in scope here —
see [moonpay-migration.md](moonpay-migration.md).

Contract addresses and ProxyAdmins are identical on all chains (deterministic CREATE3
deploys); implementations differ. Verified on-chain 2026-08-14: all six contracts have
every role and every ProxyAdmin on the Deployer, identically on all three chains.

| Chain                | Alias      | Status                |
| -------------------- | ---------- | --------------------- |
| Ethereum mainnet (1) | `mainnet`  | done — verified 40/40 |
| Arbitrum One (42161) | `arbitrum` | done — verified 40/40 |
| Monad (143)          | `monad`    | done — verified 40/40 |

All three chains are migrated; this runbook is retained as the procedure for any
future chain and as the record of how these were done. Per-contract transaction
hashes are in the "PYUSDx - Roles transfer" Notion page.

After this migration the Deployer holds no admin or upgrade rights on any of the
eight contracts, but **is not retired** — it keeps `PAUSER` on SwapFacility and
Portal, `OPERATOR` on Portal and the LayerZero adapter, the LayerZero endpoint
delegate, and Portal's `fallbackRecipient`.

## Decisions taken

- **PAUSER stays on the Deployer** (`0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB`) so
  an emergency pause does not need 3/5 signatures.
- **`OPERATOR` stays on the Deployer everywhere** — Portal and the LayerZero adapter.
  No `OPERATOR` is moved by this migration.
- Roles that stay are never touched below; the verifier asserts they are unchanged.
- **SwapFacility is in scope.** It was not on the original list but holds
  `DEFAULT_ADMIN` + `PAUSER` + ProxyAdmin on the Deployer on all three chains.
- **`FACTORY_MANAGER` and `BEACON_MANAGER` move** — rare, high-impact actions.
- **Portal `fallbackRecipient` stays on the Deployer** and is not touched. The
  verifier asserts it is unchanged.

## Why fallbackRecipient is left alone

The candidate target `0xb7A9B5f301eF3bAD36C2b4964E82931Dd7fb989C` (Engineering
multisig) is not one identity across chains:

| Chain    | State at that address                                                      |
| -------- | -------------------------------------------------------------------------- |
| mainnet  | Safe, threshold **3**, signers Ian / Jordan / Toni / Pierrick / Iryna      |
| arbitrum | Safe, threshold **2**, signers Toni / Pierrick / Iryna — **different set** |
| monad    | **No contract. codesize 0, nonce 0.**                                      |

`Portal.sol:196-206` sends PYUSDX to `fallbackRecipient` when the intended recipient is
frozen, so pointing it at an address with no contract on Monad would make those funds
unrecoverable. Left as-is pending a decision on a per-chain target.

**This means a value-receiving address remains on a single deployer key after this
migration completes.** It is a known, accepted gap, not an oversight.

## Addresses

| What                      | Address                                      |
| ------------------------- | -------------------------------------------- |
| M0 Main V2 multisig       | `0x48670B46380FE1645f0E3e821a25162dB2589D19` |
| M0 deployer (outgoing)    | `0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB` |
| SwapFacility              | `0x0bC305e7e13113cAEd3f5486849e9518a1cC4173` |
| SwapFacility PA           | `0xc421cCeA39cC9858ba613052e84f04Cc2B0DF53B` |
| ExtensionFactory          | `0x25c8aFfC5a63D8E047c12918C0438ABA5aA09c2A` |
| ExtensionFactory PA       | `0x365B54D9D69eB78B6bB1C9e5E0C7C9a142B24096` |
| Portal                    | `0xaAD1466fE33d373189FB9dcC47270e608FeEE8A7` |
| Portal PA                 | `0x65ce3f3c4732f171E3E7b759F4249dC9cD49a68F` |
| LayerZeroBridgeAdapter    | `0xEfF09B0C726789F4C123397C04F5Ed4a9A20070D` |
| LayerZeroBridgeAdapter PA | `0x3dDB1389E0Bb7c627E9acc73eA62e9ae99819a3C` |
| YieldToOne Beacon         | `0x4c9989F704b52B230C7C38618CBef171986969e7` |
| YieldToOne Beacon PA      | `0xdcC635248d3a04264820A782bBe03233f7244d7e` |
| MultiMint Beacon          | `0x00B1c02CeBa9dbdccd4fddf822ea6DEAf6e412b3` |
| MultiMint Beacon PA       | `0x56BD64587980656997F1eD99c0FAfc8A8c62aF4A` |

## Shell preamble

```bash
cd /path/to/PYUSDX

CHAIN=mainnet   # mainnet | arbitrum | monad

MS=0x48670B46380FE1645f0E3e821a25162dB2589D19
M0=0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB

SWAP=0x0bC305e7e13113cAEd3f5486849e9518a1cC4173
FACTORY=0x25c8aFfC5a63D8E047c12918C0438ABA5aA09c2A
PORTAL=0xaAD1466fE33d373189FB9dcC47270e608FeEE8A7
LZ=0xEfF09B0C726789F4C123397C04F5Ed4a9A20070D
BEACON_Y=0x4c9989F704b52B230C7C38618CBef171986969e7
BEACON_M=0x00B1c02CeBa9dbdccd4fddf822ea6DEAf6e412b3

SWAP_PA=0xc421cCeA39cC9858ba613052e84f04Cc2B0DF53B
FACTORY_PA=0x365B54D9D69eB78B6bB1C9e5E0C7C9a142B24096
PORTAL_PA=0x65ce3f3c4732f171E3E7b759F4249dC9cD49a68F
LZ_PA=0x3dDB1389E0Bb7c627E9acc73eA62e9ae99819a3C
BEACON_Y_PA=0xdcC635248d3a04264820A782bBe03233f7244d7e
BEACON_M_PA=0x56BD64587980656997F1eD99c0FAfc8A8c62aF4A

ADMIN=0x0000000000000000000000000000000000000000000000000000000000000000
FACTORY_MGR=$(cast keccak FACTORY_MANAGER_ROLE)
BEACON_MGR=$(cast keccak BEACON_MANAGER_ROLE)

# Array, not a string: zsh does not word-split unquoted parameters.
SEND=(--rpc-url $CHAIN --account protocol_one)
```

Assert before sending anything — `SEND` captures `$CHAIN` at assignment time, so a
stale `SEND` silently targets the previous chain:

```bash
echo "${SEND[@]}"                # must contain --rpc-url $CHAIN
cast chain-id "${SEND[@]:0:2}"   # 1 | 42161 | 143
cast wallet address --account protocol_one   # must be 0xF2f1ACbe...
```

## Ordering constraints

1. **Grant `DEFAULT_ADMIN` to the multisig before renouncing the Deployer's**, per
   contract. The role administers itself; inverting this bricks the contract.
2. **Never revoke `OPERATOR_ROLE` on the LayerZero adapter.**
   `LayerZeroBridgeAdapter.sol:91-97` clears the endpoint delegate to `address(0)` on
   _any_ `OPERATOR_ROLE` revocation, not only when revoking the current delegate, and
   only an OPERATOR can restore it. Leaving `OPERATOR` in place is what keeps the
   delegate intact — this migration deliberately does not touch it.
3. **Do every reversible step first.** While the Deployer still holds `DEFAULT_ADMIN`,
   everything in phase A can be undone.

## Phase A — reversible (Deployer still holds DEFAULT_ADMIN everywhere)

| #   | Step                               | Command                                                                          |
| --- | ---------------------------------- | -------------------------------------------------------------------------------- |
| 1   | Grant admin — SwapFacility         | `cast send $SWAP "grantRole(bytes32,address)" $ADMIN $MS "${SEND[@]}"`           |
| 2   | Grant admin — ExtensionFactory     | `cast send $FACTORY "grantRole(bytes32,address)" $ADMIN $MS "${SEND[@]}"`        |
| 3   | Grant admin — Portal               | `cast send $PORTAL "grantRole(bytes32,address)" $ADMIN $MS "${SEND[@]}"`         |
| 4   | Grant admin — LayerZero adapter    | `cast send $LZ "grantRole(bytes32,address)" $ADMIN $MS "${SEND[@]}"`             |
| 5   | Grant admin — YieldToOne beacon    | `cast send $BEACON_Y "grantRole(bytes32,address)" $ADMIN $MS "${SEND[@]}"`       |
| 6   | Grant admin — MultiMint beacon     | `cast send $BEACON_M "grantRole(bytes32,address)" $ADMIN $MS "${SEND[@]}"`       |
| 7   | Grant factory manager              | `cast send $FACTORY "grantRole(bytes32,address)" $FACTORY_MGR $MS "${SEND[@]}"`  |
| 8   | Revoke factory manager             | `cast send $FACTORY "revokeRole(bytes32,address)" $FACTORY_MGR $M0 "${SEND[@]}"` |
| 9   | Grant beacon manager — YieldToOne  | `cast send $BEACON_Y "grantRole(bytes32,address)" $BEACON_MGR $MS "${SEND[@]}"`  |
| 10  | Revoke beacon manager — YieldToOne | `cast send $BEACON_Y "revokeRole(bytes32,address)" $BEACON_MGR $M0 "${SEND[@]}"` |
| 11  | Grant beacon manager — MultiMint   | `cast send $BEACON_M "grantRole(bytes32,address)" $BEACON_MGR $MS "${SEND[@]}"`  |
| 12  | Revoke beacon manager — MultiMint  | `cast send $BEACON_M "revokeRole(bytes32,address)" $BEACON_MGR $M0 "${SEND[@]}"` |

`PAUSER_ROLE` on SwapFacility and Portal, `OPERATOR_ROLE` on Portal and the LayerZero
adapter, and Portal's `fallbackRecipient` are all deliberately untouched and stay on
the Deployer.

## Checkpoint — verify before anything irreversible

```
python3 script/ops/verify_m0_migration.py $CHAIN --pre-renounce
```

Must report `0 failed`. Do not proceed until it does.

## Phase B — irreversible

| #   | Step                              | Command                                                                       |
| --- | --------------------------------- | ----------------------------------------------------------------------------- |
| 13  | Upgrade rights — SwapFacility     | `cast send $SWAP_PA "transferOwnership(address)" $MS "${SEND[@]}"`            |
| 14  | Upgrade rights — ExtensionFactory | `cast send $FACTORY_PA "transferOwnership(address)" $MS "${SEND[@]}"`         |
| 15  | Upgrade rights — Portal           | `cast send $PORTAL_PA "transferOwnership(address)" $MS "${SEND[@]}"`          |
| 16  | Upgrade rights — LayerZero        | `cast send $LZ_PA "transferOwnership(address)" $MS "${SEND[@]}"`              |
| 17  | Upgrade rights — YieldToOne       | `cast send $BEACON_Y_PA "transferOwnership(address)" $MS "${SEND[@]}"`        |
| 18  | Upgrade rights — MultiMint        | `cast send $BEACON_M_PA "transferOwnership(address)" $MS "${SEND[@]}"`        |
| 19  | Renounce admin — SwapFacility     | `cast send $SWAP "renounceRole(bytes32,address)" $ADMIN $M0 "${SEND[@]}"`     |
| 20  | Renounce admin — ExtensionFactory | `cast send $FACTORY "renounceRole(bytes32,address)" $ADMIN $M0 "${SEND[@]}"`  |
| 21  | Renounce admin — Portal           | `cast send $PORTAL "renounceRole(bytes32,address)" $ADMIN $M0 "${SEND[@]}"`   |
| 22  | Renounce admin — LayerZero        | `cast send $LZ "renounceRole(bytes32,address)" $ADMIN $M0 "${SEND[@]}"`       |
| 23  | Renounce admin — YieldToOne       | `cast send $BEACON_Y "renounceRole(bytes32,address)" $ADMIN $M0 "${SEND[@]}"` |
| 24  | Renounce admin — MultiMint        | `cast send $BEACON_M "renounceRole(bytes32,address)" $ADMIN $M0 "${SEND[@]}"` |

The ProxyAdmin calls target the **ProxyAdmin contracts**, not the proxies.

## Final verification

```
python3 script/ops/verify_m0_migration.py $CHAIN
```

Must report `0 failed`. Archive the output as the handover record.
