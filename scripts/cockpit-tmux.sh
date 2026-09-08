#!/usr/bin/env bash
# Drive the live cockpit in the dedicated tmux server (-L tlon, session "cockpit") — the helper
# behind the drive-cockpit skill. Steals tmux-cli's one good mechanic: capture only once the pane
# has SETTLED (two identical captures 300 ms apart), so a read never lands mid-repaint.
#   cockpit-tmux.sh cap            print the frame (plain text)
#   cockpit-tmux.sh idle [secs]    wait until the frame stops changing (default 5 s), then print it
#   cockpit-tmux.sh send KEYS...   send tmux key names (M-d, Escape, Enter, j, ...), settle, print
#   cockpit-tmux.sh type TEXT      send TEXT literally (into an input), settle, print
#   cockpit-tmux.sh size COLS ROWS resize the window (the narrow layout kicks in under 80 cols)
# Never kills anything: the session is Andrew's window; `q` in the cockpit is the way out.
set -euo pipefail
T=(tmux -L "${COCKPIT_TMUX_SOCKET:-tlon}")
TARGET="${COCKPIT_TMUX_TARGET:-cockpit}"

cap() { "${T[@]}" capture-pane -t "$TARGET" -p; }
idle() {
  local deadline=$(( $(date +%s%3N) + ${1:-5}*1000 )) prev cur
  prev="$(cap)"
  while :; do
    sleep 0.3
    cur="$(cap)"
    [ "$cur" = "$prev" ] && break
    prev="$cur"
    [ "$(date +%s%3N)" -ge "$deadline" ] && { echo "cockpit-tmux: frame still changing after ${1:-5}s" >&2; break; }
  done
  printf '%s\n' "$cur"
}
case "${1:-}" in
  cap)  cap ;;
  idle) idle "${2:-5}" ;;
  send) shift; "${T[@]}" send-keys -t "$TARGET" "$@"; idle 5 ;;
  type) shift; "${T[@]}" send-keys -t "$TARGET" -l "$*"; idle 5 ;;
  size) "${T[@]}" resize-window -t "$TARGET" -x "$2" -y "$3"; idle 3 ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
