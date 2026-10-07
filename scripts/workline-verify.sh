#!/usr/bin/env bash
# The deterministic verifier (worklines slice 4): run the module gates AND the machine gate
# for a workline, on work/<slug> rebased onto origin/main, record each result as CHECKS evidence (correlation workline:<slug>:verify),
# and advance the stage when everything is green. Run by the service on verify entry (Server.Jobs.Verify) —
# independent of the builder by construction (the builder never runs or reports this).
# A model only enters when a failure needs interpreting; the gates themselves are script.
#
# usage: workline-verify.sh <thread-id> <slug>
set -uo pipefail

tid="${1:?usage: workline-verify.sh <thread-id> <slug> [checkout]}"
slug="${2:?usage: workline-verify.sh <thread-id> <slug> [checkout]}"

root="$(cd "$(dirname "$0")/.." && pwd)"
cli="$root/scripts/tlon-cli.sh"
# The workline's checkout of work/<slug> (the verify job passes it): where the gate borrows its
# installed deps from. The gates themselves run on a throwaway checkout, below.
tree="${3:-$root/.worktrees/$slug}"
# The gate runs as a clean checkout would: none of the service's TLON_* variables (it inherits them
# here — its ports, its real database — and a gate that boots the app would bind 4040 or touch the
# live store), and its own test database, since a coworker running the suite in the same checkout
# shares tlon_test and one run's setup wipes the other's tables (verify runs one at a time).
clean=(env)
for v in $(compgen -e | grep '^TLON_'); do clean+=(-u "$v"); done
clean+=(TLON_TEST_DATABASE=tlon_verify)
if [ ! -d "$tree" ]; then
  "$cli" note "$tid" "verify can't run: no checkout of work/$slug at $tree" || true
  echo "workline-verify: no checkout of work/$slug at $tree" >&2
  exit 1
fi

# One verifier per workline at a time: a duplicate dispatch (bus redelivery, a manual re-run
# racing the auto one) exits quietly instead of double-running gates and double-advancing.
exec 9>"$root/.git/workline-verify-$slug.lock"
flock -n 9 || { echo "verify already running for $slug — skipping"; exit 0; }

# The gates run on the branch as it would land — rebased onto the current origin/main, in a throwaway
# checkout: a fix that reached main after the branch was cut reaches its verify too, and the lead's
# own worktree is never touched.
git -C "$root" fetch -q origin main || { "$cli" note "$tid" "verify can't run: fetching origin/main failed" || true; exit 1; }
fresh="$(mktemp -d -t "tlon-verify-XXXXXX")"
trap 'git -C "$root" worktree remove --force "$fresh" >/dev/null 2>&1; rm -rf "$fresh"' EXIT
git -C "$root" worktree add -q --detach "$fresh" "work/$slug" || exit 1
if ! git -C "$fresh" rebase -q origin/main >/dev/null 2>&1; then
  git -C "$fresh" rebase --abort >/dev/null 2>&1
  "$cli" note "$tid" "verify can't run: work/$slug does not rebase cleanly onto origin/main — rebase it onto origin/main and resolve the conflict, then ask for verify again" || true
  exit 1
fi
# the lead's fetched dep sources, copy-on-write, to save the download — never its _build: compiled
# against the branch's old base, it fails the gate on lock mismatches main has moved past
[ -d "$tree/server/deps" ] && cp -r --reflink=auto "$tree/server/deps" "$fresh/server/deps"
mise trust -q "$fresh" >/dev/null 2>&1
# main's lockfile may have moved past the branch's: fetch what it pins now
(cd "$fresh/server" && "${clean[@]}" MISE_YES=1 mise exec -- mix deps.get >/dev/null 2>&1) || {
  "$cli" note "$tid" "verify can't run: mix deps.get failed on work/$slug rebased onto origin/main" || true
  exit 1
}
tree="$fresh"

# Run one gate, record its REAL exit + tail — evidence, never a self-report. A gate whose
# result could not be recorded is a gate that never ran as far as the stage machine can tell,
# so the failure is surfaced (stderr + the unrecorded flag) instead of dropped on the floor.
unrecorded=0
run_gate() {
  local name="$1"; shift
  local out code
  out=$(cd "$tree" && "${clean[@]}" "$@" 2>&1); code=$?
  if ! "$cli" record-verify "$tid" "$slug" "$code" "$name" "$(printf '%s' "$out" | tail -c 400)"; then
    echo "workline-verify: could not record evidence for '$name' (exit $code) — is the service up?" >&2
    unrecorded=1
  fi
  return $code
}

fail=0
run_gate "mise run check" mise run check || fail=1

if [ "$fail" -eq 0 ] && [ "$unrecorded" -eq 0 ]; then
  "$cli" advance "$tid"
elif [ "$fail" -eq 0 ]; then
  # Green gates with no evidence on record cannot advance: the verify stage owes a CHECKS
  # artifact, and advancing here would be exactly the self-report this script exists to replace.
  msg="verify for workline $slug ran green but its evidence could NOT be recorded — not advancing; re-run once the service is up: mise run workline:verify -- $tid $slug"
  echo "workline-verify: $msg" >&2
  "$cli" note "$tid" "$msg" || true
  exit 1
else
  "$cli" note "$tid" "verify FAILED for workline $slug — see the check_failed evidence (workline:$slug:verify); fix on branch work/$slug, then re-run: mise run workline:verify -- $tid $slug"
fi
