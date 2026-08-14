#!/usr/bin/env python3
"""Read-only verifier for the PYUSDx / IssuerGateway role migration.

Asserts the complete expected end state on a given chain. Performs no writes and
signs nothing: every call is an `eth_call` or `eth_getLogs` issued through `cast`.

Usage:
    script/ops/verify_migration.py <rpc>              # final state, post-renounce
    script/ops/verify_migration.py <rpc> --pre-renounce

`<rpc>` is a foundry rpc alias from foundry.toml (e.g. `arbitrum`, `mainnet`) or a
raw URL (e.g. http://127.0.0.1:8545 when verifying a fork rehearsal).

Exit code 0 means every check passed.
"""

import subprocess
import sys

PYUSDX = "0xeBDB0942cE16386Ab90718C7BD10C91CDb66b14d"
ISSUER_GATEWAY = "0x693CC3305342B02AC1549B509a704ff944Cd9499"
PORTAL = "0xaAD1466fE33d373189FB9dcC47270e608FeEE8A7"

M0 = "0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB"
MOONPAY = "0x314160525f5eA6677D3908112fF9Bd885F3BB78e"
GATEWAY_OPS = "0x6017927a1375cE8962116ecDa22ACda4A345403A"

DEFAULT_ADMIN_ROLE = "0x" + "00" * 32

# Earner manager reward bucket, carried over from the pre-migration configuration.
EARNER_MANAGER_CAPACITY = 5_000_000_000_000
EARNER_MANAGER_REFILL = 2_500_000_000

# Issuer buckets, expected to be untouched by the migration.
EXPECTED_BUCKETS = {
    ISSUER_GATEWAY: (25_000_000_000_000, 12_500_000_000),
    PORTAL: (10_000_000_000_000, 5_000_000_000),
}

# First block to scan for role events, keyed by chain id.
DEPLOY_BLOCK = {1: 25_232_000, 42161: 469_436_000, 143: 95_378_400}

ROLE_GRANTED = "0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d"
ROLE_REVOKED = "0xf6391f5c32d9c69d2a47ea670b442974b53935d1edc7fd64eb21e047a839171b"


