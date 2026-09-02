#!/usr/bin/env bash
# Claude Code PostToolUse hook — auto-track (reshape slice B): a successful `git … commit`
# promotes this session's thread into the stage machine via the server's track_thread, so the ticket
# condenses out of the work. Thin wrapper like heartbeat-hook.sh: the logic is cc-track.ts
# (bun, shares activity.ts's isCommitCommand + mcp.ts's TlonClient with pi's side). Never
# blocks the tool call: any failure is a silent no-op.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
entry="$here/../pi/src/cc-track.ts"

command -v bun >/dev/null 2>&1 || exit 0
bun run "$entry" >/dev/null 2>&1
exit 0
