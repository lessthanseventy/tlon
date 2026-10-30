#!/usr/bin/env bash
# Self-test of office-drive.sh's key steps, against a tmux and a bun that only record: a shell-quoted step
# ('108') reaches tmux unquoted, and a one-character step, even a shell metacharacter (the cast editor's `), is sent as typed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
# one line per tmux call, its arguments joined by "|"; a capture-pane prints the frame in $TMUX_FRAME
printf '#!/bin/sh\nIFS="|"; echo "$*" >>"$TMUX_LOG"\ncase "$*" in *capture-pane*) cat "$TMUX_FRAME";; esac\n' >"$tmp/bin/tmux"
printf '#!/bin/sh\necho /bin/true\n' >"$tmp/bin/bun"
chmod +x "$tmp/bin/tmux" "$tmp/bin/bun"
printf 'Ding dong!\n' >"$tmp/frame"
export TMUX_LOG="$tmp/log" TMUX_FRAME="$tmp/frame" OFFICE_WAIT=0 PATH="$tmp/bin:$PATH"
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

# ticks:N sends no keys, and captures every 10 ticks: 20 ticks is 2 captures, plus the last frame every step prints
expect 'ticks:3' ''
: >"$TMUX_LOG"
out="$("$here/office-drive.sh" 'ticks:20' 2>&1)"
captures="$(grep -c 'capture-pane' "$TMUX_LOG")"
if [ "$captures" = 3 ]; then echo "ok   ticks:20 captures 3 frames"; else echo "FAIL ticks:20: $captures captures, want 3"; bad=1; fi
# the union of text seen across the captures comes before the step's frame, so a balloon that came and went still shows
if printf '%s\n' "$out" | sed -n '/^=== seen/,/^=== after/p' | grep -qx 'Ding dong!'; then echo "ok   ticks:20 lists the balloon seen"; else echo "FAIL ticks:20: no seen-union with the balloon"; bad=1; fi
exit $bad
