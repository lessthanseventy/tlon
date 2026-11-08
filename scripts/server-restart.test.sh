#!/usr/bin/env bash
# Self-test of server-restart.sh: a restart that would cut work off is refused with what it would
# cut, --force and a server that cannot be asked restart anyway, and the workers are told why.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
. "$here/lib/test.sh"

mkdir "$tmp/bin"
printf '#!/bin/sh\necho "$@" >>"%s/systemctl"\n' "$tmp" >"$tmp/bin/systemctl"
printf '#!/bin/sh\ncase "$1" in\n  quiet) cat "%s/quiet" 2>/dev/null; exit "$(cat "%s/quiet_exit" 2>/dev/null || echo 0)" ;;\n  *) echo "$@" >>"%s/cli.log" ;;\nesac\n' "$tmp" "$tmp" "$tmp" >"$tmp/cli"
chmod +x "$tmp/bin/systemctl" "$tmp/cli"
export PATH="$tmp/bin:$PATH" TLON_CLI="$tmp/cli"
restarts() { { cat "$tmp/systemctl" 2>/dev/null || true; } | grep -c '^--user restart tlon'; }
restart() { "$here/server-restart.sh" "$@" 2>&1; }

printf 'busy\na coworker mid-turn\na landing\n' >"$tmp/quiet"
out="$(restart)"; code=$?
expect "a busy server is not restarted" "$code:$(restarts)" "1:0"
expect "  and the refusal names what it would cut" "$(echo "$out" | grep -c '^  a coworker mid-turn')" "1"
expect "  and how to override" "$(echo "$out" | grep -c 'server:restart -- --force')" "1"

out="$(TLON_RESTART_WHY="a release" restart --force)"; code=$?
expect "--force restarts a busy server" "$code:$(restarts)" "0:1"
expect "  after telling the workers why" "$(grep -c "^announce-restart a release$" "$tmp/cli.log")" "1"

echo idle >"$tmp/quiet"
restart >/dev/null
expect "an idle server is restarted" "$(restarts)" "2"

: >"$tmp/quiet"; echo 1 >"$tmp/quiet_exit"
restart >/dev/null
expect "a server that cannot be asked is restarted: that is what it needs" "$(restarts)" "3"

exit "$bad"
