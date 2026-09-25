#!/usr/bin/env bash
# The deterministic verifier (worklines slice 4): run the module gates AND the machine gate
# for a workline, record each result as CHECKS evidence (correlation workline:<slug>:verify),
# and advance the stage when everything is green. Driven by the COCKPIT on verify entry —
# independent of the builder by construction (the builder never runs or reports this).
# A model only enters when a failure needs interpreting; the gates themselves are script.
#
# usage: workline-verify.sh <thread-id> <slug>
set -uo pipefail

tid="${1:?usage: workline-verify.sh <thread-id> <slug>}"
slug="${2:?usage: workline-verify.sh <thread-id> <slug>}"

root="$(cd "$(dirname "$0")/.." && pwd)"
cli="$root/scripts/tlon-cli.sh"

# One verifier per workline at a time: a duplicate dispatch (bus redelivery, a manual re-run
# racing the auto one) exits quietly instead of double-running gates and double-advancing.
exec 9>"$root/.git/workline-verify-$slug.lock"
flock -n 9 || { echo "verify already running for $slug — skipping"; exit 0; }

# Run one gate, record its REAL exit + tail — evidence, never a self-report. A gate whose
# result could not be recorded is a gate that never ran as far as the stage machine can tell,
# so the failure is surfaced (stderr + the unrecorded flag) instead of dropped on the floor.
unrecorded=0
run_gate() {
  local name="$1"; shift
  local out code
  out=$(cd "$root" && "$@" 2>&1); code=$?
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
  "$cli" post "$tid" "$msg" || true
  exit 1
else
  "$cli" post "$tid" "verify FAILED for workline $slug — see the check_failed evidence (workline:$slug:verify); fix on branch work/$slug, then re-run: mise run workline:verify -- $tid $slug"
fi
