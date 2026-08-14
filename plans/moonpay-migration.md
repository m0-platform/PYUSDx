# Role migration runbook — PYUSDx & IssuerGateway

Hand over all admin authority from the M0 deployer EOA to MoonPay on a given
chain. Every contract address below is identical on all chains (deterministic
CREATE3 deploys), so the only per-chain variable is the RPC alias.

| Chain                | Alias      | Status                                                           |
| -------------------- | ---------- | ---------------------------------------------------------------- |
| Ethereum mainnet (1) | `mainnet`  | done — **earner-manager bucket still missing**, MoonPay must fix |
| Arbitrum One (42161) | `arbitrum` | done — verified 34/34                                            |
| Monad (143)          | `monad`    | done — verified 34/34                                            |

All three chains have been migrated; this runbook is retained as the procedure for
any future chain and as the record of how these were done.

Execution is step-by-step via `cast`, one transaction at a time. Verification is
automated.

## Before running on a new chain

- **Add the RPC alias.** `foundry.toml` needs `[rpc_endpoints] <chain> =
"${<CHAIN>_RPC_URL}"` and `.env` needs the matching value. `CHAIN` may hold a raw
  URL instead, since `cast --rpc-url` accepts either, but prefer the alias so no
  endpoint is pasted into the shell. A missing alias fails confusingly: `cast` treats
  the name as a file path and reports `No such file or directory`.
- **Land the deployment record first.** Handing over admin on a configuration whose
  deployment PR has not merged is a sequencing decision worth making deliberately.
- **Use an RPC that allows a full-range `eth_getLogs`.** Public endpoints often cap
  the block span — `rpc.monad.xyz` caps it at 100 — which disables the verifier's
  holder-set checks. It reports them as `SKIP` and exits 2 rather than passing, so a
  capped endpoint cannot be mistaken for a clean run.

## Addresses

| What                       | Address                                      |
| -------------------------- | -------------------------------------------- |
| PYUSDx proxy               | `0xeBDB0942cE16386Ab90718C7BD10C91CDb66b14d` |
| PYUSDx ProxyAdmin          | `0xb8A874137df3d4B0f19490Eb06CfBE6B6D35E581` |
| IssuerGateway proxy        | `0x693CC3305342B02AC1549B509a704ff944Cd9499` |
| IssuerGateway ProxyAdmin   | `0x63dF2057C740D6369a003E040a7abDF40a2D82fD` |
| Portal (issuer, untouched) | `0xaAD1466fE33d373189FB9dcC47270e608FeEE8A7` |
| M0 deployer (outgoing)     | `0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB` |
| MoonPay (incoming)         | `0x314160525f5eA6677D3908112fF9Bd885F3BB78e` |
| Gateway operator/executor  | `0x6017927a1375cE8962116ecDa22ACda4A345403A` |

The ProxyAdmin addresses are the same on every chain but are **distinct contracts
per chain**. Always re-read the ERC-1967 admin slot on the target chain rather than
trusting an address verified elsewhere.

## Role hashes

| Role                           | Hash                                                                 |
| ------------------------------ | -------------------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE`           | `0x0000000000000000000000000000000000000000000000000000000000000000` |
| `PAUSER_ROLE`                  | `0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a` |
| `FREEZE_MANAGER_ROLE`          | `0x109b88c1c8d528799ca6f455418979dd2a552493f14553ce44443b23f7df8b35` |
| `FORCED_TRANSFER_MANAGER_ROLE` | `0xc66b3536568140ce119bcc21a4fa7e3449a56fb5f260d32ff8e719230264132c` |
| `RATE_LIMIT_MANAGER_ROLE`      | `0xd2ad11a4404270d22b2f1ce9a30bc7295171184fa77fc61dd65faeb320577102` |

## Shell preamble

Run once in the shell used for the migration. `foundry.toml` resolves the
chain alias from `.env`, so no RPC URL is ever pasted.

```bash
cd /path/to/PYUSDX

CHAIN=monad   # foundry.toml rpc alias: mainnet | arbitrum | monad

PYUSDX=0xeBDB0942cE16386Ab90718C7BD10C91CDb66b14d
GATEWAY=0x693CC3305342B02AC1549B509a704ff944Cd9499
PYUSDX_PROXY_ADMIN=0xb8A874137df3d4B0f19490Eb06CfBE6B6D35E581
GATEWAY_PROXY_ADMIN=0x63dF2057C740D6369a003E040a7abDF40a2D82fD

M0=0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB
MOONPAY=0x314160525f5eA6677D3908112fF9Bd885F3BB78e

ADMIN=0x0000000000000000000000000000000000000000000000000000000000000000
PAUSER=$(cast keccak PAUSER_ROLE)
FREEZE=$(cast keccak FREEZE_MANAGER_ROLE)
FORCED=$(cast keccak FORCED_TRANSFER_MANAGER_ROLE)
RATELIMIT=$(cast keccak RATE_LIMIT_MANAGER_ROLE)

