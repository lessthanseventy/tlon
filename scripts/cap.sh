#!/usr/bin/env bash
# cap — run a command ONCE, capture all output to a log, print a lean summary and the
# exact ways to read more. The pattern (root AGENTS.md): run once, inspect the saved log,
# NEVER re-run a command with escalating greps/tails to see more. Repetition is the signal
# to read the log, not repeat the call.
#
#   scripts/cap.sh mix test
#   scripts/cap.sh bash scratchpad/thing.sh
#   mise run cap -- mise exec -- mix test
#
# Knobs (env): CAP_TAIL (tail lines, default 40), CAP_KEEP (logs to retain, default 40).
set -uo pipefail

[ "$#" -gt 0 ] || { echo "cap: give me a command to run" >&2; exit 2; }

tail_n="${CAP_TAIL:-40}"
keep="${CAP_KEEP:-40}"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
log_dir="${CAP_LOG_DIR:-$root/.logs}"
mkdir -p "$log_dir"

ts="$(date +%Y%m%dT%H%M%S)"
slug="$(printf '%s' "$*" | tr -c 'A-Za-z0-9' '-' | tr -s '-' | cut -c1-48)"
log="$log_dir/${ts}-${slug}.log"

# Run it. All output to the log only — the point is NOT to stream it into context.
"$@" >"$log" 2>&1
rc=$?

lines="$(wc -l <"$log" | tr -d ' ')"
rel="${log#"$root"/}"

printf '▶ %s\n  log: %s  (%s lines)\n' "$*" "$rel" "$lines"

# A test/build-summary line, if one exists — surfaces "115 tests, 0 failures" up top so a
# green run needs no scrolling and no second look.
summary="$(grep -nEi '[0-9]+ (tests?|examples?|failures?|errors?|passed|failed|assertions?|warnings?)' "$log" | tail -1)"
[ -n "$summary" ] && printf '  summary: %s\n' "${summary#*:}"

if [ "$rc" -eq 0 ]; then
  printf '  ✓ exit 0\n'
  # A green run is short by default — you rarely need its body. Override with CAP_TAIL.
  [ -n "${CAP_TAIL:-}" ] || tail_n=6
else
  printf '  ✗ exit %s\n' "$rc"
  # Surface likely failure lines so a failure needs no second run to locate.
  hits="$(grep -nEi 'fail|error|✗|assert|exception|traceback|undefined|panic|refused' "$log" | head -15)"
  if [ -n "$hits" ]; then
    printf '  ── failure lines (grep) ──\n'
    printf '%s\n' "$hits" | sed 's/^/    /'
  fi
fi

printf '  ── tail %s ──\n' "$tail_n"
tail -n "$tail_n" "$log" | sed 's/^/    /'
printf '  more: tail -n 200 %s   |   grep -nEi PATTERN %s\n' "$rel" "$rel"

# Keep the log dir bounded — read the recent past, don't hoard it.
ls -1t "$log_dir"/*.log 2>/dev/null | tail -n "+$((keep + 1))" | xargs -r rm -f

exit "$rc"
