#!/usr/bin/env bash
# The art the house can open, packed for a build: house-art.zip in the dist dir (see lib/house-dist.sh).
# The list is derived from the house's own loaders (house/art_pack.gd), so a pack file nothing opens
# is not in it. Mounted at run time as res://art (house/art.gd).
#
#   scripts/house-art-pack.sh            build $dist/house-art.zip, print count and size per pack
#   scripts/house-art-pack.sh --list     print the files it would hold; build nothing
set -euo pipefail
. "$(dirname "$0")/lib/house-dist.sh"

[ -d "$art" ] || { echo "house: no art folder at $art (TLON_ART_DIR)" >&2; exit 1; }
list="$(mktemp)"
stage="$(mktemp -d)"
trap 'rm -rf "$list" "$stage"' EXIT

out="$(godot --headless --path "$root/house" --script res://art_pack.gd -- --art-dir "$art" --out "$list" 2>&1)" \
  || { grep -E "^MISSING" <<<"$out" >&2; echo "house: art_pack.gd failed" >&2; exit 1; }
grep -E "^(PACK|TOTAL)" <<<"$out" >&2
[ -s "$list" ] || { echo "house: the art list came out empty" >&2; exit 1; }

if [ "${1:-}" = "--list" ]; then
  cat "$list"
  exit 0
fi

dist_outside_git
mkdir -p "$dist"
ln -s "$art" "$stage/art"
rm -f "$dist/house-art.zip"
(cd "$stage" && sed 's|^|art/|' "$list" | zip -q -X -@ "$dist/house-art.zip")
diff <(sed 's|^|art/|' "$list" | sort) <(unzip -Z1 "$dist/house-art.zip" | sort) >/dev/null \
  || { echo "house: the built pack does not hold exactly the list" >&2; exit 1; }
echo "house-art.zip: $(wc -l <"$list") files, $(du -h "$dist/house-art.zip" | cut -f1) -> $dist/house-art.zip" >&2