# Signing: pick one. Prefer hardware or an encrypted keystore over a raw key.
# Must be an ARRAY, not a string: zsh does not word-split unquoted parameters, so
# a string collapses into a single argument and cast rejects it.
#SEND=(--rpc-url $CHAIN --ledger)
SEND=(--rpc-url $CHAIN --account protocol_one)
```

With `--account`, the sender is derived from the keystore, so no `--from` is
needed. Confirm the preamble resolved correctly before sending anything:

```bash
# Assert the chain BEFORE anything else, and assert it against $SEND rather than
# $CHAIN. SEND captures $CHAIN's value at assignment time, so editing CHAIN
# afterwards leaves SEND pointing at the previous chain -- where every step reverts
# with AccessControlUnauthorizedAccount because M0 has already renounced there.
echo "${SEND[@]}"                # must contain --rpc-url $CHAIN
cast chain-id "${SEND[@]:0:2}"   # 1 = mainnet | 42161 = arbitrum | 143 = monad

# Must print 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB, or every step below is
# signed by the wrong key. Prompts for the keystore password.
cast wallet address --account protocol_one

cast call $PYUSDX "hasRole(bytes32,address)(bool)" $ADMIN $M0 --rpc-url $CHAIN   # true
cast call $PYUSDX "earnerManager()(address)" --rpc-url $CHAIN                     # 0xF2f1ACbe...
```

### Optional: avoid re-entering the keystore password on every step

`--account` prompts once per transaction, so the sequence below costs 17 prompts.
To enter it once, point `ETH_PASSWORD` at a password _file_ — despite the name it
is a path, not the password itself.

```bash
PWFILE=$(mktemp) && chmod 600 "$PWFILE"
read -rs "PW?keystore password: " && printf '%s' "$PW" > "$PWFILE" && unset PW
export ETH_PASSWORD="$PWFILE"

# ... run the 17 steps ...

