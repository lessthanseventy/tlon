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

# All output goes to the log only — not streamed into context. Strip ANSI as we store
# (pure noise). pipefail keeps the WRAPPED command's exit code, not sed's.
"$@" 2>&1 | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' >"$log"
rc=${PIPESTATUS[0]}

lines="$(wc -l <"$log" | tr -d ' ')"
rel="${log#"$root"/}"

printf '▶ %s\n  log: %s  (%s lines)\n' "$*" "$rel" "$lines"

# Surface a test/build-summary line, if one exists, up top so a green run needs no scrolling.
summary="$(grep -nEi '[0-9]+ (tests?|examples?|failures?|errors?|passed|failed|assertions?|warnings?)' "$log" | tail -1)"
[ -n "$summary" ] && printf '  summary: %s\n' "${summary#*:}"

failblock=0
if [ "$rc" -eq 0 ]; then
  printf '  ✓ exit 0\n'
  # Tiny by default — override with CAP_TAIL (a number, or `all` for the whole log inline).
  { [ "${CAP_TAIL:-}" = all ] || [ -n "${CAP_TAIL:-}" ]; } || tail_n=3
else
  printf '  ✗ exit %s\n' "$rc"
  { [ "${CAP_TAIL:-}" = all ] || [ -n "${CAP_TAIL:-}" ]; } || tail_n=5
  failblock=1

  # Framework-aware: the real failure blocks, not lines that merely contain "error".
  # Falls back to a generic grep for anything unrecognized.
  if grep -qE '^[[:space:]]+[0-9]+\) (test|doctest|property)' "$log"; then
    label="ExUnit failures"
    fails="$(awk '/^[[:space:]]+[0-9]+\) (test|doctest|property)/{p=1} p' "$log" | head -80)"
  elif grep -qiE '\(fail\)|✗ ' "$log"; then
    label="bun failures"
    fails="$(grep -nEiA2 '\(fail\)|✗ |expected:|received:' "$log" | head -50)"
  else
    label="failure lines"
    fails="$(grep -nEi 'fail|error|✗|assert|exception|traceback|undefined|panic|refused' "$log" | head -15)"
  fi
  if [ -n "$fails" ]; then
    printf '  ── %s ──\n' "$label"
    printf '%s\n' "$fails" | sed 's/^/    /'
  else
    failblock=0
  fi
fi

# The "good letters" — results, errors, warnings, counts, timings — with install/compile
# noise dropped. Shown only when there's no failure block (that block IS the signal
# already). The full log stays on disk untouched; this is only what we PRINT.
if [ "$failblock" -eq 0 ] && [ "${CAP_TAIL:-}" != all ]; then
  # Drop the known-noise lines FIRST (DB/debug/SQL chatter), THEN keep the good letters —
  # otherwise a per-query "idle=0.8ms" debug line reads as a "timing" and floods the view.
  noise_re='\[(debug|info|notice)\]|QUERY (OK|ERROR)|idle=[0-9]|queue=[0-9]|^[[:space:]]*(SELECT|INSERT|UPDATE|DELETE|BEGIN|COMMIT|begin|commit|RETURNING|FROM|WHERE|VALUES)'
  sig_re='[0-9]+ (tests?|examples?|failures?|errors?|warnings?|assertions?|passed|failed|skipped)|^(PASS|FAIL|ok |not ok)|✓|✗|✅|❌|⚠|error|warning|fail|exception|panic|fatal|refused|denied|cannot|unable|not found|timeout|finished in|compiling [0-9]+ file|generated |coverage|[0-9]+ (files?|packages?|dependencies|modules?)'
  signal="$(grep -vE "$noise_re" "$log" | grep -iE "$sig_re" | awk '!seen[$0]++' | head -"${CAP_SIGNAL:-12}")"
  if [ -n "$signal" ]; then
    printf '  ── signal ──\n'
    printf '%s\n' "$signal" | sed 's/^/    /'
  fi
fi

if [ "${CAP_TAIL:-}" = all ]; then
  printf '  ── full log (%s lines) ──\n' "$lines"
  sed 's/^/    /' "$log"
else
  printf '  ── tail %s ──\n' "$tail_n"
  tail -n "$tail_n" "$log" | sed 's/^/    /'
fi
printf '  more: tail -n 200 %s   |   grep -nEi PATTERN %s\n' "$rel" "$rel"

# Keep the log dir bounded.
ls -1t "$log_dir"/*.log 2>/dev/null | tail -n "+$((keep + 1))" | xargs -r rm -f

exit "$rc"
