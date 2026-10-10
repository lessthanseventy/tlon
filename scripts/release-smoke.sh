#!/usr/bin/env bash
# The smoke check on a release candidate (pm-and-release design §4, check 2): the candidate built as
# a scratch release in a throwaway worktree, started on a scratch port and database, asked for the
# office at /api/office, and the office TUI driven through a fixed short script against it — then
# all of it torn down. The exit code is the verdict; the last line says why.
#
#   release-smoke.sh [<commit>]     default origin/main
#
# TLON_SMOKE_PORT and TLON_SMOKE_DATABASE name the scratch ones (default: a port picked from the pid,
# and a database named after it, so concurrent smokes never share either); the service's
# 4040 and `tlon` are refused. TLON_SMOKE_URL smokes a server already up there instead: nothing is
# built, started or recorded. A run ends `ran-on: smoke <sha>`, which a scheduled run records.
# TLON_SMOKE_HOLD=1 keeps a passing scratch node up to drive by hand (QA) until this is stopped.
set -uo pipefail

root="$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
port="${TLON_SMOKE_PORT:-$((4100 + $$ % 800))}"
db="${TLON_SMOKE_DATABASE:-tlon_smoke_$port}" url="${TLON_SMOKE_URL:-}"
hold="${TLON_SMOKE_HOLD:-}"
log="$(mktemp -t tlon-smoke-log-XXXXXX)"
fail() { echo "smoke FAILED: $*$([ -s "$log" ] && echo " (the log: $log)")"; exit 1; }

# A schedule runs this from inside the service: its TLON_* (port, database), its RELEASE_* (which
# release a bin/server runs, its tmp, its node) and its systemd INVOCATION_ID (a restart from the
# scratch node would restart the service) must not reach the scratch node.
for v in $(compgen -e | grep -E '^(TLON_|RELEASE_)'); do unset "$v"; done
unset INVOCATION_ID

dir="" node="" sha="" ok="" office="$root"
cleanup() {
  if [ -n "$node" ]; then kill "$node" 2>/dev/null; wait "$node" 2>/dev/null; fi
  if [ -n "$dir" ]; then
    # the 2 GB build goes before the slow drop, so a SIGKILL mid-cleanup leaves less in RAM-backed /tmp
    git -C "$root" worktree remove --force "$dir" >/dev/null 2>&1
    rm -rf "$dir"
    psql -h "${PGHOST:-/run/postgresql}" -d postgres -qc "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)" >>"$log" 2>&1
  fi
  # a failure's log is kept for reading, unless there is nothing in it
  if [ -n "$ok" ] || [ ! -s "$log" ]; then rm -f "$log"; fi
}
trap cleanup EXIT
trap 'exit 143' TERM INT

