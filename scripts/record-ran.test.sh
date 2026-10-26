#!/usr/bin/env bash
# Self-test of lib/record-ran.sh: a hand-run gate/smoke reports its ran-on result to the service
# (POST /api/release/ran), and a service that is down never fails the run that reported.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0
sha="$(printf 'a%.0s' {1..40})"
. "$here/lib/record-ran.sh"

# a curl that records its arguments and answers like the service
mkdir "$tmp/bin"
printf '#!/bin/sh\necho "$@" >"%s/args"\necho %s\n' "$tmp" "'{\"id\":1,\"status\":\"ok\"}'" >"$tmp/bin/curl"
chmod +x "$tmp/bin/curl"

out="$(PATH="$tmp/bin:$PATH" TLON_URL=http://svc:1 record_ran gate "$sha" 0 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL a recorded run returns 0 (got $code)"; bad=1; }
grep -q "http://svc:1/api/release/ran" "$tmp/args" || { echo "FAIL it posts to the service's /api/release/ran: $(cat "$tmp/args")"; bad=1; }
grep -q "\"check\":\"gate\".*\"sha\":\"$sha\".*\"exit\":0" "$tmp/args" || { echo "FAIL the body names check, sha and exit: $(cat "$tmp/args")"; bad=1; }
case "$out" in *"recorded"*) echo "ok   a run is reported and says so" ;; *) echo "FAIL it says it recorded: $out"; bad=1 ;; esac

printf '#!/bin/sh\nexit 7\n' >"$tmp/bin/curl"
out="$(PATH="$tmp/bin:$PATH" record_ran smoke "$sha" 0 2>&1)"; code=$?
[ "$code" = 0 ] || { echo "FAIL a service that is down must not fail the run (got $code)"; bad=1; }
case "$out" in *"not recorded"*) echo "ok   a service that is down: warned, run unharmed" ;; *) echo "FAIL it warns when the report fails: $out"; bad=1 ;; esac

exit "$bad"
