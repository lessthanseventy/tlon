#!/usr/bin/env bash
# Self-test of house-app.sh: install builds through house-build.sh and leaves an executable at the
# path (replacing atomically, no .new left), a missing godot is a named skip that leaves nothing, a
# failed build keeps the old copy, and run starts the installed file or says to install.
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
printf '#!/bin/sh\n' >"$tmp/bin/godot"
chmod +x "$tmp/bin/godot"
export TLON_HOUSE_DIST="$tmp/dist" TLON_ASTERION_BIN="$tmp/app/asterion"
app() { PATH="$tmp/bin:$PATH" "$tmp/scripts/house-app.sh" "$@" 2>&1; }

expect "run before install says so" "$(app run | grep -c 'house:install')" 1
app install >/dev/null
expect "install leaves an executable" "$([ -x "$TLON_ASTERION_BIN" ] && echo yes)" yes
expect "no .new left" "$(ls "$tmp/app")" asterion
expect "run starts it" "$(app run --x)" "asterion --x"
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
