#!/usr/bin/env bash
# Claude Code presence hook — thinking counts as working. Wired by launch.sh as
# UserPromptSubmit (declare thinking, bare invocation) and as Stop/SessionEnd with "idle"
# (clear it; SessionEnd is the exit/crash safety net — funes' max-age sweep backstops the rest).
#
# Thin wrapper like capture-hook.sh: the logic is cc-presence.ts (bun, reuses mcp.ts's
# TlonClient). Never blocks the session: any failure is a silent no-op, and a missing bun
# still can't wedge the hook.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
entry="$here/../pi/src/cc-presence.ts"

command -v bun >/dev/null 2>&1 || exit 0
bun run "$entry" "${1:-thinking}" >/dev/null 2>&1
exit 0
