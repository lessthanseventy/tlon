#!/usr/bin/env bash
# Self-test of release.sh's pointer cut: only a fast-forward onto a commit on origin/main, a rollback
# only when asked, the pointer pushed, and a cut that changes nothing the server runs restarts
# nothing. Runs a copy of the real script in a private clone against a private origin, with a fake
# release build (so no mix) and a fake curl.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
. "$here/lib/test.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset TLON_THREAD

g() { git -C "$tmp/repo" "$@"; }
commit() { echo "$2" >"$tmp/repo/$1" && g add "$1" && g commit -qm "$3"; }

git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
mkdir "$tmp/repo/scripts"
cp "$here/release.sh" "$here/git-fetch-origin.sh" "$tmp/repo/scripts/"
commit mise.toml 'x' "base"
c1="$(g rev-parse HEAD)"
commit notes.txt a "docs only"
c2="$(g rev-parse HEAD)"
commit notes.txt b "docs again"
c3="$(g rev-parse HEAD)"
g push -q origin HEAD:main
g reset -q --hard "$c1"
commit local.txt z "never pushed"
local_only="$(g rev-parse HEAD)"
g branch -q live "$c1"
g fetch -q origin

# the running release: a checkout with a server binary, so a docs-only cut needs no build
export TLON_RELEASE_DIR="$tmp/rel"
g worktree add -q --detach "$TLON_RELEASE_DIR" "$c1"
mkdir -p "$TLON_RELEASE_DIR/server/_build/prod/rel/server/bin"
printf '#!/bin/sh\n' >"$TLON_RELEASE_DIR/server/_build/prod/rel/server/bin/server"
chmod +x "$TLON_RELEASE_DIR/server/_build/prod/rel/server/bin/server"

mkdir "$tmp/bin"
printf '#!/bin/sh\necho "$@" >>"%s/curl"\necho "{\\"live\\":true}"\n' "$tmp" >"$tmp/bin/curl"
printf '#!/bin/sh\necho "gate ok"\n' >"$tmp/cli"
chmod +x "$tmp/bin/curl" "$tmp/cli"
export PATH="$tmp/bin:$PATH" TLON_CLI="$tmp/cli" TLON_URL=http://svc:1
rel() { "$tmp/repo/scripts/release.sh" "$@" 2>&1; }
live() { g rev-parse live; }
pushed() { git -C "$tmp/origin.git" rev-parse -q --verify refs/heads/live; }

out="$(rel cut "$local_only")"; code=$?
expect "a commit not on origin/main is refused" "$code" "1"
expect "  and says why" "$(echo "$out" | grep -c 'not on origin/main')" "1"
expect "  and the pointer stays" "$(live)" "$c1"

out="$(rel cut "$c2" --no-restart)"; code=$?
expect "a fast-forward onto main's commit is cut" "$code:$(live)" "0:$c2"
expect "  and pushed to origin" "$(pushed)" "$c2"
expect "  and .release is checked out at it" "$(git -C "$TLON_RELEASE_DIR" rev-parse HEAD)" "$c2"
expect "  and a cut that changes nothing the server runs says so" "$(echo "$out" | grep -c 'restart: not needed')" "1"
expect "  and with --no-restart asks the server nothing" "$(cat "$tmp/curl" 2>/dev/null | wc -l)" "0"

out="$(rel cut "$c1")"; code=$?
expect "going back without --rollback is refused" "$code:$(live)" "1:$c2"
expect "  and says it is a rollback" "$(echo "$out" | grep -c 'a rollback is --rollback')" "1"

out="$(rel cut "$c3")"; code=$?
expect "the next cut tells the server of it" "$code:$(live)" "0:$c3"
expect "  and the server is asked at /api/live" "$(grep -c 'http://svc:1/api/live' "$tmp/curl")" "1"

out="$(rel cut "$c1" --rollback --no-restart)"; code=$?
expect "--rollback goes back" "$code:$(live)" "0:$c1"
expect "  and force-pushes the pointer" "$(pushed)" "$c1"

out="$(rel status)"
expect "status names the release and what main has that it lacks" "$(echo "$out" | grep -c '^on main, not released (2):')" "1"
expect "  and reads the server's checks" "$(echo "$out" | grep -c '^  gate ok')" "1"

rel nonsense >/dev/null; expect "an unknown command is a usage error" "$?" "2"

exit "$bad"
