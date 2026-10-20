#!/usr/bin/env bash
# Self-test of scratch.sh prune: work landed by patch or by subject goes, work main lacks stays.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t TLON_SCRATCH_DIR="$tmp/scratch"
g() { git -C "$tmp/repo" "$@" >/dev/null 2>&1; }
commit() { # commit <dir> <file> <text> <subject>
  echo "$3" >"$1/$2" && git -C "$1" add "$2" && git -C "$1" commit -qm "$4" >/dev/null
}
git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
commit "$tmp/repo" a.txt base "an old subject"; g push -q origin HEAD:main; g fetch -q origin

scratch() { # scratch <name> <subject> <text>: a detached worktree with one commit, aged past the hour
  g worktree add -q --detach "$TLON_SCRATCH_DIR/$1" origin/main
  commit "$TLON_SCRATCH_DIR/$1" "$1.txt" "$3" "$2"
  local gd; gd="$(git -C "$TLON_SCRATCH_DIR/$1" rev-parse --path-format=absolute --git-dir)"
  touch -d '2 hours ago' "$gd/HEAD" "$gd/index"
}
scratch reformatted "add the reformatted thing" "draft wording"
scratch unlanded "a change main never got" "x"
scratch reused "an old subject" "y"
# main lands the first under the same subject with a different patch (a landing that resolved a conflict or reworded a line)
commit "$tmp/repo" reformatted.txt "final wording" "add the reformatted thing"; g push -q origin HEAD:main

(cd "$tmp/repo" && "$here/scratch.sh" prune) >"$tmp/out" 2>&1
expect() { # expect <removed|kept> <name> <why>
  local got=kept; [ -d "$TLON_SCRATCH_DIR/$2" ] || got=removed
  if [ "$got" = "$1" ]; then echo "ok   $3"; else echo "FAIL $3: $got"; cat "$tmp/out"; bad=1; fi
}
expect removed reformatted "landed under a new patch, same subject: removed"
expect kept unlanded "a commit main lacks: kept"
expect kept reused "a subject main had before it branched: kept"
grep -q "remove .*reformatted — its HEAD was [0-9a-f]" "$tmp/out" || { echo "FAIL the removal names its HEAD"; cat "$tmp/out"; bad=1; }
exit "$bad"
