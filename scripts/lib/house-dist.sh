# Shared by house-art-pack.sh and house-build.sh: where the house's builds and art pack go.
# The art is bought and its licence forbids redistributing it, and this repo is public, so the
# output dir must lie outside every git work tree: refused when it does not.
# shellcheck shell=bash
art="${TLON_ART_DIR:-$HOME/projects/thatch/packs/x}"
dist="${TLON_HOUSE_DIST:-$HOME/.cache/tlon/house-dist}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

dist_outside_git() {
  local d="$dist"
  while [ ! -d "$d" ]; do d="$(dirname "$d")"; done
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "house: $dist is inside a git work tree; the art and the builds never go in a repo (TLON_HOUSE_DIST)" >&2
    return 1
  fi
}
