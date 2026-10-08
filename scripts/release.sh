#!/usr/bin/env bash
# The release pointer (pm-and-release design §3): `refs/heads/live` is what the always-up service
# runs, built in the `.release` checkout beside the main one. Merging to main no longer deploys;
# moving this pointer does.
#
#   release.sh cut [<commit>] [--rollback] [--no-restart]
#                                            move live to <commit> (default origin/main): only a
#                                            fast-forward, only onto a commit on origin/main;
#                                            --rollback allows going back to an older one;
#                                            --no-restart leaves the restart to the caller (the PM's
#                                            cut posts its changelog first, then restarts)
#   release.sh status                        what runs, what main has that it doesn't, and
#                                            whether main is releasable (the server's checks)
#   release.sh build                         build .release at the current release (server:release;
#                                            a first install starts the pointer at origin/main)
#
# The ref is `live`, not `release`: branches named release/* (here and on GitHub) rule a bare
# `release` branch out. A cut moves the ref, pushes it, checks .release out at it, builds the release there, and asks
# the running server for a quiet restart (it drains first); a server that can't be asked is
# restarted outright — down is what needs it. Plain git and the server's own door, so it works at
# 2am with the service down.
set -uo pipefail

root="$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
rel="${TLON_RELEASE_DIR:-$root/.release}"
url="${TLON_URL:-http://127.0.0.1:4040}"
cli="${TLON_CLI:-$root/scripts/tlon-cli.sh}"
git() { command git -C "$root" "$@"; }

# .release checked out at $1 and its release built
build_at() {
  if [ -e "$rel/.git" ]; then command git -C "$rel" checkout -q --detach "$1" || return 1
  else git worktree add -q --detach "$rel" "$1" || return 1; fi
  # the main checkout's installed deps where there are none: a cut never refetches the world
  if [ ! -d "$rel/server/deps" ] && [ -d "$root/server/deps" ]; then cp -a --reflink=auto "$root/server/deps" "$rel/server/"; fi
  (cd "$rel/server" && MIX_ENV=prod mix release --overwrite >/dev/null) || { echo "release: the build failed in $rel" >&2; return 1; }
}

cmd="${1:-status}"; shift || true

case "$cmd" in
  status)
    git fetch -q origin 2>/dev/null
    cur="$(git rev-parse -q --verify refs/heads/live)" || { echo "no release cut yet — mise run release:cut"; exit 0; }
    main="$(git rev-parse origin/main)"
    echo "release   $(git log -1 --format='%h %s' "$cur")"
    echo "main      $(git log -1 --format='%h %s' "$main")"
    waiting="$(git log --format='  %h %s' "$cur..$main")"
    if [ -z "$waiting" ]; then echo "nothing on main waits for a release"; else
      echo "on main, not released ($(printf '%s\n' "$waiting" | wc -l)):"; printf '%s\n' "$waiting"; fi
    echo "checks on main ${main:0:7}:"
    "$cli" releasable "$main" 2>/dev/null | sed 's/^/  /'
    [ "${PIPESTATUS[0]}" -eq 0 ] || echo "  the server didn't answer — no checks to read"
    ;;

  cut)
    target="" rollback="" restart=1
    for a in "$@"; do case "$a" in --rollback) rollback=1 ;; --no-restart) restart="" ;; *) target="$a" ;; esac; done
    git fetch -q origin || { echo "release: can't fetch origin" >&2; exit 1; }
    to="$(git rev-parse -q --verify "${target:-origin/main}^{commit}")" || { echo "release: no commit ${target}" >&2; exit 1; }
    git merge-base --is-ancestor "$to" origin/main ||
      { echo "release refused: ${to:0:7} is not on origin/main — only merged work ships" >&2; exit 1; }
    from="$(git rev-parse -q --verify refs/heads/live)"
    if [ -n "$from" ] && [ -z "$rollback" ] && ! git merge-base --is-ancestor "$from" "$to"; then
      echo "release refused: ${to:0:7} is behind or beside the current release ${from:0:7} — a rollback is --rollback" >&2
      exit 1
    fi

    git branch -f live "$to" || exit 1
    git push -q ${rollback:+--force} origin live 2>/dev/null || echo "release: moved here; the push to origin failed (pushed next cut)" >&2

    build_at "$to" || exit 1

    echo "release → ${to:0:7}${from:+ (from ${from:0:7})}"
    [ -n "$from" ] && git log --format='  %h %s' "$from..$to"

    [ -n "$restart" ] || exit 0
    if answer="$(curl -s -m 5 -X POST -H 'content-type: application/json' -d '{}' "$url/api/restart")" && [ -n "$answer" ]; then
      echo "restart: $answer"
    else
      echo "restart: the server didn't answer — restarting it now"
      TLON_RESTART_WHY="release ${to:0:7}" "$root/scripts/server-restart.sh" --force
    fi
    ;;

  build)
    cur="$(git rev-parse -q --verify refs/heads/live)" || {
      git fetch -q origin 2>/dev/null
      cur="$(git rev-parse origin/main)" && git branch -f live "$cur"
    }
    build_at "$cur"
    ;;

  *)
    echo "usage: release.sh cut [<commit>] [--rollback] [--no-restart] | status | build" >&2
    exit 2
    ;;
esac
