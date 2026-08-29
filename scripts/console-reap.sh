#!/usr/bin/env bash
# scripts/console-reap.sh — reap a stale `console:run` cockpit so a fresh launch can bind.
#
# console's in-process server world listens on 4041 (server.service uses 4040 — two worlds,
# one box). A cockpit that lost its TTY keeps holding 4041, and the next `console:run`
# dies with :eaddrinuse; this clears that stale listener before launch.
#
# Kills ONLY the process LISTENING on the port (ss also lists tmux clients holding an
# inherited fd — killing those would murder the user's tmux). Also reaps orphaned
# `mise run console:run` wrappers left hanging on a dead beam child (mise doesn't always
# exit when its beam is killed), without touching this invocation's own process tree.
#
# Safe to run any time; a free port is a no-op. Override the port with TLON_MCP_PORT.
set -euo pipefail

PORT="${TLON_MCP_PORT:-4041}"

# 1. reap the port listener
# ss -tlnpH "sport = :N" prints one line per listening socket with users:(("comm",pid=N,...)).
# The -p is load-bearing: WITHOUT it ss omits the users:/pid= field entirely, so the grep below
# finds nothing and this whole step silently no-ops (the port never gets freed, and step 3 then
# fails the launch). Grab every pid on the line — an inherited listen fd (a coworker pi that
# survived the tmux kill) shows up as an extra ("pi",pid=...) holder that must die too.
mapfile -t pids < <(ss -tlnpH "sport = :$PORT" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u || true)

if [ "${#pids[@]}" -gt 0 ]; then
  for pid in "${pids[@]}"; do
    cmd="$(ps -o comm= -p "$pid" 2>/dev/null || echo '?')"
    echo "console-reap: killing stale listener on $PORT — pid $pid ($cmd)"
    kill "$pid" 2>/dev/null || true
  done
  # Graceful first; SIGKILL any survivor after a beat.
  sleep 1
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "console-reap: pid $pid didn't exit — SIGKILL"
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
fi

# 2. reap orphaned mise/mix wrappers for THIS task
# A `mise run console:run` whose beam child just died (step 1) can hang on the dead child.
# Kill any such wrapper that is NOT an ancestor of this shell, so the invoking mise is
# never touched.
ancestors=" $$"
p="${PPID:-0}"
while [ "$p" -gt 1 ] 2>/dev/null; do
  ancestors="$ancestors $p"
  next="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"
  [ -n "$next" ] || break
  p="$next"
done

orphans="$(pgrep -af 'mise run console:run|mix console\.run' 2>/dev/null || true)"
if [ -n "$orphans" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opid="${line%% *}"
    # Skip if it's this shell or an ancestor of it.
    case "$ancestors" in
      *" $opid "*) continue ;;
    esac
    echo "console-reap: killing orphaned wrapper — $line"
    kill "$opid" 2>/dev/null || true
  done <<<"$orphans"
  sleep 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opid="${line%% *}"
    case "$ancestors" in
      *" $opid "*) continue ;;
    esac
    kill -0 "$opid" 2>/dev/null && { echo "console-reap: pid $opid didn't exit — SIGKILL"; kill -9 "$opid" 2>/dev/null || true; }
  done <<<"$orphans"
fi

# 3. confirm
if ss -tlnH "sport = :$PORT" 2>/dev/null | grep -q .; then
  echo "console-reap: WARNING — port $PORT still held after reap:" >&2
  ss -tlnp "sport = :$PORT" 2>/dev/null | sed 's/^/  /' >&2
  exit 1
fi
echo "console-reap: port $PORT free."