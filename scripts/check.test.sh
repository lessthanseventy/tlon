#!/usr/bin/env bash
# Self-test of check.sh's rules: a tree that already passed is not gated again (work/ and docs/ left
# out of the key), only a green is recorded, FORCE runs anyway, and tlon/check is posted only for a
# clean tree. Runs a copy of the real script in a private repo with a fake `mise` and a fake `gh`.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
. "$here/lib/test.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export XDG_CACHE_HOME="$tmp/cache"
unset TLON_CHECK_FORCE TLON_CHECK_STATUS

repo="$tmp/repo"
git init -q -b main "$repo"
mkdir "$repo/scripts" "$repo/docs" "$repo/work"
cp "$here/check.sh" "$repo/scripts/"
g() { git -C "$repo" "$@"; }
commit() { echo "$2" >"$repo/$1" && g add "$1" && g commit -qm "$3"; }
commit app.txt one "app"; g add scripts; g commit -qm "the script"

mkdir "$tmp/bin"
printf '#!/bin/sh\necho "$@" >>"%s/mise"\nexit "$(cat "%s/gate" 2>/dev/null || echo 0)"\n' "$tmp" "$tmp" >"$tmp/bin/mise"
printf '#!/bin/sh\necho "$@" >>"%s/gh"\n' "$tmp" >"$tmp/bin/gh"
chmod +x "$tmp/bin/mise" "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
runs() { { cat "$tmp/mise" 2>/dev/null || true; } | grep -c 'run check:all'; }
posts() { { cat "$tmp/gh" 2>/dev/null || true; } | grep -c 'statuses/'; }
check() { (cd "$repo" && scripts/check.sh 2>&1); }

export TLON_CHECK_STATUS=0
out="$(check)"; code=$?
expect "a clean tree is gated" "$code:$(runs)" "0:1"
expect "  and its green is recorded" "$(ls "$tmp/cache/tlon-verify/green" | wc -l)" "1"
check >/dev/null
expect "the same tree is not gated again" "$(runs)" "1"
commit docs/plan.md x "a plan"; commit work/slug.md y "a workline file"
out="$(check)"
expect "a commit touching only docs/ and work/ is the same tree" "$(runs)" "1"
expect "  and says so" "$(echo "$out" | grep -c 'already passed')" "1"
commit docs/glossary.md g "the glossary, which a check opens"
check >/dev/null
expect "docs/glossary.md is part of the key" "$(runs)" "2"
commit app.txt two "app, changed"
echo 1 >"$tmp/gate"
out="$(check)"; code=$?
expect "a failing gate fails the check" "$code:$(runs)" "1:3"
expect "  and records no green" "$(ls "$tmp/cache/tlon-verify/green" | wc -l)" "2"
check >/dev/null
expect "  so the next ask runs it again" "$(runs)" "4"
rm "$tmp/gate"

TLON_CHECK_FORCE=1 check >/dev/null
expect "FORCE runs a passed tree" "$(runs)" "5"
check >/dev/null
expect "  and the green it records serves the next ask" "$(runs)" "5"
echo dirt >"$repo/untracked.txt"
check >/dev/null
expect "a dirty tree is gated, not served from the cache" "$(runs)" "6"
rm "$repo/untracked.txt"

unset TLON_CHECK_STATUS
commit app.txt three "app, changed again"
sha="$(g rev-parse HEAD)"
out="$(check)"
expect "a clean pass posts success on HEAD" "$(grep -c "statuses/$sha -f state=success -f context=tlon/check" "$tmp/gh")" "1"
echo 1 >"$tmp/gate"
commit app.txt four "app, changed once more"
sha="$(g rev-parse HEAD)"
check >/dev/null
expect "a failure posts failure on HEAD" "$(grep -c "statuses/$sha -f state=failure" "$tmp/gh")" "1"
before="$(posts)"
echo dirt >"$repo/untracked.txt"
out="$(check)"
expect "a dirty tree posts nothing and says why" "$(posts):$(echo "$out" | grep -c 'uncommitted or untracked')" "$before:1"

exit "$bad"
