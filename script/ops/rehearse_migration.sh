#!/usr/bin/env bash
#
# Rehearses a migration runbook for a given chain against a local fork.
#
# Nothing about the migration is duplicated here. The script reads the runbook and
# derives everything from it:
#   - the shell preamble (addresses, role hashes) from its first ```bash block
#   - the ordered commands from the numbered tables
#   - the phase A/B boundary from the `## Phase B` heading
#   - the verifier to run from the script/ops/verify_*.py path it mentions
#   - optional multisig steps from a ```rehearsal block under `## Phase C`
# If script and runbook ever disagree, this script is wrong by construction rather
# than silently stale.
#
# Forks the target chain into anvil and impersonates the signers, so nothing touches
# the real chain and no key is ever used. Because signing is bypassed, this validates
# ordering, arguments and completeness -- not wallet access.
#
# Usage: script/ops/rehearse_migration.sh <runbook> <chain> [fork_block]
#          runbook    e.g. plans/m0-migration.md | plans/moonpay-migration.md
#          chain      mainnet | arbitrum | monad
#          fork_block optional; fork at this height instead of latest. Needed for a
#                     runbook whose migration is already executed on that chain --
#                     from current state the replay reverts. Pre-migration heights:
#                     monad 95700000, arbitrum 495000000 (approx), mainnet 25740000.
#
# A clean run ends in a verifier pass at both the checkpoint and the final state.

set -euo pipefail

cd "$(dirname "$0")/../.."
[ -f .env ] && set -a && . ./.env && set +a

RUNBOOK="${1:-}"
CHAIN="${2:-}"
FORK_BLOCK="${3:-}"

if [ -z "$RUNBOOK" ] || [ -z "$CHAIN" ]; then
    echo "usage: $0 <runbook> <chain> [fork_block]" >&2
    echo "  e.g. $0 plans/m0-migration.md mainnet" >&2
    exit 2
fi
if [ ! -f "$RUNBOOK" ]; then
    echo "No such runbook: ${RUNBOOK}" >&2
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

PORT=8546
FORK_RPC="http://127.0.0.1:${PORT}"
CMD_FILE=$(mktemp)
PREAMBLE_FILE=$(mktemp)
PHASE_C_FILE=$(mktemp)

cleanup() {
    [ -n "${ANVIL_PID:-}" ] && kill "$ANVIL_PID" 2>/dev/null || true
    rm -f "$CMD_FILE" "$PREAMBLE_FILE" "$PHASE_C_FILE"
}
trap cleanup EXIT

# --- derive everything from the runbook -------------------------------------

# Preamble: first ```bash block. Drop the lines the rehearsal must control itself --
# `cd`, the chain selection, and the signer array.
awk '/^```bash/ {f=1; next} f && /^```/ {exit} f' "$RUNBOOK" \
    | grep -vE '^(cd |CHAIN=|SEND=)' > "$PREAMBLE_FILE"

# Numbered table rows only; prose elsewhere contains a `cast send ... $SEND` placeholder.
# Patterns tolerate prettier's column padding (`| 1   |`), applied by the pre-commit hook.
grep -E '^\| *[0-9]+ *\|' "$RUNBOOK" | grep -oE '`cast send [^`]+`' | tr -d '`' > "$CMD_FILE"
STEP_COUNT=$(wc -l < "$CMD_FILE" | tr -d ' ')

if [ "$STEP_COUNT" -eq 0 ]; then
    echo "No commands found in ${RUNBOOK}; has the table format changed?" >&2
    exit 1
fi

PHASE_A_END=$(awk '/^## Phase B/ {exit} /^\| *[0-9]+ *\|/ {n=$2} END {print n}' "$RUNBOOK")

VERIFIER=$(grep -oE 'script/ops/verify_[a-z0-9_]+\.py' "$RUNBOOK" | head -1)
if [ -z "$VERIFIER" ] || [ ! -f "$VERIFIER" ]; then
    echo "Could not resolve a verifier from ${RUNBOOK} (found: '${VERIFIER}')" >&2
    exit 1
fi

# Optional multisig steps. On the real chain these are Safe transactions; on the fork
# we impersonate the Safe, which is why they live in a rehearsal-only block.
awk '/^## Phase C/ {f=1} f && /^```rehearsal/ {g=1; next} g && /^```/ {exit} g' \
    "$RUNBOOK" > "$PHASE_C_FILE"
PHASE_C_COUNT=$(grep -c . "$PHASE_C_FILE" || true)

# --- set up the fork --------------------------------------------------------

echo "==> runbook  ${RUNBOOK}"
echo "==> ${STEP_COUNT} steps, phase A ends at ${PHASE_A_END}, verifier ${VERIFIER}"
[ "$PHASE_C_COUNT" -gt 0 ] && echo "==> ${PHASE_C_COUNT} phase C step(s) to run as the multisig"
echo "==> forking ${CHAIN}${FORK_BLOCK:+ @ block ${FORK_BLOCK}} into anvil on port ${PORT}"

ANVIL_ARGS=(--fork-url "$FORK_URL" --port "$PORT" --auto-impersonate --silent)
[ -n "$FORK_BLOCK" ] && ANVIL_ARGS+=(--fork-block-number "$FORK_BLOCK")
anvil "${ANVIL_ARGS[@]}" &
ANVIL_PID=$!

for _ in $(seq 1 30); do
    cast chain-id --rpc-url "$FORK_RPC" >/dev/null 2>&1 && break
    sleep 1
done

# shellcheck disable=SC1090
source "$PREAMBLE_FILE"

if [ -z "${M0:-}" ]; then
    echo "Runbook preamble did not define \$M0; cannot choose a sender." >&2
    exit 1
fi

SEND=(--rpc-url "$FORK_RPC" --from "$M0" --unlocked)
SEND_MS=(--rpc-url "$FORK_RPC" --from "${MS:-$M0}" --unlocked)

# Impersonated senders need gas on the fork.
cast rpc anvil_setBalance "$M0" 0xde0b6b3a7640000 --rpc-url "$FORK_RPC" >/dev/null
[ -n "${MS:-}" ] && cast rpc anvil_setBalance "$MS" 0xde0b6b3a7640000 --rpc-url "$FORK_RPC" >/dev/null

# --- replay -----------------------------------------------------------------

step=0
while IFS= read -r cmd; do
    step=$((step + 1))
    echo "  [${step}] ${cmd}"
    eval "$cmd" >/dev/null || { echo "  step ${step} FAILED" >&2; exit 1; }

    if [ "$step" -eq "$PHASE_A_END" ]; then
        echo
        echo "==> checkpoint: verifying pre-renounce state"
        python3 "$VERIFIER" "$FORK_RPC" --pre-renounce
        echo
        echo "==> phase B: irreversible steps"
    fi
done < "$CMD_FILE"

if [ "$PHASE_C_COUNT" -gt 0 ]; then
    echo
    echo "==> phase C: executed as the multisig (a Safe transaction on the real chain)"
    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        echo "  [ms] ${cmd}"
        eval "$cmd" >/dev/null || { echo "  phase C step FAILED" >&2; exit 1; }
    done < "$PHASE_C_FILE"
fi

echo
echo "==> verifying final state"
python3 "$VERIFIER" "$FORK_RPC"
