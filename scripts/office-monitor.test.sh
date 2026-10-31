#!/usr/bin/env bash
# Self-test of office-monitor.sh's DOWN/UP across --until-new runs, against a curl that answers only while
# $UP_FLAG exists, and psql and journalctl that say nothing. A restart while the service is still down stays
# quiet and keeps watching; UP forgets the outage, so the next one is said again.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/sh
case "$*" in
  *"/api/office/needs"*) echo '[]' ;;
  *"/api/office"*) echo '{"health":{"problems":[]}}' ;;
esac
[ -e "$UP_FLAG" ]
EOF
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/psql"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/journalctl"
chmod +x "$tmp/bin/curl" "$tmp/bin/psql" "$tmp/bin/journalctl"
export UP_FLAG="$tmp/up" PATH="$tmp/bin:$PATH"
url=http://tlon.test:4040
seen_file="$tmp/state/tlon/office-monitor.seen"
bad=0

run() { # run: one --until-new invocation; its output in $out, its exit in $rc (124 = still watching after 3 s)
  out="$(TLON_URL=$url XDG_STATE_HOME="$tmp/state" TLON_MONITOR_EVERY=1 timeout 3 "$here/office-monitor.sh" --until-new 2>&1)"; rc=$?
}

run
if [ "$rc" = 0 ] && [ "$(grep -c '^DOWN' <<<"$out")" = 1 ]; then echo "ok   first DOWN is said and exits"; else echo "FAIL first DOWN: rc=$rc out=[$out]"; bad=1; fi

run
if [ "$rc" = 124 ] && [ -z "$out" ]; then echo "ok   restart while still down stays quiet and keeps watching"; else echo "FAIL restart while down: rc=$rc out=[$out]"; bad=1; fi

touch "$UP_FLAG"
run
if [ "$rc" = 0 ] && grep -q '^UP ' <<<"$out" && ! grep -qxF "down:$url" "$seen_file"; then echo "ok   UP is said, exits, and drops the DOWN key"; else echo "FAIL UP: rc=$rc out=[$out]"; bad=1; fi

rm -f "$UP_FLAG"
run
if [ "$rc" = 0 ] && [ "$(grep -c '^DOWN' <<<"$out")" = 1 ]; then echo "ok   the next outage is said again"; else echo "FAIL next outage: rc=$rc out=[$out]"; bad=1; fi
exit $bad
