#!/usr/bin/env bash
# Self-test of house-app.sh: install builds through house-build.sh and leaves an executable at the
# path (replacing atomically, no .new left), a missing godot is a named skip that leaves nothing, a
# failed build keeps the old copy, run starts the installed file or says to install, and install
# writes the launcher's desktop entry and icon, leaving both untouched on a second run and rewriting each when its content changes.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
. "$here/lib/test.sh"

mkdir -p "$tmp/scripts/lib" "$tmp/bin"
cp "$here/house-app.sh" "$tmp/scripts/"
cp "$here/lib/house-dist.sh" "$tmp/scripts/lib/"
cat >"$tmp/scripts/house-build.sh" <<'B'
#!/usr/bin/env bash
[ "${FAKE_BUILD:-ok}" = ok ] || exit 1
mkdir -p "$TLON_HOUSE_DIST/linux"
printf '#!/bin/sh\necho "asterion $*"\n' >"$TLON_HOUSE_DIST/linux/asterion"
B
chmod +x "$tmp/scripts/house-build.sh"
mkdir -p "$tmp/house"
printf 'png' >"$tmp/house/icon.png"
printf '#!/bin/sh\n' >"$tmp/bin/godot"
chmod +x "$tmp/bin/godot"
export TLON_HOUSE_DIST="$tmp/dist" TLON_ASTERION_BIN="$tmp/app/asterion" XDG_DATA_HOME="$tmp/data"
app() { PATH="$tmp/bin:$PATH" "$tmp/scripts/house-app.sh" "$@" 2>&1; }

expect "run before install says so" "$(app run | grep -c 'house:install')" 1
app install >/dev/null
expect "install leaves an executable" "$([ -x "$TLON_ASTERION_BIN" ] && echo yes)" yes
expect "no .new left" "$(ls "$tmp/app")" asterion
expect "run starts it" "$(app run --x)" "asterion --x"
entry="$tmp/data/applications/asterion.desktop"
icon="$tmp/data/icons/hicolor/256x256/apps/asterion.png"
expect "entry execs the installed binary" "$(grep -c "^Exec=$TLON_ASTERION_BIN\$" "$entry")" 1
expect "entry names the window class" "$(grep -c '^StartupWMClass=Asterion$' "$entry")" 1
expect "entry names the icon" "$(grep -c '^Icon=asterion$' "$entry")" 1
expect "icon installed" "$(cat "$icon")" png
expect "no .new left beside the entry" "$(find "$tmp/data" -name '*.new' | wc -l)" 0
touch -d '2020-01-01' "$entry" "$icon"
app install >/dev/null
expect "a second install leaves the entry" "$(stat -c %y "$entry" | cut -c1-4)" 2020
expect "a second install leaves the icon" "$(stat -c %y "$icon" | cut -c1-4)" 2020
moved="$tmp/moved/asterion"
TLON_ASTERION_BIN="$moved" app install >/dev/null
expect "a moved binary rewrites the entry" "$(grep -c "^Exec=$moved\$" "$entry")" 1
expect "the rewritten entry leaves no old Exec" "$(grep -c "^Exec=$TLON_ASTERION_BIN\$" "$entry")" 0
printf 'png2' >"$tmp/house/icon.png"
app install >/dev/null
expect "a changed icon is rewritten" "$(cat "$icon")" png2
echo old >"$TLON_ASTERION_BIN"
FAKE_BUILD=fail app install >/dev/null
expect "a failed build keeps the old copy" "$(cat "$TLON_ASTERION_BIN")" old
rm "$TLON_ASTERION_BIN"
mkdir "$tmp/bare"
for t in env bash dirname; do ln -s "$(command -v "$t")" "$tmp/bare/$t"; done
out="$(PATH="$tmp/bare" "$tmp/scripts/house-app.sh" install 2>&1)"
expect "no godot is a named skip" "$(echo "$out" | grep -c SKIPPED)" 1
expect "the skip leaves nothing" "$([ -e "$TLON_ASTERION_BIN" ] && echo yes || echo no)" no
exit "$bad"
