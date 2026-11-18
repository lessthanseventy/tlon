#!/usr/bin/env bash
# Builds the house for another machine, from this one, into $dist/<platform>/ and
# $dist/the-house-<platform>.zip (see lib/house-dist.sh; never inside a repo). The code is one
# executable with its pck embedded; the art pack (scripts/house-art-pack.sh) sits beside it, inside
# the .app's Resources on a Mac. Presets: house/export_presets.cfg.
#
#   scripts/house-build.sh windows|mac|linux|all
set -euo pipefail
. "$(dirname "$0")/lib/house-dist.sh"

templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$(godot --version | sed -E 's/^([0-9.]+)\.([a-z]+)\..*/\1.\2/')"

build() {
  local platform="$1" preset exe tmpl
  case "$platform" in
    windows) preset="Windows Desktop"; exe="the-house.exe"; tmpl="windows_release_x86_64.exe" ;;
    mac)     preset="macOS";           exe="the-house.zip"; tmpl="macos.zip" ;;
    linux)   preset="Linux";           exe="the-house";     tmpl="linux_release.x86_64" ;;
    *) echo "usage: house-build.sh windows|mac|linux|all" >&2; return 2 ;;
  esac
  [ -f "$templates/$tmpl" ] || {
    echo "house: no export template $templates/$tmpl: install Godot's official 4.7.2 export templates" >&2
    return 1
  }
  local out="$dist/$platform"
  rm -rf "$out" "$dist/the-house-$platform.zip"
  mkdir -p "$out"
  godot --headless --path "$root/house" --export-release "$preset" "$out/$exe" >"$out/export.log" 2>&1 || true
  [ -s "$out/$exe" ] || { grep -E "ERROR|Cannot|Enable|select|WARNING" "$out/export.log" >&2; echo "house: the $preset export produced nothing" >&2; return 1; }
  rm -f "$out/export.log"
  if [ "$platform" = mac ]; then
    (cd "$out" && unzip -q "$exe" && rm "$exe") || return 1
    local app
    app="$(basename "$out"/*.app)"
    cp "$dist/house-art.zip" "$out/$app/Contents/Resources/" || return 1
    (cd "$out" && zip -q -r -y -X "$dist/the-house-mac.zip" "$app") || return 1
  else
    cp "$dist/house-art.zip" "$out/" || return 1
    local stage
    stage="$(mktemp -d)"
    ln -s "$out" "$stage/the-house"
    (cd "$stage" && zip -q -r -X "$dist/the-house-$platform.zip" the-house) || return 1
    rm -rf "$stage"
  fi
  echo "house: $platform -> $dist/the-house-$platform.zip ($(du -h "$dist/the-house-$platform.zip" | cut -f1))" >&2
}

[ $# -eq 1 ] || { echo "usage: house-build.sh windows|mac|linux|all" >&2; exit 2; }
dist_outside_git
mkdir -p "$dist"
"$(dirname "$0")/house-art-pack.sh"
failed=0
if [ "$1" = all ]; then
  for p in windows mac linux; do build "$p" || failed=1; done
else
  build "$1" || failed=1
fi
exit "$failed"
