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
# TLON_SMOKE_HOLD=1 keeps a passing scratch node up to drive by hand (QA) until this is stopped, or
# until TLON_SMOKE_HOLD_TTL seconds pass (default 7200): a forgotten hold would hold its port and
# database for good.
set -uo pipefail

root="$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
port="${TLON_SMOKE_PORT:-$((4100 + $$ % 800))}"
db="${TLON_SMOKE_DATABASE:-tlon_smoke_$port}" url="${TLON_SMOKE_URL:-}"
hold="${TLON_SMOKE_HOLD:-}" ttl="${TLON_SMOKE_HOLD_TTL:-7200}"
log="$(mktemp -t tlon-smoke-log-XXXXXX)"
fail() { echo "smoke FAILED: $*$([ -s "$log" ] && echo " (the log: $log)")"; exit 1; }

# A schedule runs this from inside the service: its TLON_* (port, database), its RELEASE_* (which
# release a bin/server runs, its tmp, its node) and its systemd INVOCATION_ID (a restart from the
# scratch node would restart the service) must not reach the scratch node.
for v in $(compgen -e | grep -E '^(TLON_|RELEASE_)'); do unset "$v"; done
unset INVOCATION_ID

dir="" node="" sha="" ok="" office="$root" dblock=""
cleanup() {
  if [ -n "$node" ]; then kill "$node" 2>/dev/null; wait "$node" 2>/dev/null; fi
  if [ -n "$dir" ]; then
    # the 2 GB build goes before the slow drop, so a SIGKILL mid-cleanup leaves less in RAM-backed /tmp
    git -C "$root" worktree remove --force "$dir" >/dev/null 2>&1
    rm -rf "$dir" "$dir.lock"
    psql -h "${PGHOST:-/run/postgresql}" -d postgres -qc "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)" >>"$log" 2>&1
  fi
  [ -n "$dblock" ] && rm -f "$dblock"
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

  # a local ref (work/<slug>) is already in the shared .git: only origin/* needs the fetch
  if ! "$(dirname "$0")/git-fetch-origin.sh" "$root"; then
    git -C "$root" show-ref -q --verify "refs/heads/${1:-}" || fail "can't fetch origin"
    echo "smoke: warning: can't fetch origin; smoking the local ${1}"
  fi
  sha="$(git -C "$root" rev-parse -q --verify "${1:-origin/main}^{commit}")" || fail "no commit ${1:-origin/main}"
  echo "smoke: ${sha:0:7} on :$port, database $db"
  # one smoke per commit: a retry while one runs (or holds) would stack another 2 GB build in /tmp.
  # The lock is held by this run alone (not the node, whose daemons would outlive it); its text says which run that is.
  lock="${TMPDIR:-/tmp}/tlon-smoke-commit-$sha.lock"
  exec 8<>"$lock"
  if ! flock -n 8; then
    holder="$(head -n 1 <&8)"
    # The lock says someone holds it, not that anyone is there: a holder in another sandbox's pid
    # namespace has a pid this one can't see, and one that was killed can leave the lock with a process
    # that never ran for it. The holder is real if its pid lives, its url answers, or its record is too
    # young to be a build that has finished; otherwise take the lock over on a file of its own.
    hpid="$(printf '%s' "$holder" | sed -n 's/^pid \([0-9]*\) .*/\1/p')"
    hurl="$(printf '%s' "$holder" | sed -n 's/.* on \(http[^ ]*\)$/\1/p')"
    if { [ -n "$hpid" ] && kill -0 "$hpid" 2>/dev/null; } ||
      { [ -n "$hurl" ] && curl -s -m 2 -o /dev/null "$hurl/api/office"; } ||
      [ -z "$(find "$lock" -maxdepth 0 -mmin +20)" ]; then
      fail "${sha:0:7} is already being smoked ($holder): drive or stop that one"
    fi
    echo "smoke: reclaiming the lock on ${sha:0:7} from a holder that is gone ($holder)"
    exec 8>&-
    rm -f "$lock"
    exec 8<>"$lock"
    flock -n 8 || fail "${sha:0:7} is already being smoked (a run took the lock as this one reclaimed it)"
  fi
  # truncated, so a shorter record leaves no tail of the last run's
  : >"$lock"
  echo "pid $$ on $url" >&8
  # the database's: a sweep drops a tlon_smoke_* database only while nobody holds it (smoke-sweep.sh)
  dblock="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)/tlon-smoke-db-$db.lock"
  exec 7>"$dblock"
  flock -n 7 || { dblock=""; fail "database $db is another smoke's"; }

  # a sandboxed Bash can't open Postgres's unix socket (:eperm), and the build would only die of it
  # minutes later, at a migration's pool timeout
  pgerr="$(psql -h "${PGHOST:-/run/postgresql}" -d postgres -XAtqc 'select 1' 2>&1)" ||
    fail "can't reach Postgres at ${PGHOST:-/run/postgresql} (${pgerr//$'\n'/ }) — in a sandboxed Bash, run release:smoke unsandboxed"
  # a smoke SIGKILLed (a service restart, server:stop) never ran its cleanup: sweep the builds no
  # run holds before making another
  "$(dirname "$0")/smoke-sweep.sh" "$root"
  # under tlon-smoke/, out of reach of the sweep in a checkout from before the lock: its
  # tlon-smoke-*/ takes every build no process names in a command line, live ones too
  mkdir -p "${TMPDIR:-/tmp}/tlon-smoke"
  dir="$(mktemp -d "${TMPDIR:-/tmp}/tlon-smoke/XXXXXX")"
  # held until this run and everything it started exits: the sweep's sign that the build is live.
  # Taken before the checkout, as the sweep skips a dir with no server/ in it yet
  exec 9>"$dir.lock"
  flock -n 9 || fail "can't lock $dir"
  git -C "$root" worktree add -q --detach "$dir" "$sha" || fail "can't check out ${sha:0:7}"
  office="$dir"
  mise trust -q "$dir" >/dev/null 2>&1
  # a Hex home of its own (scripts/lib/seed-hex.sh)
  . "$(dirname "$0")/lib/seed-hex.sh"
  seed_hex_home "${HEX_HOME:-$HOME/.hex}" "$dir/.hex"
  export HEX_HOME="$dir/.hex"
  # the drive runs the candidate's own office-drive.sh under a throwaway XDG_STATE_HOME, which hides the trust above
  export MISE_TRUSTED_CONFIG_PATHS="$dir"
  [ -d "$root/server/deps" ] && cp -a --reflink=auto "$root/server/deps" "$dir/server/"
  [ -d "$root/office/node_modules" ] && cp -a --reflink=auto "$root/office/node_modules" "$dir/office/"
  (cd "$dir/office" && bun install --frozen-lockfile >/dev/null 2>&1) || fail "bun install failed"

  # chained with &&, not set -e: a subshell tested by `||` ignores set -e, and a failed build
  # would go on to the steps after it
  (
    cd "$dir/server" &&
      export MIX_ENV=prod TLON_DATABASE="$db" &&
      mix deps.get &&
      mix release --overwrite &&
      mix ecto.drop --quiet --force --force-drop &&
      mix ecto.create --quiet &&
      _build/prod/rel/server/bin/server eval 'Server.Release.migrate()'
  ) >>"$log" 2>&1 || { tail -n 20 "$log"; fail "the build or the migration of ${sha:0:7} failed"; }

  # MCP is what serves /api; everything that would talk to a model, the weather or a pane stays off
  TLON_NODE="tlon-smoke-$port@127.0.0.1" TLON_DATABASE="$db" TLON_START_MCP=1 TLON_MCP_PORT="$port" \
    TLON_BANTER=0 TLON_WEATHER=0 TLON_CALENDAR=0 \
    "$dir/server/_build/prod/rel/server/bin/server" start >>"$log" 2>&1 8>&- &
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
# the workspace the TUI opens on (one named machine, as the boot makes it), named in its header
home="$(jq -r '[.workspaces[] | select(.name | ascii_downcase == "machine")][0].name // empty' "$body")"
rm -f "$body"
echo "smoke: /api/office ✓"
[ -n "$home" ] || echo "smoke: no wait for the office (no machine workspace)"

title="release smoke $$"
tid="$(curl -s -m 10 -X POST -H 'content-type: application/json' \
  -d "{\"workspace_id\": $ws, \"body\": \"$title\"}" "$url/api/threads" | jq -r '.id // empty')"
[ -n "$tid" ] || fail "POST /api/threads opened no thread"

# open · a thread (found by its title) · a card (the crew) · R (no reload: TUI and server agree)
# a thread opens with its reply box focused: the first Escape leaves the box, the second the card
# the finder lists only what the TUI's snapshot holds: wait for it (the header names the workspace)
# before `/`, where the candidate's drive can wait at all
loaded=()
[ -n "$home" ] && grep -q 'wait:\*' "$office/scripts/office-drive.sh" && loaded=("wait:‹ $home ›")
screens="$(TLON_URL="$url" OFFICE_TAIL=60 OFFICE_WAIT=2 "$office/scripts/office-drive.sh" \
  "." "${loaded[@]}" "/" "'$title'" "Enter" "Escape" "Escape" "c" "Escape" "R" 2>&1)"
after() { printf '%s\n' "$screens" | awk -v s="=== after: $1" '$0 == s {on = 1; next} /^=== / {on = 0} on'; }
printf '%s\n' "$screens" >>"$log"
expect() { case "$(after "$1")" in *"$2"*) ;; *) fail "the office after '$1' doesn't show '$2'" ;; esac; }
expect "." "HOME"
expect "Enter" "#$tid  $title"
expect "c" "CREW"
expect "R" "HOME"
case "$(after "R")" in *"R reloads"*) fail "the office offers a reload against its own server" ;; esac
echo "smoke: the office drove ✓"

