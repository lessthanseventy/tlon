#!/usr/bin/env bash
# Counts the argv bwrap was started with and groups its mounts by source prefix, biggest first.
# Inside a sandboxed Bash call, /proc/1/cmdline is that argv (no shim); a file argument is the same
# NUL-separated shape. A seat's limit is 9000 (#522).
# `record [FILE]` also appends "<ts> <count> wt=<registered worktrees>" to $BWRAP_ARGC_DIR/count.log
# (default $TMPDIR/bwrap-argc) and snapshots the path args whenever they change; `diff` prints the
# paths added (+) and dropped (-) between the first and last snapshots.
set -euo pipefail
dir=${BWRAP_ARGC_DIR:-${TMPDIR:-/tmp}/bwrap-argc}
mode=report
case ${1:-} in
  record) mode=record; shift ;;
  diff)
    snaps=("$dir"/argv.*)
    { diff "${snaps[0]}" "${snaps[${#snaps[@]}-1]}" || true; } | sed -n 's/^> /+/p; s/^< /-/p'
    exit 0 ;;
esac
f=${1:-/proc/1/cmdline}
total=$(tr -cd '\000' <"$f" | wc -c)
if [ "$mode" = record ]; then
  mkdir -p "$dir"
  wt=$(ls "$(git rev-parse --git-common-dir 2>/dev/null)/worktrees" 2>/dev/null | wc -l || true)
  echo "$(date +%s) $total wt=$wt" >>"$dir/count.log"
  # Only bwrap's own path args: nothing after the `--` (the command) and never a --setenv value,
  # which can carry the proxy credential.
  tr '\n\000' '\001\n' <"$f" | awk '
    $0 == "--" { exit }
    /^--/ { opt = $0; next }
    opt == "--setenv" { next }
    /^\// { print }' | sort >"$dir/now"
  last=$(ls "$dir"/argv.* 2>/dev/null | sort | tail -1 || true)
  if [ -z "$last" ] || ! cmp -s "$dir/now" "$last"; then cp "$dir/now" "$dir/argv.$(date +%s%N)"; fi
fi
# NUL ends an arg and becomes the record separator; a newline inside an arg becomes \001 so it stays one record.
tr '\n\000' '\001\n' <"$f" | awk -v total="$total" '
  /^--/ { opt = $0; k = 0; next }
  { k++ }
  k == 1 && opt ~ /^--(ro-bind|bind|tmpfs)$/ {
    p = $0
    if (p ~ /\/worktrees\//) p = substr(p, 1, index(p, "/worktrees/") + 9)
    else if (p != "/dev/null") { split(p, c, "/"); p = "/" c[2] "/" c[3] "/" c[4] "/" c[5] }
    g[p]++
  }
  END { print "total " total; for (p in g) print g[p], p }' | { read -r first; echo "$first"; sort -rn; }
