#!/usr/bin/env bash
# The gate on origin/main, in a throwaway worktree with its own test database: main's health measured
# on main, never on whatever this checkout has checked out. The nightly schedule runs it.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git -C "$root" fetch -q origin main || { echo "check-main: fetch failed"; exit 1; }
dir="$(mktemp -d -t tlon-main-XXXXXX)"
trap 'git -C "$root" worktree remove --force "$dir" >/dev/null 2>&1; rm -rf "$dir"' EXIT
git -C "$root" worktree add -q --detach "$dir" origin/main || exit 1
cd "$dir" || exit 1
echo "check-main: origin/main @ $(git log -1 --format='%h %s')"
export MISE_YES=1 TLON_TEST_DATABASE=tlon_test_main
mise trust -q "$dir" >/dev/null 2>&1
(cd server && mix deps.get >/dev/null) || { echo "check-main: mix deps.get failed"; exit 1; }
log="$(mktemp -t tlon-main-check-XXXXXX)"
mise run check >"$log" 2>&1
code=$?
# the verdict: every suite's counts, and on a red gate where it broke
grep -E "(pass|fail)$|Result:|ERROR|check-names:|passed ·" "$log"
if [ "$code" -ne 0 ]; then
  # each failing test's block (name, file:line, assertion); the log's end when there is none
  fails="$(grep -E -A14 "^\[[a-z:]+\] +[0-9]+\) test" "$log" | grep -vE "\] *$|\[debug\]")"
  if [ -n "$fails" ]; then echo "--- failures:"; echo "$fails"; else echo "--- the end of the log:"; tail -n 30 "$log"; fi
fi
rm -f "$log"
exit "$code"
