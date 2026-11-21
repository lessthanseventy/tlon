#!/usr/bin/env bash
# The house's whole verification, fast: house:check, then the soak's sections as parallel headless
# Godot processes, each with its own throwaway XDG_DATA_HOME and its own stub-server port (the
# runner listens on port 0, so a parallel run never collides).
#
#   scripts/house-gate.sh              always runs
#   scripts/house-gate.sh --if-changed what `mise run check` runs: only when the commits being gated
#                                      (merge-base with origin/main..HEAD, and the working tree) touch
#                                      house/, or there is no range to look at (main itself: a full run)
#
# TLON_HOUSE_JOBS: sections at once (default half the cores); TLON_HOUSE_BOUND: seconds before a section is killed (default 600, short in the self-test). TLON_HOUSE_GATE=required makes a
# missing godot red; unset, it is a named skip. A verdict line goes to $TLON_GATE_NOTES when set, so
# the gate's own summary can repeat it.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 2

bound="${TLON_HOUSE_BOUND:-600}"
jobs_max="${TLON_HOUSE_JOBS:-$(($(nproc) / 2))}"
[ "$jobs_max" -ge 1 ] 2>/dev/null || jobs_max=1

note() {
	echo "$*"
	[ -z "${TLON_GATE_NOTES:-}" ] || echo "$*" >>"$TLON_GATE_NOTES"
}

touched() {
	local base
	base="$(git merge-base HEAD origin/main 2>/dev/null)" || return 0
	[ "$base" != "$(git rev-parse HEAD)" ] || [ -n "$(git status --porcelain -- house)" ] || return 0
	[ -n "$(git diff --name-only "$base" HEAD -- house)" ] || [ -n "$(git status --porcelain -- house)" ]
}

if [ "${1:-}" = --if-changed ] && ! touched; then
	note "house: unchanged, not run"
	exit 0
fi

if ! command -v godot >/dev/null 2>&1; then
	if [ "${TLON_HOUSE_GATE:-}" = required ]; then
		note "house: FAILED — godot is not on PATH and TLON_HOUSE_GATE=required"
		exit 1
	fi
	note "house: SKIPPED — godot not on PATH (set TLON_HOUSE_GATE=required to make this red)"
	exit 0
fi

work="$(mktemp -d)"
pids=()
cleanup() {
	local p
	for p in "${pids[@]}"; do pkill -TERM -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
	for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mise run house:check || {
	note "house: FAILED — house:check"
	exit 1
}

sections="$(XDG_DATA_HOME="$work/list" godot --headless --path house --script res://soak.gd -- --list 2>&1 | sed '/^SOAK LIST/d;/^$/d;/^Godot Engine/d')"
if [ -z "$sections" ] || echo "$sections" | grep -qE '[^a-z]'; then
	echo "$sections"
	note "house: FAILED — could not list the soak's sections"
	exit 1
fi

section() {
	local n="$1" began="$SECONDS" code
	XDG_DATA_HOME="$work/data-$n" timeout -k 5 "$bound" godot --headless --path house --script res://soak.gd -- "$n" >"$work/$n.log" 2>&1
	code=$?
	echo "$code" >"$work/$n.code"
	echo "$((SECONDS - began))" >"$work/$n.secs"
}

began="$SECONDS"
for n in $sections; do
	while [ "$(jobs -rp | wc -l)" -ge "$jobs_max" ]; do wait -n 2>/dev/null; done
	section "$n" &
	pids+=("$!")
done
wait "${pids[@]}"
pids=()

verdict() {
	local n="$1" code
	code="$(cat "$work/$n.code")"
	if [ "$code" = 124 ] || [ "$code" = 137 ]; then
		echo "TIMEOUT"
	elif [ "$code" = 0 ] && awk '/^SOAK OK/{ok=1} /^(SCRIPT )?ERROR/ && !ok{bad=1} END{exit !(ok && !bad)}' "$work/$n.log"; then
		echo "ok"
	else echo "FAILED"; fi
}

failed=0
printf '\n%-10s %7s  %s\n' section secs "last line"
for n in $sections; do
	v="$(verdict "$n")"
	[ "$v" = ok ] || failed=1
	printf '%-10s %6ss  %-7s %s\n' "$n" "$(cat "$work/$n.secs")" "$v" "$(grep -E '^SOAK (OK|FAILED)' "$work/$n.log" | tail -n 1 | grep . || grep -v '^$' "$work/$n.log" | tail -n 1 | cut -c1-100)"
done
for n in $sections; do
	[ "$(verdict "$n")" = ok ] && continue
	echo
	echo "== $n: $(verdict "$n") =="
	if grep -qE '^FAIL|ERROR' "$work/$n.log"; then grep -E '^FAIL|^(SCRIPT )?ERROR' "$work/$n.log" | sed "s/^/$n: /"; else tail -n 5 "$work/$n.log" | sed "s/^/$n: /"; fi
done
echo
if [ "$failed" = 0 ]; then
	note "house: ok — $(echo "$sections" | wc -w) sections, $jobs_max at once, $((SECONDS - began))s"
	exit 0
fi
note "house: FAILED — see the sections above"
exit 1
