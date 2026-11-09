#!/usr/bin/env bash
# Self-test of workline-verify.sh's rules: the gates a diff is scoped to (or the full check), a green
# advances and a red goes back to build with its evidence, a landing gate records and advances nothing,
# the canary A/B runs only for a workline's own verify of a tree that has the task, and the refusals.
# Runs a copy of the real script in a private repo with a fake mise, curl, psql and tlon-cli.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
. "$here/lib/test.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export XDG_CACHE_HOME="$tmp/cache" HOME="$tmp/home"
for v in $(compgen -e | grep '^TLON_'); do unset "$v"; done
unset WORKLINE_GATE LAND_REF RUN_TASK RULES_ONLY
export TLON_URL=http://svc:1

git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
repo="$tmp/repo"
g() { git -C "$repo" "$@"; }
mkdir -p "$repo/scripts/lib" "$repo/server" "$repo/work/s1"
cp "$here/workline-verify.sh" "$here/git-fetch-origin.sh" "$repo/scripts/"
cp "$here/lib/seed-hex.sh" "$here/lib/failures.sh" "$repo/scripts/lib/"
touch "$repo/server/.keep"
g add -A && g commit -qm base && g push -q origin HEAD:main
branch() { # name file
  g checkout -q -b "$1" main && mkdir -p "$(dirname "$repo/$2")" && echo x >"$repo/$2" && g add -A && g commit -qm "$1" && g checkout -q main
}
branch work/s1 work/s1/notes.md
branch work/s2 server/lib/mix/tasks/server.bench_contrast.ex
branch work/s3 stray.txt

mkdir "$tmp/bin"
cat >"$repo/scripts/tlon-cli.sh" <<SH
#!/bin/sh
echo "\$@" >>"$tmp/cli"
SH
cat >"$tmp/bin/mise" <<SH
#!/bin/sh
echo "\$*" >>"$tmp/mise"
case "\$1" in
  run) ! grep -qx "\$2" "$tmp/red" 2>/dev/null || { echo "boom in \$2"; exit 1; } ;;
  exec) case "\$*" in *server.bench_contrast*) echo "bench_contrast steering ok" ;; esac ;;
esac
SH
cat >"$tmp/bin/curl" <<SH
#!/bin/sh
echo "\$@" >"$tmp/curl"
cat "$tmp/scope" 2>/dev/null || exit 22
SH
printf '#!/bin/sh\n' >"$tmp/bin/psql"
chmod +x "$repo/scripts/tlon-cli.sh" "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"

reset() { rm -f "$tmp/cli" "$tmp/mise" "$tmp/curl" "$tmp/red" "$tmp/scope"; }
cli() { cat "$tmp/cli" 2>/dev/null; }
ran() { grep '^run ' "$tmp/mise" 2>/dev/null | paste -sd, -; }
verify() { "$repo/scripts/workline-verify.sh" "$@" 2>&1; }

reset; echo '{"tasks": ["server:check"]}' >"$tmp/scope"
out="$(verify 7 s1 "$repo")"; code=$?
expect "a scoped green runs only the scoped task" "$code:$(ran)" "0:run server:check"
expect "  asks the service with the diff's paths" "$(grep -c 'work/s1/notes.md.*http://svc:1/api/check/scope' "$tmp/curl")" "1"
expect "  records the real exit" "$(cli | grep -c '^record-verify 7 s1 0 mise run server:check')" "1"
expect "  and advances the verify stage" "$(cli | grep -c '^advance 7 verify$')" "1"

reset; echo '{"tasks":["server:check","office:check"]}' >"$tmp/scope"; echo office:check >"$tmp/red"
out="$(verify 7 s1 "$repo")"
expect "a red task still runs the rest" "$(ran)" "run server:check,run office:check"
expect "  records its exit 1" "$(cli | grep -c '^record-verify 7 s1 1 mise run office:check')" "1"
expect "  goes back to build, never advancing" "$(cli | grep -c '^red-verify 7 mise run check failed'):$(cli | grep -c '^advance')" "1:0"

reset
verify 7 s1 "$repo" >/dev/null
expect "no answer from the service runs the full check" "$(ran)" "run check"
reset; echo '{"tasks":["server:check"]}' >"$tmp/scope"
TLON_VERIFY_FULL=1 verify 7 s1 "$repo" >/dev/null
expect "TLON_VERIFY_FULL runs the full check" "$(ran)" "run check"

reset
out="$(WORKLINE_GATE=1 LAND_REF=work/s1 RUN_TASK=server:check verify - s1 "$repo")"; code=$?
expect "a landing gate runs RUN_TASK, records and advances nothing" "$code:$(ran):$(cli)" "0:run server:check:"
echo server:check >"$tmp/red"
out="$(WORKLINE_GATE=1 LAND_REF=work/s1 RUN_TASK=server:check verify - s1 "$repo")"; code=$?
expect "  a red one says what broke on stdout and exits 1" "$code:$(echo "$out" | grep -c 'boom in server:check')" "1:1"

reset
verify 7 s1 "$repo" >/dev/null
expect "no canary A/B when the tree lacks the task" "$(grep -c bench_contrast "$tmp/mise")" "0"
reset
verify 7 s2 "$repo" >/dev/null
expect "the canary A/B runs for a verify of a tree that has it" "$(cli | grep -c '^record-verify 7 s2 0 bench_contrast bench_contrast steering ok')" "1"
expect "  and posts one note" "$(cli | grep -c '^note 7 verify: canary A/B')" "1"
reset
WORKLINE_GATE=1 LAND_REF=work/s2 RUN_TASK=check verify - s2 "$repo" >/dev/null
expect "no canary A/B in a landing gate" "$(grep -c bench_contrast "$tmp/mise")" "0"
reset; echo check >"$tmp/red"
verify 7 s2 "$repo" >/dev/null
expect "no canary A/B after a red gate" "$(grep -c bench_contrast "$tmp/mise")" "0"

reset
out="$(verify 7 s3 "$repo")"; code=$?
expect "a new file at the repo root is sent back, no gate run" "$code:$(ran):$(cli | grep -c '^red-verify 7 work/s3 touches paths')" "1::1"
reset
out="$(verify 7 s1 "$tmp/nowhere")"; code=$?
expect "a missing checkout is noted and refused" "$code:$(cli | grep -c "^note 7 verify can't run: no checkout")" "1:1"
out="$("$repo/scripts/workline-verify.sh" 2>&1)"; code=$?
expect "missing arguments print usage" "$code:$(echo "$out" | grep -c usage)" "1:1"

exit "$bad"
