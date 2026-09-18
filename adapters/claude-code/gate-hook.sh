#!/usr/bin/env bash
# Claude Code Stop hook — the workline gate with teeth (field survey §4 adopt #3, after Claude
# Code's own TaskCompleted/TeammateIdle exit-2 pattern). When this session is a coworker on a
# WORKLINE whose current stage still owes its artifact, the stop is refused ONCE with the reason
# on stderr (exit 2 → Claude reads it and keeps working). `stop_hook_active` in the hook input
# is set when a Stop hook already bounced this turn — then we let it end, so a coworker that
# genuinely cannot produce the artifact is never looped forever. Plain threads: no-op.
#
# Never wedge a session: any failure to ask the server is exit 0.
set -uo pipefail

[ -n "${TLON_THREAD:-}" ] && [ -n "${TLON_MCP_URL:-}" ] || exit 0
command -v curl >/dev/null && command -v jq >/dev/null || exit 0

input="$(cat 2>/dev/null || true)"
if [ "$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null)" = "true" ]; then exit 0; fi

api="${TLON_MCP_URL%/mcp}/api/threads/$TLON_THREAD"
brief="$(curl -fsS --max-time 4 "$api" 2>/dev/null)" || exit 0
stage="$(jq -r '.workline.stage // empty' <<<"$brief")"
[ -n "$stage" ] || exit 0
ok="$(jq -r '.workline.artifact_ok' <<<"$brief")"
[ "$ok" = "false" ] || exit 0
why="$(jq -r '.workline.why // "artifact missing"' <<<"$brief")"

echo "tlon: this workline is at stage '$stage' and its owed artifact is not committed — $why. Commit it (then call advance_stage), or post on the thread why you cannot, before stopping." >&2
exit 2