class Checker:
    def __init__(self, rpc):
        self.rpc = rpc
        self.failures = []
        self.skipped = []
        self.passes = 0

    def cast(self, *args, allow_failure=False):
        result = subprocess.run(
            ["cast", *args, "--rpc-url", self.rpc], capture_output=True, text=True
        )
        if result.returncode != 0:
            if allow_failure:
                return None
            raise RuntimeError(f"cast {' '.join(args)} failed: {result.stderr.strip()}")
        return result.stdout.strip()

    def skip(self, label, reason):
        self.skipped.append(f"{label}: {reason}")
        print(f"  SKIP  {label} ({reason})")

    def call(self, address, sig, *args):
        # `cast call` annotates large integers as "12345 [1.2e4]"; keep the raw value.
        raw = self.cast("call", address, sig, *args)
        return [line.split()[0] for line in raw.splitlines() if line.strip()]

    def check(self, label, actual, expected):
        if actual == expected:
            self.passes += 1
            print(f"  PASS  {label}")
        else:
            self.failures.append(f"{label}: expected {expected}, got {actual}")
            print(f"  FAIL  {label}: expected {expected}, got {actual}")

    def role_hash(self, address, name):
        return self.call(address, f"{name}()(bytes32)")[0]

    def has_role(self, address, role, account):
        return self.call(address, "hasRole(bytes32,address)(bool)", role, account)[0]

    def holders(self, address, role, from_block):
        """Current holders of `role`, derived from the full grant/revoke event history.

        Returns None if the RPC refuses a full-range eth_getLogs (some endpoints cap
        the block span). The caller reports that as SKIP rather than a pass, because
        a narrower scan cannot prove the absence of an unexpected holder.
        """
        current = {}
        events = []
        for topic in (ROLE_GRANTED, ROLE_REVOKED):
            raw = self.cast(
                "logs",
                "--from-block",
                str(from_block),
                "--to-block",
                "latest",
                "--address",
                address,
                topic,
                role,
                "--json",
                allow_failure=True,
            )
            if raw is None:
                return None
            import json

            for log in json.loads(raw):
                events.append(
                    (
                        int(log["blockNumber"], 16),
                        int(log["logIndex"], 16),
                        topic == ROLE_GRANTED,
                        "0x" + log["topics"][2][-40:],
                    )
                )
        for _, _, granted, account in sorted(events):
            current[account] = granted
        return {a for a, held in current.items() if held}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    rpc = sys.argv[1]
    pre_renounce = "--pre-renounce" in sys.argv

    c = Checker(rpc)
    chain_id = int(c.cast("chain-id"))
    from_block = DEPLOY_BLOCK.get(chain_id)
    if from_block is None:
        print(f"Unknown chain id {chain_id}; add it to DEPLOY_BLOCK.")
        return 2

    admin_expected = "true" if pre_renounce else "false"
    mode = "PRE-RENOUNCE" if pre_renounce else "FINAL"
    print(f"Verifying chain {chain_id} via {rpc} [{mode}]\n")

    roles = {
        name: c.role_hash(PYUSDX, name)
        for name in (
            "ISSUER_ROLE",
            "PAUSER_ROLE",
            "FREEZE_MANAGER_ROLE",
            "FORCED_TRANSFER_MANAGER_ROLE",
            "RATE_LIMIT_MANAGER_ROLE",
        )
    }
    roles["OPERATOR_ROLE"] = c.role_hash(ISSUER_GATEWAY, "OPERATOR_ROLE")
    roles["EXECUTOR_ROLE"] = c.role_hash(ISSUER_GATEWAY, "EXECUTOR_ROLE")

    print("PYUSDx roles")
    for name in (
        "PAUSER_ROLE",
        "FREEZE_MANAGER_ROLE",
        "FORCED_TRANSFER_MANAGER_ROLE",
        "RATE_LIMIT_MANAGER_ROLE",
    ):
        c.check(f"{name} held by MoonPay", c.has_role(PYUSDX, roles[name], MOONPAY), "true")
        c.check(f"{name} released by M0", c.has_role(PYUSDX, roles[name], M0), "false")

    c.check(
        "DEFAULT_ADMIN_ROLE held by MoonPay",
        c.has_role(PYUSDX, DEFAULT_ADMIN_ROLE, MOONPAY),
        "true",
    )
    c.check(
        f"DEFAULT_ADMIN_ROLE on M0 (expect {admin_expected})",
        c.has_role(PYUSDX, DEFAULT_ADMIN_ROLE, M0),
        admin_expected,
    )

    print("\nPYUSDx issuers (must be unchanged by the migration)")
    c.check("ISSUER_ROLE held by IssuerGateway", c.has_role(PYUSDX, roles["ISSUER_ROLE"], ISSUER_GATEWAY), "true")
    c.check("ISSUER_ROLE held by Portal", c.has_role(PYUSDX, roles["ISSUER_ROLE"], PORTAL), "true")
    c.check("ISSUER_ROLE not held by MoonPay", c.has_role(PYUSDX, roles["ISSUER_ROLE"], MOONPAY), "false")
    c.check("ISSUER_ROLE not held by M0", c.has_role(PYUSDX, roles["ISSUER_ROLE"], M0), "false")

    print("\nEarner manager and rate limits")
    c.check("earnerManager() is MoonPay", c.call(PYUSDX, "earnerManager()(address)")[0].lower(), MOONPAY.lower())

    bucket = c.call(PYUSDX, "getRateLimitConfig(address)(uint128,uint128)", MOONPAY)
    c.check(
        "earner manager bucket provisioned",
        (int(bucket[0]), int(bucket[1])),
        (EARNER_MANAGER_CAPACITY, EARNER_MANAGER_REFILL),
    )

    stale = c.call(PYUSDX, "getRateLimitConfig(address)(uint128,uint128)", M0)
    c.check("stale M0 bucket retired", (int(stale[0]), int(stale[1])), (0, 0))

    for issuer, expected in EXPECTED_BUCKETS.items():
        actual = c.call(PYUSDX, "getRateLimitConfig(address)(uint128,uint128)", issuer)
        c.check(f"issuer bucket unchanged {issuer}", (int(actual[0]), int(actual[1])), expected)

    print("\nIssuerGateway roles")
    c.check(
        "DEFAULT_ADMIN_ROLE held by MoonPay",
        c.has_role(ISSUER_GATEWAY, DEFAULT_ADMIN_ROLE, MOONPAY),
        "true",
    )
    c.check(
        f"DEFAULT_ADMIN_ROLE on M0 (expect {admin_expected})",
        c.has_role(ISSUER_GATEWAY, DEFAULT_ADMIN_ROLE, M0),
        admin_expected,
    )
    c.check("OPERATOR_ROLE unchanged", c.has_role(ISSUER_GATEWAY, roles["OPERATOR_ROLE"], GATEWAY_OPS), "true")
    c.check("EXECUTOR_ROLE unchanged", c.has_role(ISSUER_GATEWAY, roles["EXECUTOR_ROLE"], GATEWAY_OPS), "true")

    # ProxyAdmin ownership transfers are part of the irreversible phase, so before
    # the renounce they are still expected to sit with M0.
    print("\nProxy admin ownership")
    admin_slot = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
    expected_owner = M0 if pre_renounce else MOONPAY
    for label, proxy in (("PYUSDx", PYUSDX), ("IssuerGateway", ISSUER_GATEWAY)):
        proxy_admin = "0x" + c.cast("storage", proxy, admin_slot)[-40:]
        owner = c.call(proxy_admin, "owner()(address)")[0]
        c.check(f"{label} ProxyAdmin {proxy_admin} owner", owner.lower(), expected_owner.lower())

    print("\nUnexpected role holders (full event history)")
    expected_sets = {
        (PYUSDX, "DEFAULT_ADMIN_ROLE", DEFAULT_ADMIN_ROLE): {MOONPAY} | ({M0} if pre_renounce else set()),
        (PYUSDX, "ISSUER_ROLE", roles["ISSUER_ROLE"]): {ISSUER_GATEWAY, PORTAL},
        (PYUSDX, "PAUSER_ROLE", roles["PAUSER_ROLE"]): {MOONPAY},
        (PYUSDX, "FREEZE_MANAGER_ROLE", roles["FREEZE_MANAGER_ROLE"]): {MOONPAY},
        (PYUSDX, "FORCED_TRANSFER_MANAGER_ROLE", roles["FORCED_TRANSFER_MANAGER_ROLE"]): {MOONPAY},
        (PYUSDX, "RATE_LIMIT_MANAGER_ROLE", roles["RATE_LIMIT_MANAGER_ROLE"]): {MOONPAY},
        (ISSUER_GATEWAY, "DEFAULT_ADMIN_ROLE", DEFAULT_ADMIN_ROLE): {MOONPAY} | ({M0} if pre_renounce else set()),
        (ISSUER_GATEWAY, "OPERATOR_ROLE", roles["OPERATOR_ROLE"]): {GATEWAY_OPS},
        (ISSUER_GATEWAY, "EXECUTOR_ROLE", roles["EXECUTOR_ROLE"]): {GATEWAY_OPS},
    }
    for (address, name, role), expected in expected_sets.items():
        actual = c.holders(address, role, from_block)
        label = f"{name} holder set on {address[:10]}"
        if actual is None:
            c.skip(label, "RPC rejected full-range eth_getLogs")
            continue
        c.check(
            label,
            sorted(a.lower() for a in actual),
            sorted(a.lower() for a in expected),
        )

    print(f"\n{c.passes} passed, {len(c.failures)} failed, {len(c.skipped)} skipped")
    if c.failures:
        print("\nFAILURES:")
        for failure in c.failures:
            print(f"  - {failure}")
        return 1
    if c.skipped:
        print(
            "\nINCOMPLETE: the holder-set checks did not run, so an unexpected role\n"
            "holder granted outside the known addresses would not be detected.\n"
            "Re-run against an RPC that allows a full-range eth_getLogs."
        )
        return 2
    print("Migration state verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
