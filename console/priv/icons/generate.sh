#!/usr/bin/env bash
# Generate the cockpit's icon PNGs from Lucide (https://lucide.dev, ISC) SVGs — the raster tier for
# Console.Icons (Slice 3.4). Reproducible: re-run to refresh or add icons. Requires curl + resvg.
# Output: <name>.png (RGBA), committed alongside this script; Console.Icons embeds them at compile.
#
# Kitty scales the PNG to the placement, so ONE size works at any font size — we render generously.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="https://raw.githubusercontent.com/lucide-icons/lucide/main/icons"
COLOR="#d8d8d8"   # a light neutral that reads on the dark cockpit (recolors Lucide's currentColor)
SIZE=128

# our-name:lucide-name — the app-wide set. Add a row, re-run, then wire it in Console.Icons.
ICONS="
home:house
add:plus
settings:settings
ticket:ticket
note:sticky-note
now:activity
crew:users
memory:brain
stack:git-branch
threads:messages-square
rocket:rocket
box:box
folder:folder
code:code
terminal:terminal
globe:globe
star:star
layers:layers
flask:flask-conical
cpu:cpu
"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for pair in $ICONS; do
  name="${pair%%:*}"; lucide="${pair##*:}"
  curl -fsSL "$BASE/$lucide.svg" -o "$tmp/$name.svg"
  sed "s/currentColor/$COLOR/g" "$tmp/$name.svg" > "$tmp/${name}_c.svg"
  resvg --width "$SIZE" --height "$SIZE" "$tmp/${name}_c.svg" "$DIR/$name.png"
  echo "  $name.png  ←  lucide/$lucide"
done

# Workspace DIGIT icons (`d1.png`…`d9.png`) — the numbers as icons, matching the line set: a thin
# (Light-weight) sans digit in the same neutral, so a numbered workspace reads as an icon, not
# terminal text. Noto Sans Light is on-box; falls back through fontconfig if not.
for n in 1 2 3 4 5 6 7 8 9; do
  cat > "$tmp/d$n.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <text x="12" y="18" font-family="Noto Sans" font-weight="300" font-size="20" fill="$COLOR" text-anchor="middle">$n</text>
</svg>
SVG
  resvg --width "$SIZE" --height "$SIZE" "$tmp/d$n.svg" "$DIR/d$n.png"
  echo "  d$n.png  ←  digit $n"
done

echo "done → $DIR"
