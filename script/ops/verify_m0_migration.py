#!/usr/bin/env python3
"""Read-only verifier for the M0-deployer -> multisig migration.

Covers the six contracts that were not part of the MoonPay handover: SwapFacility,
ExtensionFactory, Portal, LayerZeroBridgeAdapter and the YieldToOne / MultiMint
beacons. Performs no writes and signs nothing.

Usage:
    script/ops/verify_m0_migration.py <rpc>
    script/ops/verify_m0_migration.py <rpc> --pre-renounce

Exit 0 = all checks passed, 1 = failures, 2 = checks could not run.
"""

import json
import subprocess
import sys

MULTISIG = "0x48670B46380FE1645f0E3e821a25162dB2589D19"
M0 = "0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB"

DEFAULT_ADMIN_ROLE = "0x" + "00" * 32
ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"

# name -> (proxy, proxy admin, roles that must move to the multisig)
CONTRACTS = {
    "SwapFacility": ("0x0bC305e7e13113cAEd3f5486849e9518a1cC4173", "0xc421cCeA39cC9858ba613052e84f04Cc2B0DF53B", []),
    "ExtensionFactory": ("0x25c8aFfC5a63D8E047c12918C0438ABA5aA09c2A", "0x365B54D9D69eB78B6bB1C9e5E0C7C9a142B24096", ["FACTORY_MANAGER_ROLE"]),
    "Portal": ("0xaAD1466fE33d373189FB9dcC47270e608FeEE8A7", "0x65ce3f3c4732f171E3E7b759F4249dC9cD49a68F", []),
    "LayerZeroBridgeAdapter": ("0xEfF09B0C726789F4C123397C04F5Ed4a9A20070D", "0x3dDB1389E0Bb7c627E9acc73eA62e9ae99819a3C", []),
    "YieldToOneBeacon": ("0x4c9989F704b52B230C7C38618CBef171986969e7", "0xdcC635248d3a04264820A782bBe03233f7244d7e", ["BEACON_MANAGER_ROLE"]),
    "MultiMintBeacon": ("0x00B1c02CeBa9dbdccd4fddf822ea6DEAf6e412b3", "0x56BD64587980656997F1eD99c0FAfc8A8c62aF4A", ["BEACON_MANAGER_ROLE"]),
}

# Roles deliberately left on the deployer. Asserted as unchanged so that an
# accidental grant to the multisig, or a stray revoke, is caught.
ROLES_STAYING_ON_M0 = {
    "SwapFacility": ["PAUSER_ROLE"],
    "Portal": ["PAUSER_ROLE", "OPERATOR_ROLE"],
    "LayerZeroBridgeAdapter": ["OPERATOR_ROLE"],
}

LZ_ENDPOINT = {1: "0x1a44076050125825900e736c501f859c50fE728c", 42161: "0x1a44076050125825900e736c501f859c50fE728c", 143: "0x6f475642a6e85809b1c36fa62763669b1b48dd5b"}


class Checker:
    def __init__(self, rpc):
        self.rpc = rpc
        self.failures = []
        self.passes = 0

    def cast(self, *args, allow_failure=False):
        r = subprocess.run(["cast", *args, "--rpc-url", self.rpc], capture_output=True, text=True)
        if r.returncode != 0:
            if allow_failure:
                return None
            raise RuntimeError(f"cast {' '.join(args)} failed: {r.stderr.strip()}")
        return r.stdout.strip()

    def call(self, address, sig, *args):
        raw = self.cast("call", address, sig, *args, allow_failure=True)
        if raw is None:
            return None
        return [l.split()[0] for l in raw.splitlines() if l.strip()]

    def check(self, label, actual, expected):
        if actual == expected:
            self.passes += 1
            print(f"  PASS  {label}")
        else:
            self.failures.append(f"{label}: expected {expected}, got {actual}")
            print(f"  FAIL  {label}: expected {expected}, got {actual}")

    def has_role(self, address, role, account):
        r = self.call(address, "hasRole(bytes32,address)(bool)", role, account)
        return r[0] if r else "?"

    def role_hash(self, address, name):
        r = self.call(address, f"{name}()(bytes32)")
        return r[0] if r else None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    rpc = sys.argv[1]
    pre_renounce = "--pre-renounce" in sys.argv
    c = Checker(rpc)
    chain_id = int(c.cast("chain-id"))
    admin_on_m0 = "true" if pre_renounce else "false"
    proxy_owner = M0 if pre_renounce else MULTISIG
    print(f"Verifying chain {chain_id} via {rpc} [{'PRE-RENOUNCE' if pre_renounce else 'FINAL'}]\n")

    for name, (proxy, proxy_admin, moved_roles) in CONTRACTS.items():
        print(name)
        c.check("  DEFAULT_ADMIN held by multisig", c.has_role(proxy, DEFAULT_ADMIN_ROLE, MULTISIG), "true")
        c.check(f"  DEFAULT_ADMIN on M0 (expect {admin_on_m0})", c.has_role(proxy, DEFAULT_ADMIN_ROLE, M0), admin_on_m0)

        for role_name in moved_roles:
            h = c.role_hash(proxy, role_name)
            if h is None:
                c.check(f"  {role_name} readable", "getter reverted", "ok")
                continue
            c.check(f"  {role_name} held by multisig", c.has_role(proxy, h, MULTISIG), "true")
            c.check(f"  {role_name} released by M0", c.has_role(proxy, h, M0), "false")

        for role_name in ROLES_STAYING_ON_M0.get(name, []):
            h = c.role_hash(proxy, role_name)
            if h:
                c.check(f"  {role_name} still on M0 (deliberate)", c.has_role(proxy, h, M0), "true")
                c.check(f"  {role_name} not on multisig", c.has_role(proxy, h, MULTISIG), "false")

        slot = c.cast("storage", proxy, ADMIN_SLOT)
        on_chain_pa = "0x" + slot[-40:]
        c.check("  ProxyAdmin address as documented", on_chain_pa.lower(), proxy_admin.lower())
        owner = c.call(on_chain_pa, "owner()(address)")
        c.check("  ProxyAdmin owner", (owner[0] if owner else "?").lower(), proxy_owner.lower())
        print()

    # Deliberately NOT migrated -- see "Why fallbackRecipient is left alone" in the
    # runbook. Asserted as unchanged so an accidental setFallbackRecipient is caught.
    print("Portal fallbackRecipient (deliberately unchanged)")
    fr = c.call(CONTRACTS["Portal"][0], "fallbackRecipient()(address)")
    c.check("  still the deployer", (fr[0] if fr else "?").lower(), M0.lower())

    # OPERATOR_ROLE is never revoked on the adapter, so the delegate must survive the
    # migration untouched. A zero here means an OPERATOR revoke wiped it.
    print("\nLayerZero delegate (must be untouched)")
    endpoint = LZ_ENDPOINT.get(chain_id)
    if endpoint is None:
        print(f"  SKIP  unknown endpoint for chain {chain_id}")
    else:
        d = c.call(endpoint, "delegates(address)(address)", CONTRACTS["LayerZeroBridgeAdapter"][0])
        c.check("  still the deployer", (d[0] if d else "?").lower(), M0.lower())

    print(f"\n{c.passes} passed, {len(c.failures)} failed")
    if c.failures:
        print("\nFAILURES:")
        for f in c.failures:
            print(f"  - {f}")
        return 1
    print("Multisig migration state verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
