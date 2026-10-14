#!/usr/bin/env bash
# `mise run check`'s body, inside its checks-queue slot: check:all, then the verdict posted to GitHub
# as the commit status `tlon/check` on HEAD — the check main's branch protection requires, so the
# local gate is what lets a PR merge.
#
# It vouches only for a commit it tested: the tree clean (`git status --porcelain` empty) and HEAD
# the same before and after the run, else nothing is posted and it says why. gh missing or refusing
# (unauthenticated, offline, a sha GitHub doesn't have) is said, never a red gate; the exit is the
# gate's. TLON_CHECK_STATUS=0 posts nothing.
set -uo pipefail

state() { printf '%s\n%s' "$(git rev-parse HEAD 2>/dev/null)" "$(git status --porcelain 2>/dev/null)"; }
before="$(state)"
mise run check:all
code=$?

sha="$(git rev-parse HEAD 2>/dev/null)"
say() { echo "tlon/check: $*"; }
if [ "${TLON_CHECK_STATUS:-1}" = "0" ]; then
  say "not posted (TLON_CHECK_STATUS=0)"
elif [ -z "$sha" ]; then
  say "not posted — not in a git checkout"
elif [ "$before" != "$sha" ] || [ "$(state)" != "$before" ]; then
  say "not posted — the tree has uncommitted or untracked changes, or HEAD moved during the run: it vouches only for a commit it tested"
elif ! command -v gh >/dev/null 2>&1; then
  say "not posted — gh is not installed"
else
  verdict=success; [ "$code" -eq 0 ] || verdict=failure
  if err="$(gh api "repos/{owner}/{repo}/statuses/$sha" -f state="$verdict" -f context=tlon/check \
    -f description="mise run check on $(hostname)" 2>&1 >/dev/null)"; then
    say "$verdict posted for ${sha:0:12}"
  else
    say "not posted — gh: $(printf '%s' "$err" | head -n 1)"
  fi
fi
exit "$code"
