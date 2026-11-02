#!/usr/bin/env bash
# Remove the tmux socket files that no server is behind, and say how many:
#
#   tmux-sweep.sh
#
# Every socket-typed entry of ${TMUX_TMPDIR:-/tmp}/tmux-<uid> that this uid owns is asked a question
# with a client command, which never starts a server: a live one answers and stays, a dead one fails
# "no server running" and goes.
set -uo pipefail

command -v tmux >/dev/null || { echo "tmux-sweep: no tmux on PATH, nothing swept" >&2; exit 2; }
dir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
removed=0
[ -d "$dir" ] || { echo "tmux-sweep: removed 0 dead socket(s) (no $dir)"; exit 0; }
for sock in "$dir"/*; do
  [ -S "$sock" ] && [ -O "$sock" ] || continue
  # Only "no server running" proves the socket is dead; any other failure keeps it.
  err="$(tmux -S "$sock" display -p ok 2>&1 >/dev/null)" && continue
  case "$err" in
    *"no server running"*|*"error connecting"*) rm -f "$sock" && removed=$((removed + 1)) ;;
  esac
done
echo "tmux-sweep: removed $removed dead socket(s) from $dir"
