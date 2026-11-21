#!/usr/bin/env bash
# Self-test of house-gate.sh: --if-changed runs only when house/ changed in the gated commits (or
# there is no range: main itself), a missing godot is a named skip or red with TLON_HOUSE_GATE=required,
# and the sections run in parallel with each one's verdict, FAIL lines and timeout reported and no
# godot left behind. A private repo, a fake `godot` and a fake `mise`.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
. "$here/lib/test.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset TLON_HOUSE_GATE TLON_GATE_NOTES TLON_HOUSE_JOBS TLON_HOUSE_BOUND

repo="$tmp/repo"
git init -q -b main "$repo"
mkdir "$repo/scripts" "$repo/house" "$repo/office"
cp "$here/house-gate.sh" "$repo/scripts/"
g() { git -C "$repo" "$@"; }
commit() { echo "$2" >"$repo/$1" && g add "$1" && g commit -qm "$3"; }
commit house/a.gd one "house"
g update-ref refs/remotes/origin/main HEAD
g switch -q -c work

gate() { (cd "$repo" && scripts/house-gate.sh "$@" 2>&1); }

mkdir "$tmp/bare" "$tmp/bin"
for t in env bash git dirname nproc cat rm; do ln -s "$(command -v "$t")" "$tmp/bare/$t"; done
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/mise"
cat >"$tmp/bin/godot" <<'GODOT'
#!/bin/sh
case " $* " in
*" --list "*) printf 'Godot Engine v4\nalpha\nbeta\ngamma\nSOAK LIST (3 sections)\n'; exit 0 ;;
esac
for a; do n="$a"; done
echo "$n" >>"$FAKE_STARTED"
case "$n:$FAKE_MODE" in
beta:fail) echo "FAIL: beta check broke"; echo "SOAK FAILED (1 failures)"; exit 1 ;;
beta:hang) exec sleep 301 ;;
beta:error) echo "ERROR: engine"; echo "SOAK OK (0 failures)"; exit 0 ;;
esac
sleep 1
echo "SOAK OK (0 failures)"
GODOT
chmod +x "$tmp/bin/mise" "$tmp/bin/godot"
export FAKE_STARTED="$tmp/started" FAKE_MODE=ok

commit office/a.ts x "office only"
out="$(gate --if-changed)"; code=$?
expect "a range without house/ is not run" "$code:$(echo "$out" | grep -c 'house: unchanged, not run')" "0:1"
echo dirt >"$repo/house/dirty.gd"
out="$(PATH="$tmp/bare" gate --if-changed)"; code=$?
expect "an uncommitted house/ file counts" "$code:$(echo "$out" | grep -c 'house: SKIPPED')" "0:1"
rm "$repo/house/dirty.gd"

commit house/b.gd two "house again"
out="$(PATH="$tmp/bare" gate --if-changed)"; code=$?
expect "house/ changed, no godot: a named skip, exit 0" "$code:$(echo "$out" | grep -c '^house: SKIPPED — godot not on PATH (set TLON_HOUSE_GATE=required to make this red)$')" "0:1"
out="$(TLON_HOUSE_GATE=required PATH="$tmp/bare" gate --if-changed)"; code=$?
expect "  required: red with the message" "$code:$(echo "$out" | grep -c 'house: FAILED — godot is not on PATH')" "1:1"
notes="$tmp/notes"
PATH="$tmp/bare" TLON_GATE_NOTES="$notes" gate --if-changed >/dev/null
expect "  the skip is handed to the gate's summary" "$(grep -c SKIPPED "$notes")" "1"

g switch -q main
out="$(PATH="$tmp/bare" gate --if-changed)"
expect "on main, with no range, it is a full run" "$(echo "$out" | grep -c 'house: SKIPPED')" "1"
g switch -q work

out="$(PATH="$tmp/bin:$PATH" TLON_HOUSE_JOBS=2 gate)"; code=$?
expect "all sections ok: exit 0, one line each" "$code:$(echo "$out" | grep -c 'ok      SOAK OK')" "0:3"
expect "  and the verdict says how many ran" "$(echo "$out" | grep -c 'house: ok — 3 sections, 2 at once')" "1"

out="$(FAKE_MODE=fail PATH="$tmp/bin:$PATH" gate)"; code=$?
expect "a failing section fails the gate" "$code" "1"
expect "  and its FAIL line is named with the section" "$(echo "$out" | grep -c '^beta: FAIL: beta check broke')" "1"
out="$(FAKE_MODE=error PATH="$tmp/bin:$PATH" gate)"; code=$?
expect "an ERROR line before SOAK OK fails it" "$code:$(echo "$out" | grep -c '^beta: ERROR: engine')" "1:1"

: >"$tmp/started"
out="$(FAKE_MODE=hang TLON_HOUSE_BOUND=2 PATH="$tmp/bin:$PATH" gate)"; code=$?
expect "a hung section is killed at the bound and reported" "$code:$(echo "$out" | grep -c 'beta .*TIMEOUT')" "1:1"
sleep 0.5
expect "  and no process of the gate is left" "$(pgrep -fx "sleep 301" | wc -l)" "0"

exit "$bad"
