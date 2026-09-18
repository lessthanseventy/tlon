#!/usr/bin/env bash
# Claude Code SessionStart hook — Door 2 of the claude-code adapter (the brief).
# Claude Code adds this hook's stdout to the session context on start/resume/clear. If the
# session carries a server identity (TLON_THREAD), render that thread's brief so a fresh or
# /clear'd context re-orients from the server instead of from nothing.
#
# The brief comes from the node that spawned this session: `tlon-cli.sh dossier` calls the
# `get_dossier` MCP tool at TLON_MCP_URL (a console-launched claude briefs from the :4041
# .dev world, a service-launched one from :4040) — the same world Door 1's tools talk to.
# Rendered as JSON.
#
# Never blocks the session: no identity is a silent no-op; a failed dossier (node down, no
# such thread, unknown agent) logs to stderr and still exits 0 with no output. Reads its
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

# Seancing: the brief is a budgeted VIEW of the record; the record answers past every cap.
printf '# tlon — your thread #%s\n\n_This brief is a budgeted view. The record answers past every cap: get_facts, get_messages, search_history, search_facts._\n\n%s\n' "$thread" "$brief"
