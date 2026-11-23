#!/usr/bin/env bash
# Self-test of house-check.sh: a green run is quiet, and each way a step can fail prints the step's
# name, godot's exit code and the output. A fake `godot` on PATH.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
. "$here/lib/test.sh"

mkdir "$tmp/bin"
cat >"$tmp/bin/godot" <<'GODOT'
#!/bin/sh
case " $* " in
*" --quit "*) [ "$FAKE_MODE" = load-error ] && echo "SCRIPT ERROR: Parse Error: boom"; [ "$FAKE_MODE" = load-exit ] && exit 3; exit 0 ;;
*check-only*) exit 0 ;;
esac
case "$FAKE_MODE" in
logic-fail) echo "FAIL: done of a waiting-on returns 404"; echo "LOGIC FAILED (1 failures)"; exit 1 ;;
logic-crash) echo "partial output"; exit 139 ;;
logic-hang) echo "LOGIC > ChoreLogic"; exec sleep 30 ;;
logic-stdin) read -r _ && exec sleep 30; echo "SCRIPT ERROR: Parse Error: boom"; exit 1 ;;
esac
echo "LOGIC OK (0 failures)"
[ "$FAKE_MODE" = exit-noise ] && echo "ERROR: 4 resources still in use at exit"
exit 0
GODOT
chmod +x "$tmp/bin/godot"
run() { TLON_HOUSE_CHECK_BOUND="${BOUND:-300}" FAKE_MODE="$1" PATH="$tmp/bin:$PATH" "$here/house-check.sh" 2>&1; }

out="$(run ok)"
code=$?
expect "green is quiet and exits 0" "$code:[$out]" "0:[]"
out="$(run exit-noise)"
code=$?
expect "an ERROR after LOGIC OK (godot's exit noise) stays green" "$code:[$out]" "0:[]"
out="$(run logic-fail)"
code=$?
expect "a failing logic case: exit 1" "$code" "1"
expect "  names the step and exit code" "$(grep -c '^house:check: FAILED — logic.gd (godot exit 1)$' <<<"$out")" "1"
expect "  prints the failing assertion" "$(grep -c '^FAIL: done of a waiting-on returns 404$' <<<"$out")" "1"
out="$(run logic-crash)"
code=$?
expect "a crash with no verdict line: step, exit code, output" "$code:$(grep -c 'logic.gd (godot exit 139)' <<<"$out"):$(grep -c '^partial output$' <<<"$out")" "1:1:1"
out="$(run load-exit)"
code=$?
expect "a load step exiting non-zero with no ERROR line is named" "$code:$(grep -c '^house:check: FAILED — scripts load (--quit) (godot exit 3)$' <<<"$out")" "1:1"
out="$(run load-error)"
code=$?
expect "a load ERROR line is shown" "$code:$(grep -c '^SCRIPT ERROR: Parse Error: boom$' <<<"$out")" "1:1"
out="$(BOUND=2 run logic-hang)"
code=$?
expect "a looping check is killed at the bound and named" "$code:$(grep -c "^house:check: FAILED — logic.gd timed out after 2s (last: LOGIC > ChoreLogic)$" <<<"$out")" "1:1"
start=$SECONDS
out="$(BOUND=20 run logic-stdin)"
code=$?
expect "a script error with stdin closed fails at once, not at the bound" "$code:$(grep -c "timed out" <<<"$out"):$(grep -c "^SCRIPT ERROR: Parse Error: boom$" <<<"$out"):$((SECONDS - start < 10))" "1:0:1:1"
exit "$bad"
