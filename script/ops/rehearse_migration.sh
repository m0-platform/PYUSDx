#!/usr/bin/env bash
#
# Rehearses the role migration for a given chain against a local fork.
#
# The command sequence is not duplicated here: it is extracted from the numbered
# tables in plans/role-migration.md and executed in order, so the
# rehearsal always tests the runbook you are actually going to follow. If the two
# ever disagree, this script is wrong by construction rather than silently stale.
#
# Forks the target chain into anvil and impersonates the M0 deployer, so nothing
# touches the real chain and no key is ever used. Because signing is bypassed,
# this validates ordering, arguments and completeness -- not wallet access.
#
# Usage: script/ops/rehearse_migration.sh <chain>   # mainnet | arbitrum | monad
#
# A clean run ends in "Migration state verified." at both the checkpoint and the
# final state.

set -euo pipefail

cd "$(dirname "$0")/../.."
[ -f .env ] && set -a && . ./.env && set +a

CHAIN="${1:-}"
if [ -z "$CHAIN" ]; then
    echo "usage: $0 <chain>   # mainnet | arbitrum | monad" >&2
    exit 2
fi

# anvil needs a raw URL, not a foundry.toml alias.
case "$CHAIN" in
    mainnet)  FORK_URL="${MAINNET_RPC_URL:-}" ;;
    arbitrum) FORK_URL="${ARBITRUM_RPC_URL:-}" ;;
    monad)    FORK_URL="${MONAD_RPC_URL:-}" ;;
    *)        echo "unknown chain '${CHAIN}'" >&2; exit 2 ;;
esac
if [ -z "$FORK_URL" ]; then
    echo "No RPC URL for '${CHAIN}'. Set the matching *_RPC_URL in .env." >&2
    exit 2
fi

RUNBOOK=plans/role-migration.md
PORT=8546
FORK_RPC="http://127.0.0.1:${PORT}"
CMD_FILE=$(mktemp)

cleanup() {
    [ -n "${ANVIL_PID:-}" ] && kill "$ANVIL_PID" 2>/dev/null || true
    rm -f "$CMD_FILE"
}
trap cleanup EXIT

# Runbook preamble, mirrored. Only $SEND differs: impersonation instead of a signer.
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
SEND=(--rpc-url "$FORK_RPC" --from "$M0" --unlocked)

# Numbered table rows only; prose elsewhere contains a `cast send ... $SEND` placeholder.
grep -E '^\| [0-9]+ \|' "$RUNBOOK" | grep -oE '`cast send [^`]+`' | tr -d '`' > "$CMD_FILE"
STEP_COUNT=$(wc -l < "$CMD_FILE" | tr -d ' ')

if [ "$STEP_COUNT" -eq 0 ]; then
    echo "No commands found in ${RUNBOOK}; has the table format changed?" >&2
    exit 1
fi

# Phase A ends with the last step before the irreversible section.
PHASE_A_END=$(awk '/^## Phase B/ {exit} /^\| [0-9]+ \|/ {n=$2} END {print n}' "$RUNBOOK")

echo "==> ${STEP_COUNT} steps extracted from ${RUNBOOK} (phase A ends at step ${PHASE_A_END})"
echo "==> forking ${CHAIN} into anvil on port ${PORT}"
anvil --fork-url "$FORK_URL" --port "$PORT" --auto-impersonate --silent &
ANVIL_PID=$!

for _ in $(seq 1 30); do
    cast chain-id --rpc-url "$FORK_RPC" >/dev/null 2>&1 && break
    sleep 1
done

# The impersonated admin needs gas on the fork.
cast rpc anvil_setBalance "$M0" 0xde0b6b3a7640000 --rpc-url "$FORK_RPC" >/dev/null

step=0
while IFS= read -r cmd; do
    step=$((step + 1))
    echo "  [${step}] ${cmd}"
    eval "$cmd" >/dev/null || { echo "  step ${step} FAILED" >&2; exit 1; }

    if [ "$step" -eq "$PHASE_A_END" ]; then
        echo
        echo "==> checkpoint: verifying pre-renounce state"
        python3 script/ops/verify_migration.py "$FORK_RPC" --pre-renounce
        echo
        echo "==> phase B: irreversible steps"
    fi
done < "$CMD_FILE"

echo
echo "==> verifying final state"
python3 script/ops/verify_migration.py "$FORK_RPC"
