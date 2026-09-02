#!/usr/bin/env bash
# Claude Code PostToolUse hook — the claude-code adapter's heartbeat (funes thread #3,
# 2026-08-27). Mirrors pi's turn_start/turn_end interval (adapters/pi's extension.ts): a periodic
# "here's what's happening" check-in posted to the thread during a long single turn, instead of
# silence until Stop.
#
# Thin wrapper like capture-hook.sh: the actual logic is cc-heartbeat.ts (bun, reuses activity.ts's
# pure cadence gate + message-building, and mcp.ts's TlonClient). Never blocks the tool call: any
# failure in the bun entry is its own silent no-op (exit 0, no output); this wrapper adds one more
# no-op layer in case bun itself is missing.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
entry="$here/../pi/src/cc-heartbeat.ts"

command -v bun >/dev/null 2>&1 || exit 0
bun run "$entry" >/dev/null 2>&1
exit 0
