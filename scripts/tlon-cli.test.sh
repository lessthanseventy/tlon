#!/usr/bin/env bash
# Self-test of tlon-cli.sh: a caller that closed stderr still hands the client node a stderr that
# takes writes, so a boot-time error report cannot kill the VM with a crash dump.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0

printf '#!/bin/sh\nif printf . >&2 2>/dev/null; then echo writable; else echo closed; fi\n' >"$tmp/server"
chmod +x "$tmp/server"

out="$(TLON_CLI_SERVER="$tmp/server" XDG_STATE_HOME="$tmp/state" "$here/tlon-cli.sh" toys 2>&-)"
[ "$out" = writable ] && echo "ok   a closed stderr reaches the client node as a writable one" || { echo "FAIL closed stderr must not reach the client node (got: $out)"; bad=1; }

out="$(TLON_CLI_SERVER="$tmp/server" XDG_STATE_HOME="$tmp/state" "$here/tlon-cli.sh" toys 2>/dev/null)"
[ "$out" = writable ] && echo "ok   stderr to /dev/null is untouched" || { echo "FAIL (got: $out)"; bad=1; }

exit "$bad"
