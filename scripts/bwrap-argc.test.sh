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
echo "bwrap-argc: ok"
