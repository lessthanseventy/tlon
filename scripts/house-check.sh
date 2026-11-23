#!/usr/bin/env bash
# house:check — every script loads clean in headless Godot, then logic.gd passes. A red step names
# itself, godot's exit code and the last 40 lines of its output; a green run is quiet.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
d="$(mktemp -d)"
trap 'rm -rf "$d"' EXIT
errors='ERROR|SCRIPT ERROR|Parse Error|Unicode parsing error'

step() {
	local name="$1" mode="$2" out code
	shift 2
	out="$(XDG_DATA_HOME="$d" godot --headless --path house "$@" 2>&1)"
	code=$?
	case "$mode" in
	loads) [ "$code" -eq 0 ] && ! grep -qE "$errors" <<<"$out" && return 0 ;;
	logic) [ "$code" -eq 0 ] && grep -q '^LOGIC OK' <<<"$out" && ! sed '/^LOGIC OK/q' <<<"$out" | grep -qE '^(SCRIPT )?ERROR' && return 0 ;;
	esac
	echo "house:check: FAILED — $name (godot exit $code)"
	tail -n 40 <<<"$out"
	exit 1
}

step "scripts load (--quit)" loads --quit
step "soak.gd parses (--check-only)" loads --check-only --script res://soak.gd
step "logic.gd" logic --script res://logic.gd
