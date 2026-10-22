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
echo "bwrap-argc: ok"
