#!/usr/bin/env bash
# Claude Code presence hook — the session's place on the roster. Wired by launch.sh as
# SessionStart with "start" (register the session, as pi does at its session_start: without it
# the worker has no session row, so the roster and warmth never see it), UserPromptSubmit
# (declare thinking, bare invocation), PreToolUse with "doing" (what tool is running, for the
# office's animations and the thread card's activity timeline) and Stop/SessionEnd with "idle" (clear it; SessionEnd is the exit/crash
# safety net — the server's max-age sweep backstops the rest).
#
# Thin wrapper like capture-hook.sh: the logic is cc-presence.ts (bun, reuses mcp.ts's
# TlonClient). Never blocks the session: any failure is a silent no-op, and a missing bun
# still can't wedge the hook.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
entry="$here/../pi/src/cc-presence.ts"

command -v bun >/dev/null 2>&1 || exit 0
# "doing" fires before every tool call: detached, so a cold bun never slows a tool down. It may
# land after the turn's idle; the server ignores a doing outside a turn.
if [ "${1:-}" = doing ]; then
  input="$(cat)"
  printf '%s' "$input" | bun run "$entry" doing >/dev/null 2>&1 &
  exit 0
fi
bun run "$entry" "${1:-thinking}" >/dev/null 2>&1
exit 0
