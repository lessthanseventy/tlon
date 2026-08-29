#!/usr/bin/env bash
# Claude Code Stop hook — the claude-code adapter's capture reflex (one-ledger Cut 1, Task 4).
# Mirrors pi's cadence capture (adapters/pi's extension.ts + capture.ts): extract durable facts from
# the turn's transcript delta and bank them `derived` to funes, unbidden.
#
# Thin wrapper like brief-hook.sh: the actual logic is cc-capture.ts (bun, reuses capture.ts's
# pure core + mcp.ts's FunesClient — no forked extraction prompt). Never blocks the session: any
# failure in the bun entry is its own silent no-op (exit 0, no output); this wrapper adds one more
# no-op layer in case bun itself is missing, so a broken/uninstalled bun still can't wedge Stop.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
entry="$here/../pi/src/cc-capture.ts"

command -v bun >/dev/null 2>&1 || exit 0
bun run "$entry" >/dev/null 2>&1
exit 0
