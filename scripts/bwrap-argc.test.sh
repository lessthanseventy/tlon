#!/usr/bin/env bash
# bwrap-argc.sh counts a bwrap argv (a NUL-separated file) and groups its mounts.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'bwrap\0--setenv\0A\0B\0--ro-bind\0/x/.git/worktrees/a\0/x/.git/worktrees/a\0--ro-bind\0/x/.git/worktrees/b\0/x/.git/worktrees/b\0--ro-bind\0/dev/null\0/y/.bashrc\0--\0zsh\0' >"$tmp/argv"
out=$("$here/bwrap-argc.sh" "$tmp/argv")
grep -qx 'total 15' <<<"$out" || { echo "FAIL total: $out"; exit 1; }
grep -qx '2 /x/.git/worktrees' <<<"$out" || { echo "FAIL group worktrees: $out"; exit 1; }
grep -qx '1 /dev/null' <<<"$out" || { echo "FAIL group devnull: $out"; exit 1; }
# A multi-line arg (a seat's command string) whose line reads like a mount option is one arg, not a mount.
printf 'bwrap\0--ro-bind\0/dev/null\0/y/.bashrc\0--\0zsh\0-c\0echo\n--ro-bind\n/z/a/b/c/d\n\0' >"$tmp/multi"
out=$("$here/bwrap-argc.sh" "$tmp/multi")
grep -qx 'total 8' <<<"$out" || { echo "FAIL multi total: $out"; exit 1; }
! grep -q '/z/' <<<"$out" || { echo "FAIL multi-line arg grouped as a mount: $out"; exit 1; }
# It needs no gawk: a gawk that always fails must not matter.
mkdir "$tmp/bin"; printf '#!/bin/sh\nexit 99\n' >"$tmp/bin/gawk"; chmod +x "$tmp/bin/gawk"
out=$(PATH="$tmp/bin:$PATH" "$here/bwrap-argc.sh" "$tmp/multi") || { echo "FAIL depends on gawk"; exit 1; }
grep -qx 'total 8' <<<"$out" || { echo "FAIL no-gawk total: $out"; exit 1; }
# record appends "<ts> <count> wt=<n>" and snapshots the path args when they change; diff names what was added.
export BWRAP_ARGC_DIR="$tmp/rec"
printf 'bwrap\0--setenv\0GIT_X\0/http://u:pw@h:3128\0--ro-bind\0/home/a\0/home/a\0--\0/bin/zsh\0-c\0/z/cmd\n/z/more\0' >"$tmp/r1"
"$here/bwrap-argc.sh" record "$tmp/r1" >/dev/null
grep -Eqx '[0-9]+ 11 wt=[0-9]+' "$BWRAP_ARGC_DIR/count.log" || { echo "FAIL record line: $(cat "$BWRAP_ARGC_DIR/count.log")"; exit 1; }
snap=$(cat "$BWRAP_ARGC_DIR"/argv.*)
[ "$snap" = $'/home/a\n/home/a' ] || { echo "FAIL snapshot keeps mount paths only: $snap"; exit 1; }
! grep -rq 'pw@h' "$BWRAP_ARGC_DIR" || { echo "FAIL an env value was recorded"; exit 1; }
"$here/bwrap-argc.sh" record "$tmp/r1" >/dev/null
[ "$(ls "$BWRAP_ARGC_DIR"/argv.* | wc -l)" -eq 1 ] || { echo "FAIL unchanged paths snapshot again"; exit 1; }
[ "$(wc -l <"$BWRAP_ARGC_DIR/count.log")" -eq 2 ] || { echo "FAIL every record appends a line"; exit 1; }
printf 'bwrap\0--ro-bind\0/home/a\0/home/a\0--tmpfs\0/tmp/x1\0--\0zsh\0' >"$tmp/r2"
"$here/bwrap-argc.sh" record "$tmp/r2" >/dev/null
[ "$(ls "$BWRAP_ARGC_DIR"/argv.* | wc -l)" -eq 2 ] || { echo "FAIL changed paths take a new snapshot"; exit 1; }
out=$("$here/bwrap-argc.sh" diff)
[ "$out" = '+/tmp/x1' ] || { echo "FAIL diff names only the added path: $out"; exit 1; }
echo "bwrap-argc: ok"
