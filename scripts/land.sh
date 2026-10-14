#!/usr/bin/env bash
# Land a reviewed PR: hand it to the server's merge queue (Server.Jobs.Land, the same line and gate as
# worklines — Server.PRLanding), which takes it only when its branch's review on tlon approves its
# head (a review by neither the PR's author nor a builder of it), then rebases it onto origin/main,
# gates it, posts tlon/check and merges at exactly that head.
# Here: GitHub says what the PR is, and a PR from main, a fork, a protected branch, one closed or one
# not onto main is refused before it is queued. The service must be up.
#
#   scripts/land.sh <pr-number>
set -uo pipefail

pr="${1:-}"
case "$pr" in '' | *[!0-9]*) echo "usage: land.sh <pr-number>" >&2; exit 2 ;; esac
cli="${TLON_CLI:-$(dirname "$0")/tlon-cli.sh}"
stop() { echo "land #$pr: $*" >&2; exit 1; }

read -r head base state cross author <<<"$(gh pr view "$pr" --json headRefName,baseRefName,state,isCrossRepository,author \
  --template '{{.headRefName}} {{.baseRefName}} {{.state}} {{.isCrossRepository}} {{.author.login}}' 2>/dev/null)"
[ -n "${head:-}" ] || stop "gh could not read the PR"
[ "$state" = OPEN ] || stop "it is $state, not open"
[ "$base" = main ] || stop "it targets $base, not main"
[ "$cross" = false ] || stop "its branch is on a fork — the merge queue can't push it"
[ "$head" != main ] || stop "its branch is main — refused"
[ "$(gh api "repos/{owner}/{repo}/branches/$head" --template '{{.protected}}' 2>/dev/null)" != true ] ||
  stop "its branch $head is protected — refused"
exec "$cli" land-pr "$pr" "$head" "${author:-}"