# the wide room (the door, the bathroom, Argos) is reachable headless: its labels are on screen. A candidate whose
# drive predates OFFICE_WIDE only has the rail room.
if grep -q OFFICE_WIDE "$office/scripts/office-drive.sh"; then
  wide_screen="$(TLON_URL="$url" OFFICE_WIDE=1 OFFICE_TEXT=1 "$office/scripts/office-drive.sh" "wait:no signal" 2>&1)"
  printf '%s\n' "$wide_screen" >>"$log"
  case "$(printf '%s\n' "$wide_screen" | grep -v '^===')" in *"no signal"*) ;; *) fail "the wide room didn't draw under OFFICE_WIDE: no stereo label (only the wide room draws it)" ;; esac
  echo "smoke: the wide room drove ✓"
fi

ok=1
echo "smoke passed${sha:+ on ${sha:0:7}}"
[ -n "$sha" ] && echo "ran-on: smoke $sha"
if [ -n "$hold" ] && [ -n "$node" ]; then
  echo "smoke: holding $url up — TLON_URL=$url mise run office:drive -- <keys>; stop this to tear it down"
  trap 'exit 0' TERM INT
  for ((left = ttl; left > 0; left--)); do
    kill -0 "$node" 2>/dev/null || exit 0
    sleep 1
  done
  echo "smoke: the hold of $url expired after ${ttl}s; tearing it down"
fi
exit 0
