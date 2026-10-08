#!/usr/bin/env bash
# Drive the office TUI headlessly: start it in a private tmux server (never the operator's), send
# each step's keys, print the screen after each, then tear it all down — in ONE call, because a
# harness may reap a tmux server between calls. Half blocks under tmux, so the frame is text.
#
#   office-drive.sh STEP...      each STEP is tmux send-keys arguments: "/" "'108'" "Enter" "M-Enter"
#
# TLON_URL picks the server (default the service's 127.0.0.1:4040; `server:dev` is :4041).
# OFFICE_COLS/OFFICE_ROWS size the window (150x60), OFFICE_WAIT the settle per step (1.5 s),
# OFFICE_TAIL how many bottom rows to print (20; the detail pane and foot live there).
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sock="office-drive-$$"
state="$(mktemp -d)"
t() { tmux -L "$sock" "$@"; }
trap 't kill-server 2>/dev/null; rm -rf "$state"' EXIT

t new-session -d -x "${OFFICE_COLS:-150}" -y "${OFFICE_ROWS:-60}" \
  "cd '$root/office' && TLON_URL='${TLON_URL:-http://127.0.0.1:4040}' OFFICE_GRAPHICS=blocks MISE_TRUSTED_CONFIG_PATHS='$root' XDG_STATE_HOME='$state' bun tui/main.ts 2>'$state/err'"
sleep 3
for step in "$@"; do
  eval "t send-keys -t 0 $step"
  sleep "${OFFICE_WAIT:-1.5}"
  echo "=== after: $step"
  t capture-pane -p -t 0 | tail -n "${OFFICE_TAIL:-20}"
done
[ -s "$state/err" ] && { echo "=== stderr"; cat "$state/err"; }
exit 0
