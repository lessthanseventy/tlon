#!/usr/bin/env bash
# Scratch worktrees: detached checkouts outside the repo (~/.cache/tlon-scratch/<name>) where a
# session builds and gates a change without touching the live checkout. Detached, so nothing
# writes .git/config: a branch is published with `git push origin HEAD:refs/heads/<branch>`.
#
#   scripts/scratch.sh new <name> [<ref>]   worktree at <ref> (default: origin/main, fetched),
#                                           with what the gates and menard need installed
#   scripts/scratch.sh prune [--dry-run]    remove the ones whose work is done; say what stays
#
# TLON_SCRATCH_DIR moves the directory (default ${XDG_CACHE_HOME:-~/.cache}/tlon-scratch).
#
# Its work is done when the worktree is clean and every commit it has beyond origin/main is on
# origin/main by patch: a PR lands by rebase-merge, which rewrites SHAs, so ancestry never
# matches and `git cherry` (patch-id) is the test. Kept: uncommitted or untracked changes, a
# commit main doesn't have, a process working in it, or one touched within the hour (a session
# that just made it hasn't committed yet).
set -uo pipefail

base="${TLON_SCRATCH_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tlon-scratch}"
common="$(git rev-parse --path-format=absolute --git-common-dir)" || exit 1
fail() { echo "scratch: $*" >&2; exit 1; }

new() {
  local name="${1:-}" ref="${2:-origin/main}"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "usage: scratch.sh new <name> [<ref>] (name: letters, digits, . _ -)"
  local dir="$base/$name"
  [ -e "$dir" ] && fail "$dir exists — pick another name, or prune"
  mkdir -p "$base"
  git fetch -q origin || fail "git fetch origin failed"
  git worktree add -q --detach "$dir" "$ref" || fail "git worktree add $dir $ref failed"
  local log
  log="$(mktemp)"
  trap 'rm -f "$log"' RETURN
  install() { # dir, what, cmd…
    local d="$1" what="$2"; shift 2
    [ -d "$d" ] || return 0
    (cd "$d" && "$@") >"$log" 2>&1 || { tail -n 20 "$log" >&2; fail "$what failed in $d"; }
  }
  install "$dir/server" "mix deps.get" mix deps.get
  # menard formats with the plugins from the host's last build, which a fresh worktree has none of
  install "$dir/server" "formatter plugins" mix deps.compile credo quokka doctest_formatter
  install "$dir/office" "bun install" bun install --frozen-lockfile
  local pkg
  for pkg in "$dir"/adapters/*/package.json; do
    [ -f "$pkg" ] && install "$(dirname "$pkg")" "bun install" bun install --frozen-lockfile
  done
  echo "$dir"
}

# why a worktree stays, or "" when its work is done
held() {
  local dir="$1" gitdir now touched pid
  gitdir="$(git -C "$dir" rev-parse --path-format=absolute --git-dir)"
  now="$(date +%s)"
  touched="$(stat -c %Y "$gitdir/HEAD" "$gitdir/index" 2>/dev/null | sort -n | tail -n 1)"
  local dirty cherry
  # no optional locks: a status that refreshes the index would make it look touched just now
  dirty="$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" status --porcelain 2>&1)" || { echo "git status failed"; return; }
  [ -n "$dirty" ] && { echo "uncommitted changes"; return; }
  cherry="$(git -C "$dir" cherry origin/main HEAD 2>&1)" || { echo "git cherry failed"; return; }
  [ "$(grep -c '^+' <<<"$cherry")" -gt 0 ] && { echo "$(grep -c '^+' <<<"$cherry") commit(s) not on origin/main"; return; }
  for pid in /proc/[0-9]*; do
    case "$(readlink "$pid/cwd" 2>/dev/null)" in "$dir" | "$dir"/*) echo "in use by pid ${pid#/proc/}"; return ;; esac
  done
  [ $((now - ${touched:-0})) -lt 3600 ] && { echo "touched within the hour"; return; }
  echo ""
}

prune() {
  local dry=""
  [ "${1:-}" = "--dry-run" ] && dry=1
  [ -d "$base" ] || { echo "nothing in $base"; return 0; }
  git fetch -q origin || fail "git fetch origin failed"
  local dir why
  for dir in "$base"/*/; do
    dir="${dir%/}"
    if [ "$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" != "$common" ] ||
      [ "$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" != "$dir" ]; then
      echo "skip   $dir — not a worktree of this repo"
      continue
    fi
    why="$(held "$dir")"
    if [ -n "$why" ]; then
      echo "keep   $dir — $why"
    elif [ -n "$dry" ]; then
      echo "would remove $dir"
    elif out="$(git worktree remove "$dir" 2>&1)"; then
      echo "remove $dir"
    else
      echo "keep   $dir — git refused: ${out%%$'\n'*}"
    fi
  done
  [ -n "$dry" ] || git worktree prune
}

cmd="${1:-}"
shift || true
case "$cmd" in
  new) new "$@" ;;
  prune) prune "$@" ;;
  *) fail "usage: scratch.sh new <name> [<ref>] | prune [--dry-run]" ;;
esac
