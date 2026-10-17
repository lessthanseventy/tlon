# Sourced by the machine-wide scripts (checks-queue.sh, release-smoke.sh) as `refuse_stale_script "$0"`.
#
# These scripts act on state every checkout shares (the checks queue, the smokes' builds and
# databases), and a coworker's worktree on an old base runs its own old copy of them: a sweep that
# deleted other smokes' live builds was one. A copy that origin/main has changed since this checkout
# branched is refused, exit 2, naming the rebase; the checkout's own edits to it don't count.
# TLON_STALE_SCRIPTS_OK=1 runs it anyway. A checkout old enough to lack this check runs its old
# copy unchecked: only a rebase fixes that one.
refuse_stale_script() {
  [ -z "${TLON_STALE_SCRIPTS_OK:-}" ] || return 0
  local dir name base
  dir="$(cd "$(dirname "$1")" && pwd)" name="$(basename "$1")"
  base="$(git -C "$dir" merge-base HEAD origin/main 2>/dev/null)" || return 0
  git -C "$dir" diff --quiet "$base" origin/main -- "$name" && return 0
  echo "$name: this checkout's copy is behind origin/main's (main changed it since this branch was cut): rebase onto origin/main, or TLON_STALE_SCRIPTS_OK=1 to run it anyway" >&2
  exit 2
}
