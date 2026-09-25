#!/usr/bin/env bash
# `mise run menard -- VERB …`: menard at the version the server's mix.lock pins — the same version
# the coworkers' source tools run as a library — from a checkout of its own under ~/.cache.
#
# Not the live ~/projects/menard: that is where menard is developed, and a half-applied edit
# there stopped every other session's verbs mid-task. Not server/deps/menard either: the
# CLI has to keep working while the server's deps do not resolve.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# A hex pin checks out its release tag; a git pin its commit.
version=$(grep -oE '"menard": \{:hex, :menard, "[^"]+"' "$repo/server/mix.lock" | grep -oE '"[0-9][^"]*"$' | tr -d '"' || true)
sha=${version:+v$version}
sha=${sha:-$(grep -oE '"menard": \{:git, "[^"]+", "[0-9a-f]{40}"' "$repo/server/mix.lock" | grep -oE '[0-9a-f]{40}' || true)}
[[ -n "$sha" ]] || { echo "menard.sh: no menard pin in server/mix.lock" >&2; exit 2; }

dir="${XDG_CACHE_HOME:-$HOME/.cache}/ficciones/menard/$sha"
if [[ ! -x "$dir/bin/menard" ]]; then
  # the local checkout when it has the commit (fast, offline), else GitHub
  src="https://github.com/lessthanseventy/menard.git"
  git -C "$HOME/projects/menard" cat-file -e "$sha^{commit}" 2>/dev/null && src="$HOME/projects/menard"
  rm -rf "$dir.tmp"
  git clone -q "$src" "$dir.tmp" >&2
  git -C "$dir.tmp" checkout -q "$sha"
  mv "$dir.tmp" "$dir"
fi
# each pin carries its own deps and build; one no call has used in two weeks is not coming back
touch "$dir"
find "$(dirname "$dir")" -mindepth 1 -maxdepth 1 -type d -mtime +14 ! -path "$dir" -exec rm -rf {} + 2>/dev/null || true

# the caller's directory, which every relative path resolves against
export MENARD_CWD="${MISE_ORIGINAL_CWD:-$PWD}"
exec "$dir/bin/menard" "$@"
