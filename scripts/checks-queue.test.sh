#!/usr/bin/env bash
# Self-test of checks-queue.sh: waiters run in the order they arrived (even one arriving as the slot
# frees), a killed waiter does not block the line, two checks never overlap, and bookkeeping that
# cannot be written falls back to a plain lock. Runs the real script against a private runtime dir.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$tmp"' EXIT
bad=0
export XDG_RUNTIME_DIR="$tmp/run" CHECKS_POLL=0.05 TLON_STALE_SCRIPTS_OK=1
unset CHECKS_UNQUEUED
log="$tmp/log"
err="$tmp/err"
fresh() { rm -rf "$XDG_RUNTIME_DIR"; mkdir -p "$XDG_RUNTIME_DIR"; : >"$log"; : >"$err"; }
# job <name> <seconds>: a check that logs its start and end
job() { CHECKS_LABEL="$1" "$here/checks-queue.sh" bash -c "echo start $1 >>'$log'; sleep $2; echo end $1 >>'$log'" 2>>"$err"; }
queued() { ls "$XDG_RUNTIME_DIR/tlon-checks.wait" 2>/dev/null | wc -l; }
until_queued() { local i=0; while [ "$(queued)" -lt "$1" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; }
until_log() { local i=0; while ! grep -q "^$1" "$log" && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; }
starts() { grep '^start' "$log" | cut -d' ' -f2 | tr '\n' ' '; }
first_waiter() { ls "$XDG_RUNTIME_DIR/tlon-checks.wait" | head -1 | cut -s -d- -f2; }
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; bad=1; fi; }

fresh
job A 1 & until_log "start A"
job B 0 & until_queued 1
job C 0 & until_queued 2
wait
expect "A, B, C run in arrival order" "$(starts)" "A B C "

got=""
for _ in $(seq "${CHECKS_RACE_LOOPS:-20}"); do
  fresh
  job A 0.3 & a=$!; until_log "start A"
  job B 0 & until_queued 1
  wait "$a"; job C 0 &
  wait
  got="$(starts)"; [ "$got" = "A B C " ] || break
done
expect "C arriving as the slot frees runs after B (${CHECKS_RACE_LOOPS:-20} rounds)" "$got" "A B C "

fresh
job A 1 & until_log "start A"
job B 0 & until_queued 1
bpid="$(first_waiter)"
job C 0 & until_queued 2
[ -n "$bpid" ] && kill -9 "$bpid"
wait
expect "a SIGKILLed waiter does not block the line" "$(starts)" "A C "
expect "its entry is reaped" "$(queued | tr -d ' ')" "0"

fresh
job A 1 & until_log "start A"
job B 0 & until_queued 1
bpid="$(first_waiter)"
[ -n "$bpid" ] && kill -TERM "$bpid"
sleep 0.3
expect "a TERMed waiter removes its own entry at once" "$(queued | tr -d ' ')" "0"
wait

fresh
for n in 1 2 3 4; do job "J$n" 0.1 & done
wait
expect "two checks never overlap" "$(awk '{ if ($1 == prev) bad = 1; prev = $1 } END { print bad ? "overlap" : "serial" }' "$log")" "serial"
expect "all four ran" "$(wc -l <"$log" | tr -d ' ')" "8"

fresh
: >"$XDG_RUNTIME_DIR/tlon-checks.wait" # a file where the dir should be: bookkeeping cannot be written
job A 0 &
wait
expect "unwritable bookkeeping still runs the check" "$(starts)" "A "
expect "…and says it fell back" "$(grep -c 'falling back' "$err")" "1"

exit "$bad"
