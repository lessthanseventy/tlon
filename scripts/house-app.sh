#!/usr/bin/env bash
# The installed Asterion: the Linux build (art inside, house-build.sh) put where a command can run it,
# outside the git tree. `install` replaces it atomically (rename), so a running copy is not broken
# mid-write; no godot is a named skip, so a landing never fails on a machine that cannot build.
# `run` starts it, or says to install when there is none. Install also writes the launcher's entry
# ($XDG_DATA_HOME/applications/asterion.desktop) and icon, each only when its content changed.
#
#   scripts/house-app.sh install | run [args]
# TLON_ASTERION_BIN moves the installed file (default ~/.local/share/asterion/asterion).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/house-dist.sh"
bin="${TLON_ASTERION_BIN:-$HOME/.local/share/asterion/asterion}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"

# put_if_changed SRC DEST: atomic, and untouched when DEST already holds SRC's bytes.
put_if_changed() {
	cmp -s "$1" "$2" 2>/dev/null && return 0
	mkdir -p "$(dirname "$2")"
	cp "$1" "$2.new"
	mv -f "$2.new" "$2"
}

# StartupWMClass is the window's class (the project name), so the launcher and bar group them.
install_launcher() {
	local entry
	entry="$(mktemp)"
	cat >"$entry" <<D
[Desktop Entry]
Type=Application
Name=Asterion
Exec=$bin
Icon=asterion
Terminal=false
Categories=Utility;
StartupWMClass=Asterion
D
	put_if_changed "$entry" "$data/applications/asterion.desktop"
	rm -f "$entry"
	put_if_changed "$root/house/icon.png" "$data/icons/hicolor/256x256/apps/asterion.png"
	if command -v update-desktop-database >/dev/null 2>&1; then
		update-desktop-database "$data/applications" || true
	fi
}

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
	install_launcher
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
