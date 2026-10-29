#!/usr/bin/env bash
# Self-test of office-drive.sh's key steps, against a tmux and a bun that only record: a shell-quoted step
# ('108') reaches tmux unquoted, and a one-character step, even a shell metacharacter (the cast editor's `), is sent as typed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
# one line per tmux call, its arguments joined by "|"
printf '#!/bin/sh\nIFS="|"; echo "$*" >>"$TMUX_LOG"\n' >"$tmp/bin/tmux"
printf '#!/bin/sh\necho /bin/true\n' >"$tmp/bin/bun"
chmod +x "$tmp/bin/tmux" "$tmp/bin/bun"
export TMUX_LOG="$tmp/log" OFFICE_WAIT=0 PATH="$tmp/bin:$PATH"
bad=0

expect() { # expect <step> <keys tmux should get>
  : >"$TMUX_LOG"
  "$here/office-drive.sh" "$1" >/dev/null 2>&1
  local got; got="$(grep -F -- '|send-keys|-t|0|' "$TMUX_LOG" | sed -e 's/.*|send-keys|-t|0|//' -e 's/^-l|//' -e 's/^--|//')"
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: sent [$got], want [$2]"; bad=1; fi
}

expect '`' '`'
expect '"' '"'
expect ';' ';'
expect '&' '&'
expect "'my title'" 'my title'
expect "'108'" '108'
expect 'Enter' 'Enter'
exit $bad
