#!/usr/bin/env bash
# The machine's checks queue: one full check at a time, whoever asks for it — a workline's verify,
# a landing's gate, a nightly schedule, a coworker before a commit, a session at the terminal.
#
# Every full check compiles everything and runs the whole server suite against the one test
# database, so two at once slow the machine to a crawl and wipe each other's rows (tests that
# fail only when another suite runs beside them). This takes a machine-wide lock first and waits
# its turn, saying who holds it; the command runs once the lock is free and releases it on exit.
#
#   scripts/checks-queue.sh <command…>        e.g. scripts/checks-queue.sh mise run check:all
#
# A shell that cannot open the lock file (a sandbox that hides the runtime dir) runs unqueued, and
# says so: the check still runs, it just doesn't wait.
set -u

dir="${XDG_RUNTIME_DIR:-/tmp}"
lock="$dir/tlon-checks.lock"
holder="$dir/tlon-checks.holder"

# braces: a bare `exec … 2>/dev/null` would silence the whole script's stderr, the check's too
if ! { exec 9>>"$lock"; } 2>/dev/null; then
  echo "checks queue: can't open $lock — running unqueued" >&2
  exec "$@"
fi

if ! flock -n 9; then
  echo "checks queue: waiting — $(cat "$holder" 2>/dev/null || echo 'another check is running')" >&2
  flock 9
fi

printf '%s (pid %s) in %s since %s\n' "$*" "$$" "$PWD" "$(date +%H:%M:%S)" >"$holder" 2>/dev/null || true
"$@"
status=$?
: >"$holder" 2>/dev/null || true
exit "$status"
