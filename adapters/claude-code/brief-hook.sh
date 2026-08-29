#!/usr/bin/env bash
# Claude Code SessionStart hook — Door 2 of the claude-code adapters adapter (the brief).
# Claude Code adds this hook's stdout to the session context on start/resume/clear. If the
# session carries a funes identity (TLON_THREAD), render that thread's brief so a fresh or
# /clear'd context re-orients from funes instead of from nothing.
#
# Never blocks the session: no identity, a down channel, or a missing thread is a silent
# no-op (exit 0, no output). Reads its JSON on stdin and ignores it.
set -euo pipefail

thread="${TLON_THREAD:-}"
[ -n "$thread" ] || exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
brief="$("$here/../../../scripts/tlon-cli.sh" dossier "$thread" 2>/dev/null || true)"
[ -n "$brief" ] || exit 0

printf '# funes — your thread #%s\n\n%s\n' "$thread" "$brief"
