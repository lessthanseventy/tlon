#!/usr/bin/env bash
# Claude Code SessionStart hook — Door 2 of the claude-code adapter (the brief).
# Claude Code adds this hook's stdout to the session context on start/resume/clear. If the
# session carries a server identity (TLON_THREAD), render that thread's brief so a fresh or
# /clear'd context re-orients from the server instead of from nothing.
#
# Known limitation: the brief comes via `bin/server rpc` into the always-up service node
# regardless of TLON_MCP_URL, so a console-launched claude (:4041 / .dev) briefs from the
# service db, not the world it was spawned into.
#
# Never blocks the session: no identity is a silent no-op; a failed dossier (no release,
# service down, no such thread) logs to stderr and still exits 0 with no output. Reads its
# JSON on stdin and ignores it.
set -euo pipefail

thread="${TLON_THREAD:-}"
[ -n "$thread" ] || exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! brief="$("$here/../../../scripts/tlon-cli.sh" dossier "$thread")"; then
  echo "tlon brief-hook: dossier for thread #$thread failed — session starts without a brief" >&2
  exit 0
fi
[ -n "$brief" ] || exit 0

printf '# tlon — your thread #%s\n\n%s\n' "$thread" "$brief"
