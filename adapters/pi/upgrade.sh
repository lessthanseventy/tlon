#!/usr/bin/env bash
# Bump pi PROPER — the nix-wrapped release binary in flake.nix — to a release tag, then the
# adapters' pi-* dep ranges to match, then home:switch and the extension update. `pi update`
# alone only touches ~/.pi/agent/npm (extensions); the binary is nix's, so it moves here.
#
#   modules/adapters/pi/upgrade.sh            # latest GitHub release
#   modules/adapters/pi/upgrade.sh 0.85.1     # a specific version
#   PI_UPGRADE_NO_SWITCH=1 ...                # edit the pins only, no home:switch
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

want="${1:-}"
if [ -z "$want" ]; then
  want=$(curl -fsSL https://api.github.com/repos/earendil-works/pi/releases/latest | jq -r '.tag_name | ltrimstr("v")')
fi
[ -n "$want" ] && [ "$want" != "null" ] || { echo "pi:upgrade — could not resolve a release" >&2; exit 1; }

have=$(perl -0ne 'print $1 if /pname = "pi-coding-agent";\s*version = "([^"]+)"/' flake.nix)
echo "pi:upgrade — flake pins $have, target $want"
if [ "$have" = "$want" ]; then
  echo "pi:upgrade — already at $want"
else
  url="https://github.com/earendil-works/pi/releases/download/v${want}/pi-linux-x64.tar.gz"
  hash=$(nix store prefetch-file --json "$url" | jq -r .hash)
  perl -0pi -e "s/(pname = \"pi-coding-agent\";\s*version = \")[^\"]+/\${1}$want/" flake.nix
  perl -0pi -e "s|(pi-linux-x64\.tar\.gz\";\s*hash = \")[^\"]+|\${1}$hash|" flake.nix
  echo "pi:upgrade — flake.nix → $want ($hash)"
fi

# the adapters' pi-* deps track the same release
sed -i -E "s|(\"@earendil-works/pi-(ai\|coding-agent\|tui)\": \"\^)[^\"]+|\1$want|" modules/adapters/pi/package.json
(cd modules/adapters/pi && bun install --silent)   # bun.lock follows; adapters:pi:check is --frozen-lockfile
echo "pi:upgrade — adapters/pi pi-* deps → ^$want (bun.lock refreshed)"

if [ -z "${PI_UPGRADE_NO_SWITCH:-}" ]; then
  mise run home:switch
  echo "pi:upgrade — now $(pi --version)"
  mise run pi:update
fi
