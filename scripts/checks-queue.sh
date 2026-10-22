#!/usr/bin/env bash
# The machine's checks queue: one full check at a time, whoever asks for it — a workline's verify,
# a landing's gate, a nightly schedule, a coworker before a commit, a session at the terminal.
#
# Every full check compiles everything and runs the whole server suite against the one test
# database, so two at once slow the machine to a crawl and wipe each other's rows (tests that
# fail only when another suite runs beside them). This takes a ticket, waits for the lowest live one
# (first come, first served), then takes the machine-wide lock, saying who holds it; the command
# runs once the lock is free and releases it on exit.
#
#   scripts/checks-queue.sh <command…>        e.g. scripts/checks-queue.sh mise run check:all
#
# A shell that cannot open the lock file (a sandbox that hides the runtime dir) is refused, exit 2:
# its suite would run beside the merge queue's gates, and a sandboxed run can't post tlon/check
# anyway. Run it unsandboxed. CHECKS_UNQUEUED=1 runs it without the queue, for a box with no
# usable XDG_RUNTIME_DIR.
set -u
. "$(dirname "$0")/lib/fresh-script.sh"
refuse_stale_script "$0"

dir="${XDG_RUNTIME_DIR:-/tmp}"
lock="$dir/tlon-checks.lock"
holder="$dir/tlon-checks.holder"

# braces: a bare `exec … 2>/dev/null` would silence the whole script's stderr, the check's too
if ! { exec 9>>"$lock"; } 2>/dev/null; then
  if [ "${CHECKS_UNQUEUED:-}" = 1 ]; then
    echo "checks queue: can't open $lock — running unqueued (CHECKS_UNQUEUED=1)" >&2
    exec "$@"
  fi
  echo "checks queue: can't open $lock — run the check unsandboxed (a sandboxed Bash hides the queue), or set CHECKS_UNQUEUED=1 on a box with no runtime dir" >&2
  exit 2
fi

# CHECKS_LABEL names the run for the rack and the room (a workline's: "#<id> verify|landing <slug>")
# who asked, so a queue of bare `scripts/check.sh` lines says whose each is: a seat by its handle and
# thread, anything else (a terminal, the operator's own session) as the operator
label="${CHECKS_LABEL:-${TLON_AUTHOR:-operator}${TLON_THREAD:+ on #$TLON_THREAD}: $* @ $(git rev-parse --short HEAD 2>/dev/null || echo '?')}"
me="$label (pid $$) in $PWD since $(date +%H:%M:%S)"

# FIFO: a ticket, then the lock only for the lowest live ticket. The lock (the kernel's flock) still
# does the mutual exclusion; the tickets only decide who may try it, so a newcomer never beats a
# waiter. The office's rack reads the holder and the waiters (Server.Office.Room.checks/0).
wait_dir="$dir/tlon-checks.wait"
seq_file="$dir/tlon-checks.seq"
poll="${CHECKS_POLL:-0.5}"

# alive <pid>: a running checks-queue.sh (the cmdline guard keeps a reused pid from holding the line)
alive() { [ "$1" = "$$" ] || { [ -r "/proc/$1/cmdline" ] && tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -q 'checks-queue\.sh'; }; }

# take_ticket: the next number, and the entry <10-digit ticket>-<pid> written under the same lock, so
# no ticket is ever taken but invisible. Prints the entry's path; fails if the bookkeeping can't be written.
take_ticket() {
  mkdir -p "$wait_dir" || return 1
  (
    exec 8>>"$seq_file" || exit 1
    flock 8 || exit 1
    n="$(cat "$seq_file")"
    n=$((10#${n:-0} + 1))
    printf '%d\n' "$n" >"$seq_file" || exit 1
    entry="$wait_dir/$(printf '%010d' "$n")-$$"
    printf '%s\n' "$me" >"$entry" || exit 1
    printf '%s' "$entry"
  )
}

if entry="$(take_ticket 2>/dev/null)" && [ -n "$entry" ]; then
  trap 'rm -f "$entry"' EXIT
  told=0
  # a waiter says so again every heartbeat: a scheduled run's timeout restarts at each line
  # (Server.Schedules), so a long wait is not mistaken for a hung check
  heartbeat="${CHECKS_HEARTBEAT:-600}" next_word=0
  while :; do
    head=""
    for f in "$wait_dir"/[0-9]*-[0-9]*; do # padded tickets: glob order is arrival order
      [ -e "$f" ] || continue
      if alive "${f##*-}"; then head="$f"; break; fi
      rm -f "$f" # a dead waiter's ticket: whoever notices removes it
    done
    if [ "$head" = "$entry" ] && flock -n 9; then break; fi
    if [ "$SECONDS" -ge "$next_word" ]; then
      echo "checks queue: waiting — $(cat "$holder" 2>/dev/null || echo 'another check is running')" >&2
      told=1 next_word=$((SECONDS + heartbeat))
    fi
    sleep "$poll"
  done
  rm -f "$entry"
  [ "$told" = 1 ] && echo "checks queue: your turn" >&2
else
  echo "checks queue: can't write $wait_dir or $seq_file — falling back to a plain lock, no queue order" >&2
  flock 9
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