unset ETH_PASSWORD && rm -P "$PWFILE"
```

The password touches disk for the duration. `rm -P` overwrites before unlinking,
though on APFS that is not a guarantee against forensic recovery. Do not use
`--password <cleartext>`: it lands in shell history and in `ps` output.

Weigh this against the fact that each prompt is a forced pause in front of an
irreversible transaction, which is most of why this runbook is manual.

**Dry-run any step** by swapping `cast send ... "${SEND[@]}"` for
`cast call <same args> --from $M0 --rpc-url $CHAIN`. It executes against current
state without broadcasting and surfaces a revert before you spend gas.

## Ordering constraints

These are the failure modes that manual execution is exposed to. Violating any
of them requires MoonPay to fix, because M0 will no longer hold the authority.

1. **`setRateLimit` for the new earner manager must precede revoking
   `RATE_LIMIT_MANAGER_ROLE` from M0.** Missing this is what left mainnet's
   `distributeReward` reverting with `RateLimitNotConfigured`.
2. **`setEarnerManager` must precede renouncing `DEFAULT_ADMIN_ROLE`** — it is
   gated on that role.
3. **Grant `DEFAULT_ADMIN_ROLE` to MoonPay before renouncing M0's.** Inverting
   this leaves the contract permanently admin-less; the role administers itself
   and there is no recovery path.
4. **Do every reversible step first.** While M0 still holds
   `DEFAULT_ADMIN_ROLE`, every role change in phase A can be undone.

## Phase A — reversible

All sent from the M0 deployer. At the end of this phase M0 still holds
`DEFAULT_ADMIN_ROLE` on both contracts, so anything wrong here is recoverable.

On **PYUSDx** `0xeBDB0942…`:

| #   | Step                              | Command                                                                                                              |
| --- | --------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 1   | Point earner manager at MoonPay   | `cast send $PYUSDX "setEarnerManager(address)" $MOONPAY "${SEND[@]}"`                                                |
| 2   | Provision MoonPay's reward bucket | `cast send $PYUSDX "setRateLimit(address,uint128,uint128,bool)" $MOONPAY 5000000000000 2500000000 true "${SEND[@]}"` |
| 3   | Retire M0's stale bucket          | `cast send $PYUSDX "setRateLimit(address,uint128,uint128,bool)" $M0 0 0 false "${SEND[@]}"`                          |
| 4   | Grant pauser                      | `cast send $PYUSDX "grantRole(bytes32,address)" $PAUSER $MOONPAY "${SEND[@]}"`                                       |
| 5   | Revoke pauser                     | `cast send $PYUSDX "revokeRole(bytes32,address)" $PAUSER $M0 "${SEND[@]}"`                                           |
| 6   | Grant freeze manager              | `cast send $PYUSDX "grantRole(bytes32,address)" $FREEZE $MOONPAY "${SEND[@]}"`                                       |
| 7   | Revoke freeze manager             | `cast send $PYUSDX "revokeRole(bytes32,address)" $FREEZE $M0 "${SEND[@]}"`                                           |
| 8   | Grant forced-transfer manager     | `cast send $PYUSDX "grantRole(bytes32,address)" $FORCED $MOONPAY "${SEND[@]}"`                                       |
| 9   | Revoke forced-transfer manager    | `cast send $PYUSDX "revokeRole(bytes32,address)" $FORCED $M0 "${SEND[@]}"`                                           |
| 10  | Grant rate-limit manager          | `cast send $PYUSDX "grantRole(bytes32,address)" $RATELIMIT $MOONPAY "${SEND[@]}"`                                    |
| 11  | Revoke rate-limit manager         | `cast send $PYUSDX "revokeRole(bytes32,address)" $RATELIMIT $M0 "${SEND[@]}"`                                        |
| 12  | Grant admin to MoonPay            | `cast send $PYUSDX "grantRole(bytes32,address)" $ADMIN $MOONPAY "${SEND[@]}"`                                        |

Steps 2 and 3 mirror the pre-migration earner manager bucket: 5,000,000 PYUSDx
capacity (6 decimals) refilling at 2,500/second, full in 2,000 seconds. Step 11
must not run before steps 2 and 3 — see constraint 1.

On **IssuerGateway** `0x693CC330…`:

| #   | Step                   | Command                                                                        |
| --- | ---------------------- | ------------------------------------------------------------------------------ |
| 13  | Grant admin to MoonPay | `cast send $GATEWAY "grantRole(bytes32,address)" $ADMIN $MOONPAY "${SEND[@]}"` |

## Checkpoint — verify before anything irreversible

```
python3 script/ops/verify_moonpay_migration.py $CHAIN --pre-renounce
```

Must report `0 failed`. **Do not proceed to phase B until it does.** This is the
last point at which a mistake is cheap.

## Phase B — irreversible

| #   | Step                             | Command                                                                             |
| --- | -------------------------------- | ----------------------------------------------------------------------------------- |
| 14  | Hand over PYUSDx upgrade rights  | `cast send $PYUSDX_PROXY_ADMIN "transferOwnership(address)" $MOONPAY "${SEND[@]}"`  |
| 15  | Hand over gateway upgrade rights | `cast send $GATEWAY_PROXY_ADMIN "transferOwnership(address)" $MOONPAY "${SEND[@]}"` |
| 16  | Renounce PYUSDx admin            | `cast send $PYUSDX "renounceRole(bytes32,address)" $ADMIN $M0 "${SEND[@]}"`         |
| 17  | Renounce gateway admin           | `cast send $GATEWAY "renounceRole(bytes32,address)" $ADMIN $M0 "${SEND[@]}"`        |

The ProxyAdmin calls go to the **ProxyAdmin contracts directly**, not through the
proxies — note steps 14 and 15 target `$PYUSDX_PROXY_ADMIN` / `$GATEWAY_PROXY_ADMIN`,
not `$PYUSDX` / `$GATEWAY`. `renounceRole` takes the caller's own address as the
second argument; OpenZeppelin rejects renouncing on behalf of anyone else.

## Final verification

```
python3 script/ops/verify_moonpay_migration.py $CHAIN
```

Must report `0 failed`. Archive the output as the handover record.

## Rehearsal

```
script/ops/rehearse_migration.sh $CHAIN
```

Forks the target chain into anvil, replays steps 1–17 in order, and runs the verifier at
both the checkpoint and the end. Confirmed green against the live fork before
this runbook was written. Re-run it after any edit to the sequence.

## Open decisions — resolve before phase B

- **MoonPay key is unproven.** `0x314160525f5eA6677D3908112fF9Bd885F3BB78e` has
  nonce 0 and zero balance on every chain checked so far — it has never signed
  anything. After step 17 there is no recovery if the key is wrong or lost. Ask
  MoonPay for any signed transaction from it first; on mainnet that option is
  already gone.
- **`OPERATOR_ROLE` and `EXECUTOR_ROLE` are the same EOA**
  (`0x6017927a…`), which collapses the IssuerGateway's separation of duties: one
  key can both propose and execute a mint after the 300-second delay. Splitting
  them is far easier now than after handing over gateway admin. The verifier
  currently asserts the existing shared-holder state; update
  `EXPECTED_BUCKETS`-adjacent role expectations in
  `script/ops/verify_moonpay_migration.py` if this changes.
- **`.env` drift.** It carries `PYUSDX_EARNER_MANAGER_RATE_LIMIT_CAPACITY` /
  `_REFILL` and `PYUSDX_RATE_MANAGER`, but the deployed token exposes
  `RATE_LIMIT_MANAGER_ROLE` and no earner-manager role. Reconcile before trusting
  `.env` as the source of truth for any redeploy.
