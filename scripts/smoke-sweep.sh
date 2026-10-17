#!/usr/bin/env bash
# Remove what a SIGKILLed release-smoke.sh left behind (it never ran its cleanup): its build in
# ${TMPDIR:-/tmp}/tlon-smoke/ (and tlon-smoke-* beside it, an older checkout's), as worktrees of
# <repo-root>, and its tlon_smoke_* database:
#
#   smoke-sweep.sh <repo-root>
#
# A live run holds an flock on <dir>.lock for its whole life, and one on
# <git-common-dir>/tlon-smoke-db-<db>.lock for its database. The lock, not a pid or a command line,
# says it is alive: a run in another pid namespace (a sandbox) has pids this one can't see. The
# database's lock sits in the repo, not TMPDIR, because runs under different TMPDIRs share Postgres.
set -uo pipefail

root="$1"
for stale in "${TMPDIR:-/tmp}"/tlon-smoke/*/ "${TMPDIR:-/tmp}"/tlon-smoke-*/; do
  stale="${stale%/}"; [ -d "$stale" ] || continue
  if [ -e "$stale.lock" ]; then
    flock -n "$stale.lock" true || continue
  else
    # a build from before the lock: only once it is older than any build takes
    [ -n "$(find "$stale" -maxdepth 0 -mmin +120)" ] || continue
  fi
  git -C "$root" worktree remove --force "$stale" >/dev/null 2>&1; rm -rf "$stale" "$stale.lock"
done
# a lock whose build is gone: a cleanup cut short between the two
for lock in "${TMPDIR:-/tmp}"/tlon-smoke/*.lock; do
  [ -e "$lock" ] && [ ! -e "${lock%.lock}" ] || continue
  flock -n "$lock" true && rm -f "$lock"
done
git -C "$root" worktree prune

# A database some process is connected to stays even with no lock: a smoke from a checkout older
# than the database lock takes none. In a sandbox psql can't reach the socket and this does nothing.
locks="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
pg() { psql -h "${PGHOST:-/run/postgresql}" -d postgres -XAtq "$@" 2>/dev/null; }
pg -c "select d.datname from pg_database d where d.datname ~ '^tlon_smoke_'
       and not exists (select 1 from pg_stat_activity a where a.datname = d.datname)" |
  while read -r db; do
    lock="$locks/tlon-smoke-db-$db.lock"
    exec {fd}>"$lock"
    if flock -n "$fd"; then
      pg -c "DROP DATABASE IF EXISTS \"$db\""
      rm -f "$lock"
    fi
    exec {fd}>&-
  done
exit 0
