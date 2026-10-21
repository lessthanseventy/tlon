#!/usr/bin/env bash
# Counts the argv bwrap was started with and groups its mounts by source prefix, biggest first.
# Inside a sandboxed Bash call, /proc/1/cmdline is that argv (no shim); a file argument is the same
# NUL-separated shape. A seat's limit is 9000 (#522).
set -euo pipefail
f=${1:-/proc/1/cmdline}
total=$(tr -cd "\0" <"$f" | wc -c)
gawk -v RS='\0' -v total="$total" '
  /^--/ { opt = $0; k = 0; next }
  { k++ }
  k == 1 && opt ~ /^--(ro-bind|bind|tmpfs)$/ {
    p = $0
    if (p ~ /\/worktrees\//) p = substr(p, 1, index(p, "/worktrees/") + 9)
    else if (p != "/dev/null") { split(p, c, "/"); p = "/" c[2] "/" c[3] "/" c[4] "/" c[5] }
    g[p]++
  }
  END { print "total " total; for (p in g) print g[p], p }' "$f" | { read -r first; echo "$first"; sort -rn; }
