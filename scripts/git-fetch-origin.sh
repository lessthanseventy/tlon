#!/usr/bin/env bash
# `git fetch origin [<branch>...]` in <repo>, over HTTPS when origin's SSH can't be used (a sandboxed
# seat is denied ~/.ssh): a GitHub SSH remote is read at https://github.com/ instead (the repos read
# publicly), its refs landing in refs/remotes/origin/ as origin's would. The remote config is never changed.
#
#   git-fetch-origin.sh <repo> [<branch>...]
set -uo pipefail
repo="${1:?usage: git-fetch-origin.sh <repo> [<branch>...]}"; shift

err="$(git -C "$repo" fetch -q origin "$@" 2>&1)" && exit 0
url="$(git -C "$repo" remote get-url origin)" || exit 1
case "$url" in
  git@github.com:*) https="https://github.com/${url#git@github.com:}" ;;
  ssh://git@github.com/*) https="https://github.com/${url#ssh://git@github.com/}" ;;
  *) printf '%s\n' "$err" >&2; exit 1 ;;
esac
specs=()
for b in "$@"; do specs+=("+refs/heads/$b:refs/remotes/origin/$b"); done
[ ${#specs[@]} -gt 0 ] || specs=("+refs/heads/*:refs/remotes/origin/*")
GIT_TERMINAL_PROMPT=0 git -C "$repo" fetch -q "$https" "${specs[@]}" && exit 0
printf 'origin over ssh: %s\n' "$err" >&2
exit 1
