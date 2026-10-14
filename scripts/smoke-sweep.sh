#!/usr/bin/env bash
# Remove the smoke builds a SIGKILLed release-smoke.sh left behind (it never ran its cleanup), in
# ${TMPDIR:-/tmp}/tlon-smoke/ (and tlon-smoke-* beside it, an older checkout's), as worktrees of
# <repo-root>:
#
#   smoke-sweep.sh <repo-root>
#
# A live run holds an flock on <dir>.lock for its whole life. The lock, not a pid or a command
# line, says it is alive: a run in another pid namespace (a sandbox) has pids this one can't see.
set -uo pipefail

root="$1"
for stale in "${TMPDIR:-/tmp}"/tlon-smoke/*/ "${TMPDIR:-/tmp}"/tlon-smoke-*/; do
  stale="${stale%/}"; [ -d "$stale/server" ] || continue
  if [ -e "$stale.lock" ]; then
    flock -n "$stale.lock" true || continue
  else
    # a build from before the lock: only once it is older than any build takes
    [ -n "$(find "$stale" -maxdepth 0 -mmin +120)" ] || continue
  fi
  git -C "$root" worktree remove --force "$stale" >/dev/null 2>&1; rm -rf "$stale" "$stale.lock"
done
git -C "$root" worktree prune
