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

printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"$STUB_LOG"\nprintf "{\\"token\\":\\"tok-123\\"}"\n' >"$tmp/curl"
chmod +x "$tmp/curl"
out="$(STUB_LOG="$tmp/curl.log" TLON_CLI_CURL="$tmp/curl" TLON_MCP_URL="http://127.0.0.1:4041/mcp" TLON_THREAD=7 TLON_AUTHOR=hronir XDG_STATE_HOME="$tmp/state" "$here/tlon-cli.sh" token)"
[ "$out" = '{"Authorization":"Bearer tok-123"}' ] && echo "ok   token prints the headers JSON" || { echo "FAIL token header (got: $out)"; bad=1; }
{ grep -qx 'http://127.0.0.1:4041/mint' "$tmp/curl.log" && grep -qx '{"thread_id": 7, "agent": "hronir"}' "$tmp/curl.log"; } &&
  echo "ok   token mints at the URL's /mint for the thread and author" || { echo "FAIL token request: $(cat "$tmp/curl.log")"; bad=1; }

err="$(XDG_STATE_HOME="$tmp/state" "$here/tlon-cli.sh" 2>&1 >/dev/null)"; code=$?
{ [ "$code" = 2 ] && [[ "$err" == usage:* ]]; } && echo "ok   no arguments: usage on stderr, exit 2" || { echo "FAIL usage (exit $code, got: $err)"; bad=1; }

exit "$bad"
