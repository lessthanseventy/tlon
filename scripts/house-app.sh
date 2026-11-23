#!/usr/bin/env bash
# The installed Asterion: the Linux build (art inside, house-build.sh) put where a command can run it,
# outside the git tree. `install` replaces it atomically (rename), so a running copy is not broken
# mid-write; no godot is a named skip, so a landing never fails on a machine that cannot build.
# `run` starts it, or says to install when there is none.
#
#   scripts/house-app.sh install | run [args]
# TLON_ASTERION_BIN moves the installed file (default ~/.local/share/asterion/asterion).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/house-dist.sh"
bin="${TLON_ASTERION_BIN:-$HOME/.local/share/asterion/asterion}"

case "${1:-}" in
install)
	command -v godot >/dev/null 2>&1 || {
		echo "house: SKIPPED — godot not on PATH, Asterion not built" >&2
		exit 0
	}
	"$here/house-build.sh" linux
	mkdir -p "$(dirname "$bin")"
	cp "$dist/linux/asterion" "$bin.new"
	chmod +x "$bin.new"
	mv -f "$bin.new" "$bin"
	echo "house: installed $bin" >&2
	;;
run)
	shift
	[ -x "$bin" ] || {
		echo "house: no installed Asterion at $bin: run mise run house:install (or house:run from source)" >&2
		exit 1
	}
	exec "$bin" "$@"
	;;
*)
	echo "usage: house-app.sh install | run [args]" >&2
	exit 2
	;;
esac
