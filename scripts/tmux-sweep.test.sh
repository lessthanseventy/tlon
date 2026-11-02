#!/usr/bin/env bash
# Self-test of tmux-sweep.sh: the dead tmux sockets go, the live ones stay, and nothing else in the
# directory is touched. Runs under a private TMUX_TMPDIR, never the real /tmp/tmux-<uid>.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0
export TMUX_TMPDIR="$tmp"
dir="$tmp/tmux-$(id -u)"
mkdir -p "$dir"

live="$dir/tlon-sweep-live"
dead="$dir/tlon-sweep-dead"
tmux -S "$live" new-session -d cat
tmux -S "$dead" new-session -d true
for _ in $(seq 50); do tmux -S "$dead" ls >/dev/null 2>&1 || break; sleep 0.02; done
printf 'keep me\n' >"$dir/not-a-socket"
[ -S "$dead" ] || { echo "FAIL setup: the dead server left no socket file to sweep"; exit 1; }

out="$("$here/tmux-sweep.sh" 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL the sweep exits 0 (got $code): $out"; bad=1; }
[ ! -e "$dead" ] && echo "ok   a dead socket is removed" || { echo "FAIL a dead socket must be removed"; bad=1; }
[ -S "$live" ] && tmux -S "$live" display -p ok >/dev/null 2>&1 \
  && echo "ok   a live server's socket stays, and it still answers" \
  || { echo "FAIL a live server must survive the sweep"; bad=1; }
[ -f "$dir/not-a-socket" ] && echo "ok   a non-socket entry is left alone" || { echo "FAIL the sweep touched a non-socket"; bad=1; }
case "$out" in *"removed 1"*) echo "ok   it says how many it removed" ;; *) echo "FAIL it prints the count: $out"; bad=1 ;; esac

tmux -S "$live" kill-server 2>/dev/null
exit "$bad"
