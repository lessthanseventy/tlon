#!/usr/bin/env bash
# Self-test of release-smoke.sh's build lock and pool verdict (lib/smoke-build.sh, which the script
# sources): two builds under the lock run one after the other, the second says whose build it waits
# for, a killed holder frees the lock, and a log whose tail holds a Postgres pool failure is named.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$tmp"' EXIT
bad=0
log="$tmp/log" lock="$tmp/build.lock"
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; bad=1; fi; }
until_log() { local i=0; while ! grep -q "^$1" "$log" && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; }
# build <name> <seconds>: a fake build under the lock, in a shell of its own as each smoke is
build() {
  (
    . "$here/lib/smoke-build.sh"
    smoke_build_lock "$lock" "$1" >"$tmp/out-$1" 2>&1
    echo "start $1" >>"$log"; sleep "$2"; echo "end $1" >>"$log"
    smoke_build_unlock
  )
}

: >"$log"
build A 1 & until_log "start A"
build B 0 & wait
expect "two builds run one after the other" "$(tr '\n' ' ' <"$log")" "start A end A start B end B "
expect "the second says whose build it waits for" "$(cat "$tmp/out-B")" "smoke: waiting for A's build"
expect "the first waits for no one" "$(cat "$tmp/out-A")" ""

: >"$log"
( . "$here/lib/smoke-build.sh"; smoke_build_lock "$lock" K >/dev/null; echo "start K" >>"$log"; exec sleep 30 ) & kpid=$!
until_log "start K"
build C 0 & cpid=$!
sleep 0.3; kill -9 "$kpid" 2>/dev/null
wait "$cpid"; wait "$kpid" 2>/dev/null
expect "a killed holder does not block the next build" "$(grep -c '^end C' "$log")" "1"

: >"$log"
leaver() { sleep 30 >/dev/null 2>&1 & }
( . "$here/lib/smoke-build.sh"; smoke_build_lock "$lock" D >/dev/null; smoke_isolated leaver; smoke_build_unlock )
timeout 5 bash -c '. "$1/lib/smoke-build.sh"; smoke_build_lock "$2" E >/dev/null && echo got' _ "$here" "$lock" >"$tmp/out-E"
expect "a build's leftover child does not keep the lock" "$(cat "$tmp/out-E")" "got"

. "$here/lib/smoke-build.sh"
printf 'boot\n** (DBConnection.ConnectionError) connection not available and request was dropped from queue after 5940ms\n' >"$log"
expect "a DBConnection tail is named" "$(smoke_pool_cause "$log")" \
  "Postgres ran out of connections during the migration (another smoke or gate was building): wait for it, then re-run"
printf 'FATAL: sorry, too many clients already (too_many_connections)\n' >"$log"
expect "a too_many_connections tail is named" "$(smoke_pool_cause "$log" | cut -c1-38)" "Postgres ran out of connections during"
printf 'compile error: undefined function foo/0\n' >"$log"
expect "any other tail is not" "$(smoke_pool_cause "$log")" ""
{ echo "** (DBConnection.ConnectionError) old"; seq 40; } >"$log"
expect "only the tail counts" "$(smoke_pool_cause "$log")" ""

# smoke_pick_port: the base, or the first above it nothing listens on; epmd's 4369 and the service's 4040 are never picked
expect "a free base is itself" "$(smoke_pick_port 4700)" "4700"
expect "epmd's port is skipped" "$(smoke_pick_port 4369)" "4370"
expect "the service's port is skipped" "$(smoke_pick_port 4040)" "4041"
( exec elixir -e ':gen_tcp.listen(4600, []); Process.sleep(:infinity)' ) >/dev/null 2>&1 & lpid=$!
for i in $(seq 1 100); do smoke_port_taken 4600 && break; sleep 0.1; done
expect "a base with a listener steps on" "$(smoke_pick_port 4600)" "4601"
kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null

exit "$bad"
