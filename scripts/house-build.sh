#!/usr/bin/env bash
# Builds the house for another machine, from this one, into $dist/<platform>/ and
# $dist/the-house-<platform>.zip (see lib/house-dist.sh; never inside a repo). Windows and Linux are
# one executable with the code and the art pack (scripts/house-art-pack.sh) in its embedded pck;
# the Mac app carries the pack in its Resources. Presets: house/export_presets.cfg.
#
# The art goes in as raw files: a throwaway copy of house/ under $dist gets the pack's files in art/,
# each with a `keep` .import so Godot neither imports it as a texture nor leaves it out of the pck.
# art.gd reads them at res://art.
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
  local project="$root/house" stage=""
  if [ "$platform" != mac ]; then
    stage="$dist/.stage-$platform"
    rm -rf "$stage"
    mkdir -p "$stage"
    rsync -a --exclude .godot --exclude '*.uid' --exclude .logs "$root/house/" "$stage/" || return 1
    unzip -q "$dist/house-art.zip" -d "$stage" || return 1
    find "$stage/art" -type f ! -name '*.import' -print0 |
      while IFS= read -r -d '' f; do printf '[remap]\n\nimporter="keep"\n' >"$f.import"; done
    godot --headless --path "$stage" --import >"$out/import.log" 2>&1 || true
    project="$stage"
  fi
  godot --headless --path "$project" --export-release "$preset" "$out/$exe" >"$out/export.log" 2>&1 || true
  [ -z "$stage" ] || rm -rf "$stage"
  [ -s "$out/$exe" ] || { grep -E "ERROR|Cannot|Enable|select|WARNING" "$out/export.log" >&2; echo "house: the $preset export produced nothing" >&2; return 1; }
  rm -f "$out/export.log" "$out/import.log"
  if [ "$platform" = mac ]; then
    (cd "$out" && unzip -q "$exe" && rm "$exe") || return 1
    local app
    app="$(basename "$out"/*.app)"
    cp "$dist/house-art.zip" "$out/$app/Contents/Resources/" || return 1
    (cd "$out" && zip -q -r -y -X "$dist/the-house-mac.zip" "$app") || return 1
  else
    (cd "$out" && zip -q -X "$dist/the-house-$platform.zip" "$exe") || return 1
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
