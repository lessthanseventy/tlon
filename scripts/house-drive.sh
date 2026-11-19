#!/usr/bin/env bash
# Drives the real, running house (house/drive.gd) from a shell: start it live under headless
# gamescope on a throwaway data folder, send it one JSON command per argument, read the Godot errors
# it printed, stop it. The run's files are in $XDG_RUNTIME_DIR/tlon-house-drive/ (pid, port, data,
# log, shots/). The throwaway XDG_DATA_HOME is set on the gamescope process only, never exported
# into a shell that goes on to call mise.
#
#   scripts/house-drive.sh start [house args]   prints the port (HOUSE_DRIVE_W / _H: the window, 1100x700)
#   scripts/house-drive.sh send '<json>' ...    one reply line per command
#   scripts/house-drive.sh errors               Godot error lines since the last call
#   scripts/house-drive.sh stop
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
run="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/tlon-house-drive"
alive() { [ -f "$run/pid" ] && kill -0 "$(cat "$run/pid")" 2>/dev/null; }
need_up() { alive || {
	echo "house-drive: no house is running (mise run house:drive:start)" >&2
	exit 1
}; }

start() {
	if alive; then
		echo "house-drive: already running on port $(cat "$run/port")" >&2
		exit 1
	fi
	rm -rf "$run"
	mkdir -p "$run/shots"
	local data
	data="$(mktemp -d "${TMPDIR:-/tmp}/tlon-house-drive-data.XXXXXX")"
	echo "$data" >"$run/data"
	echo 0 >"$run/errors.seen"
	XDG_DATA_HOME="$data" setsid gamescope --backend headless -W "${HOUSE_DRIVE_W:-1100}" -H "${HOUSE_DRIVE_H:-700}" -- \
		godot --display-driver x11 --path "$root/house" -- --drive "$@" >"$run/log" 2>&1 &
	echo $! >"$run/pid"
	local line=""
	for _ in $(seq 300); do
		line="$(grep -m1 '^DRIVE ' "$run/log" || true)"
		[ -n "$line" ] && break
		alive || break
		sleep 0.2
	done
	if [ -z "$line" ]; then
		echo "house-drive: the house did not report a port; log: $run/log" >&2
		tail -n 20 "$run/log" >&2
		stop
		exit 1
	fi
	echo "${line#DRIVE }" | tee "$run/port"
}

send() {
	need_up
	exec 3<>"/dev/tcp/127.0.0.1/$(cat "$run/port")"
	local cmd out
	for cmd in "$@"; do
		out="$(jq -c --arg dir "$run/shots" \
			'if .do == "shot" and (.path | type) == "string" and (.path | startswith("/") | not)
       then .path = $dir + "/" + .path else . end' <<<"$cmd" 2>/dev/null)" || out="$cmd"
		printf '%s\n' "$out" >&3
		IFS= read -r -t 330 reply <&3 || {
			echo '{"ok":false,"error":"no reply from the house"}'
			continue
		}
		printf '%s\n' "$reply"
	done
	exec 3>&-
}

errors() {
	[ -f "$run/log" ] || {
		echo "house-drive: no log (mise run house:drive:start)" >&2
		exit 1
	}
	local seen total
	seen="$(cat "$run/errors.seen")"
	total="$(wc -l <"$run/log")"
	tail -n "+$((seen + 1))" "$run/log" |
		awk '/^(SCRIPT )?ERROR/ { print; keep = 1; next } keep && /^ +at:/ { print; next } { keep = 0 }'
	echo "$total" >"$run/errors.seen"
}

stop() {
	if alive; then
		if [ -f "$run/port" ]; then
			exec 3<>"/dev/tcp/127.0.0.1/$(cat "$run/port")" 2>/dev/null &&
				{
					echo '{"do":"quit"}' >&3
					IFS= read -r -t 5 _ <&3 || true
					exec 3>&-
				} || true
		fi
		for _ in $(seq 50); do
			alive || break
			sleep 0.1
		done
		alive && kill -TERM -- "-$(cat "$run/pid")" 2>/dev/null || true
	fi
	[ -f "$run/data" ] && rm -rf "$(cat "$run/data")"
	rm -rf "$run"
}

case "${1:-}" in
start)
	shift
	start "$@"
	;;
send)
	shift
	send "$@"
	;;
errors) errors ;;
stop) stop ;;
*)
	echo "usage: house-drive.sh start [house args] | send JSON... | errors | stop" >&2
	exit 2
	;;
esac
