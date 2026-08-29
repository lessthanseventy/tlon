#!/usr/bin/env bash
# pi model launcher + funes citizenship. The `pi:*` mise tasks pass a fixed
# --provider/--model/[--thinking]; an optional trailing numeric thread-id joins that funes
# thread (else a fresh one is opened). Everything after is passed through to pi.
#
# This exports the TLON_* block and pi's adapters extension reads it at session_start to
# register. If the funes channel isn't up, pi still launches — just not as a funes citizen.
set -euo pipefail

adapter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$adapter/../../.." && pwd)"
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

# Optional leading numeric thread-id → join that funes thread; else open a fresh one.
# The agent is the MODEL, so `funes:roster` shows which model is on the thread.
join_id=""
if [ -n "${1:-}" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
  join_id="$1"
  shift
fi

if [ -n "$join_id" ]; then
  block="$("$cli" spawn --join "$join_id" "$model" 2>/dev/null || true)"
else
  branch="$(git -C "$PWD" branch --show-current 2>/dev/null || true)"
  block="$("$cli" spawn "pi/$model @ $(basename "$PWD")${branch:+ ($branch)}" "$model" 2>/dev/null || true)"
fi

if [ -z "$block" ]; then
  echo "funes: channel not up${join_id:+ or no thread #$join_id} — launching pi WITHOUT a funes identity (start it with 'mise run funes:restart')" >&2
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
