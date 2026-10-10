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

# CHECKS_LABEL names the run for the rack and the room (a workline's: "#<id> verify|landing <slug>")
label="${CHECKS_LABEL:-$*}"
me="$label (pid $$) in $PWD since $(date +%H:%M:%S)"

# the office's rack reads the holder and the waiters (Server.Office.Room.checks/0)
if ! flock -n 9; then
  echo "checks queue: waiting — $(cat "$holder" 2>/dev/null || echo 'another check is running')" >&2
  mkdir -p "$dir/tlon-checks.wait" 2>/dev/null && echo "$me" >"$dir/tlon-checks.wait/$$" 2>/dev/null
  trap 'rm -f "$dir/tlon-checks.wait/$$"' EXIT
  flock 9
  rm -f "$dir/tlon-checks.wait/$$"
fi

echo "$label (pid $$) in $PWD since $(date +%H:%M:%S)" >"$holder" 2>/dev/null || true
# a killed check must not leave its line behind as if it still ran
trap ': >"$holder" 2>/dev/null' EXIT
# 9>&-: what the check leaves running (a watcher, a dev server) must not keep holding the lock.
# In the background and waited on, so a TERM stops the check and clears the line at once.
# In its own process group, so stopping it stops its test runs too, not just the top process.
setsid "$@" 9>&- &
child=$!
trap 'kill -TERM -- "-$child" 2>/dev/null; exit 143' TERM
trap 'kill -TERM -- "-$child" 2>/dev/null; exit 130' INT
wait "$child"

