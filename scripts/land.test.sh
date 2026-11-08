#!/usr/bin/env bash
# Self-test of land.sh's preflight: a PR that is not open, not onto main, from a fork, from main or
# from a protected (or unreadable) branch is refused before it reaches the merge queue; a good one
# is handed to the queue with its branch and author.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
. "$here/lib/test.sh"

mkdir "$tmp/bin"
cat >"$tmp/bin/gh" <<SH
#!/bin/sh
case "\$1" in
  pr) cat "$tmp/pr" ;;
  api) cat "$tmp/protected" ;;
esac
SH
printf '#!/bin/sh\necho "$@" >>"%s/cli.log"\n' "$tmp" >"$tmp/cli"
chmod +x "$tmp/bin/gh" "$tmp/cli"
export PATH="$tmp/bin:$PATH" TLON_CLI="$tmp/cli"
land() { "$here/land.sh" "$@" 2>&1; }
queued() { { cat "$tmp/cli.log" 2>/dev/null || true; } | wc -l; }
good='feature main OPEN false andrew'

printf '%s' false >"$tmp/protected"
printf '%s' "$good" >"$tmp/pr"
land >/dev/null; expect "no PR number is a usage error" "$?" "2"
land 12x >/dev/null; expect "a non-numeric PR is a usage error" "$?" "2"

for case in 'feature main CLOSED false andrew|it is CLOSED' 'feature develop OPEN false andrew|it targets develop' \
  'feature main OPEN true andrew|on a fork' 'main main OPEN false andrew|its branch is main'; do
  printf '%s' "${case%%|*}" >"$tmp/pr"
  out="$(land 12)"; code=$?
  expect "refused: ${case#*|}" "$code:$(echo "$out" | grep -c "${case#*|}"):$(queued)" "1:1:0"
done

printf '%s' "$good" >"$tmp/pr"
printf '%s' true >"$tmp/protected"
out="$(land 12)"; code=$?
expect "a protected branch is refused" "$code:$(echo "$out" | grep -c 'is protected'):$(queued)" "1:1:0"
printf '%s' '' >"$tmp/protected"
out="$(land 12)"; code=$?
expect "an unreadable protection is refused" "$code:$(echo "$out" | grep -c "can't tell"):$(queued)" "1:1:0"

printf '%s' false >"$tmp/protected"
land 12 >/dev/null; code=$?
expect "a good PR goes to the queue with its branch and author" "$code:$(cat "$tmp/cli.log")" "0:land-pr 12 feature andrew"

exit "$bad"