if [ -z "$url" ]; then
  [ "$port" != 4040 ] || fail "4040 is the service's port"
  [ "$db" != tlon ] || fail "tlon is the service's database"
  url="http://127.0.0.1:$port"
  curl -s -m 2 -o /dev/null "$url" && fail "something already answers on $port"

  "$(dirname "$0")/git-fetch-origin.sh" "$root" || fail "can't fetch origin"
  sha="$(git -C "$root" rev-parse -q --verify "${1:-origin/main}^{commit}")" || fail "no commit ${1:-origin/main}"
  echo "smoke: ${sha:0:7} on :$port, database $db"

  # a smoke SIGKILLed (a service restart, server:stop) never ran its cleanup: sweep any build
  # no process is using before making another
  for stale in "${TMPDIR:-/tmp}"/tlon-smoke-*/; do
    stale="${stale%/}"; [ -d "$stale/server" ] || continue
    # in use: named in a command line (the node, the drive) or the working directory of one (mix)
    pgrep -f "$stale/" >/dev/null && continue
    [ -n "$(find /proc/[0-9]*/cwd -maxdepth 0 -lname "$stale*" -print -quit 2>/dev/null)" ] && continue
    git -C "$root" worktree remove --force "$stale" >/dev/null 2>&1; rm -rf "$stale"
  done
  git -C "$root" worktree prune
  dir="$(mktemp -d -t tlon-smoke-XXXXXX)"
  git -C "$root" worktree add -q --detach "$dir" "$sha" || fail "can't check out ${sha:0:7}"
  office="$dir"
  mise trust -q "$dir" >/dev/null 2>&1
  # the drive runs the candidate's own office-drive.sh under a throwaway XDG_STATE_HOME, which hides the trust above
  export MISE_TRUSTED_CONFIG_PATHS="$dir"
  [ -d "$root/server/deps" ] && cp -a --reflink=auto "$root/server/deps" "$dir/server/"
  [ -d "$root/office/node_modules" ] && cp -a --reflink=auto "$root/office/node_modules" "$dir/office/"
  (cd "$dir/office" && bun install --frozen-lockfile >/dev/null 2>&1) || fail "bun install failed"

  (
    set -e
    cd "$dir/server"
    export MIX_ENV=prod TLON_DATABASE="$db"
    mix deps.get
    mix release --overwrite
    mix ecto.drop --quiet --force --force-drop
    mix ecto.create --quiet
    _build/prod/rel/server/bin/server eval 'Server.Release.migrate()'
  ) >>"$log" 2>&1 || { tail -n 20 "$log"; fail "the build or the migration of ${sha:0:7} failed"; }

  # MCP is what serves /api; everything that would talk to a model, the weather or a pane stays off
  TLON_NODE="tlon-smoke-$port@127.0.0.1" TLON_DATABASE="$db" TLON_START_MCP=1 TLON_MCP_PORT="$port" \
    TLON_BANTER=0 TLON_WEATHER=0 TLON_CALENDAR=0 \
    "$dir/server/_build/prod/rel/server/bin/server" start >>"$log" 2>&1 &
  node=$!
  for _ in $(seq 90); do
    curl -s -m 2 -o /dev/null "$url/api/office" && break
    kill -0 "$node" 2>/dev/null || { tail -n 20 "$log"; fail "the scratch node of ${sha:0:7} exited at boot"; }
    sleep 1
  done
fi

body="$(mktemp)"
code="$(curl -s -m 10 -o "$body" -w '%{http_code}' "$url/api/office")"
[ "$code" = 200 ] || { rm -f "$body"; fail "/api/office answered ${code:-nothing}"; }
jq -e '(.roster | type) == "array" and (.threads | type) == "array" and (.workspaces | length) > 0' "$body" >/dev/null ||
  { rm -f "$body"; fail "/api/office answered 200 without the office's shape (roster, threads, workspaces)"; }
ws="$(jq -r '.workspaces[0].id' "$body")"
rm -f "$body"
echo "smoke: /api/office ✓"

title="release smoke $$"
tid="$(curl -s -m 10 -X POST -H 'content-type: application/json' \
  -d "{\"workspace_id\": $ws, \"body\": \"$title\"}" "$url/api/threads" | jq -r '.id // empty')"
[ -n "$tid" ] || fail "POST /api/threads opened no thread"

# open · a thread (found by its title) · a card (the crew) · R (no reload: TUI and server agree)
screens="$(TLON_URL="$url" OFFICE_TAIL=60 OFFICE_WAIT=2 "$office/scripts/office-drive.sh" \
  "." "/" "'$title'" "Enter" "Escape" "c" "Escape" "R" 2>&1)"
after() { printf '%s\n' "$screens" | awk -v s="=== after: $1" '$0 == s {on = 1; next} /^=== / {on = 0} on'; }
printf '%s\n' "$screens" >>"$log"
expect() { case "$(after "$1")" in *"$2"*) ;; *) fail "the office after '$1' doesn't show '$2'" ;; esac; }
expect "." "HOME"
expect "Enter" "#$tid  $title"
expect "c" "CREW"
expect "R" "HOME"
case "$(after "R")" in *"R reloads"*) fail "the office offers a reload against its own server" ;; esac
echo "smoke: the office drove ✓"

ok=1
echo "smoke passed${sha:+ on ${sha:0:7}}"
[ -n "$sha" ] && echo "ran-on: smoke $sha"
if [ -n "$hold" ] && [ -n "$node" ]; then
  echo "smoke: holding $url up — TLON_URL=$url mise run office:drive -- <keys>; stop this to tear it down"
  trap 'exit 0' TERM INT
  wait "$node"
fi
exit 0
