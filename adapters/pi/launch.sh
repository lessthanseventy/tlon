#!/usr/bin/env bash
# pi model launcher + server citizenship. The `pi:*` mise tasks pass a fixed
# --provider/--model/[--thinking]; an optional trailing numeric thread-id joins that server
# thread (else a fresh one is opened). Everything after is passed through to pi.
#
# This exports the TLON_* block and pi's adapters extension reads it at session_start to
# register. If the spawn fails (service down, no release), pi still launches — just not as a
# citizen.
set -euo pipefail

adapter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$adapter/../.." && pwd)"
cli="$repo/scripts/tlon-cli.sh"

provider="" model="" thinking=""
while [ $# -gt 0 ]; do
  case "$1" in
    --provider) provider="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --thinking) thinking="$2"; shift 2 ;;
    *) break ;;
  esac
done
[ -n "$provider" ] && [ -n "$model" ] || { echo "usage: launch.sh --provider P --model M [--thinking T] [thread-id] [pi-args…]" >&2; exit 2; }

# Optional leading numeric thread-id → join that server thread; else open a fresh one.
# The agent is the MODEL, so `server:roster` shows which model is on the thread.
join_id=""
if [ -n "${1:-}" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
  join_id="$1"
  shift
fi

# The CLI's stderr passes through: its own error (no release, service down, no such
# thread) is the diagnosis, so nothing here guesses at one.
if [ -n "$join_id" ]; then
  block="$("$cli" spawn --join "$join_id" "$model" || true)"
else
  branch="$(git -C "$PWD" branch --show-current 2>/dev/null || true)"
  block="$("$cli" spawn "pi/$model @ $(basename "$PWD")${branch:+ ($branch)}" "$model" || true)"
fi

# Degrade gracefully: spawn failed → launch pi WITHOUT an identity, not as a citizen, so the
# harness is never held hostage to the server being up.
if [ -z "$block" ]; then
  echo "tlon: spawn failed${join_id:+ for thread #$join_id} (see above) — launching pi without an identity, not as a citizen. If the service is down: 'mise run server:restart'" >&2
else
  eval "$block" # exports TLON_MCP_URL / TLON_THREAD / TLON_AUTHOR — adapters mints the token per connect (no TLON_TOKEN)
fi

set -- pi --provider "$provider" --model "$model" ${thinking:+--thinking "$thinking"} "$@"
if [ "${TLON_LAUNCH_DRYRUN:-}" = "1" ]; then
  printf 'identity: TLON_THREAD=%s TLON_AUTHOR=%s\n' "${TLON_THREAD:-<none>}" "${TLON_AUTHOR:-<none>}"
  printf 'exec: %s\n' "$*"
  exit 0
fi
exec "$@"
