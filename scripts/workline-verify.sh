#!/usr/bin/env bash
# The deterministic verifier (worklines slice 4): run the module gates AND the machine gate
# for a workline, on work/<slug> rebased onto origin/main, record each result as CHECKS evidence (correlation workline:<slug>:verify),
# and advance the stage when everything is green, or send it back to build with the finding when red. Run by the service on verify entry (Server.Jobs.Verify) —
# independent of the builder by construction (the builder never runs or reports this).
# A model only enters when a failure needs interpreting; the gates themselves are script.
#
# usage: workline-verify.sh <thread-id> <slug>
#
# A PR's landing gate (Server.Jobs.Land.gate_pr/4) is the same check in branch mode: WORKLINE_GATE=1,
# thread id `-`, LAND_REF the rebased ref to check out instead of work/<slug>, no stray-path rule and no
# evidence recorded. RUN_TASK there runs that mise task in place of `check` (Server.Jobs.RunTask).
# RULES_ONLY=1 stops after the workline's own rules, before the suite (a verify train's per-car pass).
set -uo pipefail

tid="${1:?usage: workline-verify.sh <thread-id> <slug> [checkout]}"
slug="${2:?usage: workline-verify.sh <thread-id> <slug> [checkout]}"

# the main checkout, even when this copy runs inside a worktree: its scripts and server are the ones
# that answer, and a worktree's own root would resolve the thread's checkout under itself
root="$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
cli="$root/scripts/tlon-cli.sh"
# sourced before the cd below: $0 may be relative
. "$(dirname "$0")/lib/seed-hex.sh"
# WORKLINE_GATE=1: the merge queue's gate (Server.Jobs.Land) — the same check and evidence, but it
# never advances and posts nothing; it says what broke on stdout and the landing tells the thread
note() { if [ -n "${WORKLINE_GATE:-}" ]; then echo "$2"; else "$cli" note "$@"; fi; }
# The workline's checkout of work/<slug> (the verify job passes it): where the gate borrows its
# installed deps from. The gates themselves run on a throwaway checkout, below.
# Never guessed from tlon's own .worktrees/: a thread in another project (menard) has its checkout
# there, and a stale tlon worktree of the same name once got verified in its place, green.
tree="${3:-$("$cli" worktree "$tid" 2>/dev/null)}"
# The gate runs as a clean checkout would: none of the service's TLON_* variables (it inherits them
# here — its ports, its real database — and a gate that boots the app would bind 4040 or touch the
# live store), and a test database of its own per workline and per role: a verify and a landing
# run at once, and coworkers re-run verify by hand, so a shared name lets one run's setup drop the
# database under another ({:error, :already_up}, tables wiped mid-suite).
clean=(env)
for v in $(compgen -e | grep '^TLON_'); do clean+=(-u "$v"); done
role=verify; [ -n "${WORKLINE_GATE:-}" ] && role=land
db="tlon_${role}_$(printf '%s' "$slug" | tr -c 'a-zA-Z0-9' '_' | tr 'A-Z' 'a-z')"
clean+=(TLON_TEST_DATABASE="${db:0:63}")
# how the machine's checks queue names this run: the office's room and rack read "#<id> verify|landing"
label=verify; [ -n "${WORKLINE_GATE:-}" ] && label=landing
clean+=(CHECKS_LABEL="${CHECKS_LABEL:-#$tid $label $slug}")
ref="${LAND_REF:-work/$slug}"
if [ ! -d "$tree" ]; then
  note "$tid" "verify can't run: no checkout of work/$slug at $tree" || true
  echo "workline-verify: no checkout of work/$slug at $tree" >&2
  exit 1
fi

# One verifier per workline at a time: a duplicate dispatch (bus redelivery, a manual re-run
# racing the auto one) exits quietly instead of double-running gates and double-advancing. A
# landing gate waits its turn instead: its exit 0 is a green, and it must not pass on a run it didn't make.
exec 9>"$root/.git/workline-verify-$slug.lock"
if [ -n "${WORKLINE_GATE:-}" ]; then
  flock 9
else
  flock -n 9 || { echo "verify already running for $slug — skipping"; exit 0; }
fi

# The repo the workline lives in is its worktree's — not always tlon's: a menard thread's is menard.
repo="$(cd "$(git -C "$tree" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"

# The gates run on the branch as it would land — rebased onto the current origin/main, in a throwaway
# checkout: a fix that reached main after the branch was cut reaches its verify too, and the lead's
# own worktree is never touched.
"$(dirname "$0")/git-fetch-origin.sh" "$repo" main || { note "$tid" "verify can't run: fetching origin/main failed in $repo" || true; exit 1; }
# a verify SIGKILLed mid-cleanup (a service stop outlasting its timeout) leaves its checkout and the
# repo's worktree entry: sweep any no process is using. This run holds its own by standing in it.
# the throwaway checkouts live under the cache, not TMPDIR (/tmp): a seat's sandbox writes /tmp, and
# every git repo under a write root costs bwrap arguments (its 9000 cap), so a verify's suite of
# seeded repos would overflow the seat that runs it
vroot="${XDG_CACHE_HOME:-$HOME/.cache}/tlon-verify"
mkdir -p "$vroot"
for stale in "$vroot"/*/; do
  stale="${stale%/}"; [ -d "$stale" ] || continue
  pgrep -f "$stale" >/dev/null && continue
  [ -n "$(find /proc/[0-9]*/cwd -maxdepth 0 -lname "$stale*" -print -quit 2>/dev/null)" ] && continue
  rm -rf "$stale"
done
git -C "$repo" worktree prune
fresh="$(mktemp -d -p "$vroot" "XXXXXX")" && cd "$fresh" || exit 1
drop_tree() { git -C "$repo" worktree remove --force "$1" >/dev/null 2>&1; rm -rf "$1"; }
mainwt=""
cleanup() {
  drop_tree "$fresh"
  [ -z "$mainwt" ] || drop_tree "$mainwt"
  git -C "$repo" worktree prune
}
trap cleanup EXIT
git -C "$repo" worktree add -q --detach "$fresh" "$ref" || exit 1
# --no-update-refs: rebase.updateRefs (set on this machine) would move every branch pointing into
# the range — a coworker's work/<slug> not checked out anywhere
if ! git -C "$fresh" rebase -q --no-update-refs origin/main >/dev/null 2>&1; then
  conflicts="$(git -C "$fresh" diff --name-only --diff-filter=U | paste -sd' ' -)"
  git -C "$fresh" rebase --abort >/dev/null 2>&1
  # A conflict is the branch's red, not the environment's fault: recorded as a check_failed, finish/5
  # sends it back to build. Exiting with nothing recorded is retried into a job_failed Need instead.
  if [ -n "${WORKLINE_GATE:-}" ]; then
    note "$tid" "verify can't run: work/$slug does not rebase cleanly onto origin/main — rebase it onto origin/main and resolve the conflict, then ask for verify again" || true
  else
    "$cli" record-verify "$tid" "$slug" 1 rebase "$conflicts" ||
      note "$tid" "verify can't run: work/$slug does not rebase cleanly onto origin/main — rebase it onto origin/main and resolve the conflict, then ask for verify again" || true
  fi
  exit 1
fi

# The paths a workline's diff may not touch (name-status lines on stdin): a new file at the repo
# root, or anything under another workline's work/<slug>/ — its docs belong in its own.
strays() { # slug
  awk -F '\t' -v own="work/$1/" '
    $2 !~ /\// { if ($1 == "A") print $2; next }
    $2 ~ /^work\// && index($2, own) != 1 { print $2 }'
}
# a workline's rule, not a PR's: a PR's branch has no work/<slug>/ of its own
stray=""
[ -n "${LAND_REF:-}" ] || stray="$(git -C "$fresh" diff --name-status --no-renames origin/main HEAD | strays "$slug")"
if [ -n "$stray" ]; then
  finding="work/$slug touches paths outside its own: a workline adds no file at the repo root and writes its docs under work/$slug/ only — move or drop:
$stray"
  if [ -n "${WORKLINE_GATE:-}" ]; then echo "$finding"; exit 1; fi
  "$cli" red-verify "$tid" "$finding" || note "$tid" "verify FAILED for workline $slug — $finding" || true
  exit 1
fi
# RULES_ONLY: a verify train's per-car pass (Server.VerifyTrain) — the workline's own rules, and the
# suite is the train's, run once on the stacked cars
[ -n "${RULES_ONLY:-}" ] && exit 0
mise trust -q "$fresh" >/dev/null 2>&1
# a Hex home of its own
seed_hex_home "${HEX_HOME:-$HOME/.hex}" "$fresh/.hex"
clean+=(HEX_HOME="$fresh/.hex")
# each mix project in the tree (tlon's under server/, menard's at its root): the lead's fetched dep
# sources, copy-on-write, to save the download — never its _build: compiled against the branch's
# old base, it fails the gate on lock mismatches main has moved past — then what main's lock pins now
# -L: a deps dir an older checkout linked into the shared one is copied, not linked, so the gate's
# deps.get writes only this checkout's
copy_deps() { # tree fresh dir
  [ -d "$1/$3/deps" ] && cp -rL --reflink=auto "$1/$3/deps" "$2/$3/deps"
}
for d in server .; do
  [ -f "$fresh/$d/mix.exs" ] || continue
  copy_deps "$tree" "$fresh" "$d"
  (cd "$fresh/$d" && "${clean[@]}" MISE_YES=1 mise exec -- mix deps.get >/dev/null 2>&1) || {
    note "$tid" "verify can't run: mix deps.get failed in $d on work/$slug rebased onto origin/main" || true
    exit 1
  }
done
tree="$fresh"

# Run one gate, record its REAL exit + tail — evidence, never a self-report. A gate whose
# result could not be recorded is a gate that never ran as far as the stage machine can tell,
# so the failure is surfaced (stderr + the unrecorded flag) instead of dropped on the floor.
unrecorded=0
# The failing tests by name (ExUnit's "N) test … (Mod)" + its file:line, bun's "(fail) …" and the
# "error: …" before it that says why, read past mise's "[task] " line prefix): a long suite's last
# 400 bytes hold only its summary, or another task's interleaved compile output, and the lead would
# re-run it to learn what broke.
failures() {
  awk '{ sub(/^\[[^]]*\] /, "") }
       /^ +[0-9]+\) (test|doctest|property) / { sub(/^ +/, ""); h = $0; getline; sub(/^\[[^]]*\] /, ""); sub(/^ +/, ""); print h " — " $0; next }
       /^error: / { e = e $0 "\n"; next }
       /^\(fail\) / { printf "%s", e; e = ""; print }' | cut -c1-160 | iconv -c -f utf-8 -t utf-8 | head -n 10
}
run_gate() {
  local name="$1"; shift
  local out code
  out=$(cd "$tree" && "${clean[@]}" "$@" 2>&1); code=$?
  fails="$(printf '%s\n' "$out" | failures)"
  gate_tail="${fails:+failing:
$fails
…
}$(printf '%s' "$out" | tail -c 400)"
  # the whole of a red gate's output, where a flake can be read to its failing assertion and line;
  # the checkout it ran in is gone on exit
  if [ "$code" -ne 0 ] && mkdir -p "$root/.logs" && printf '%s\n' "$out" >"$root/.logs/verify-$slug.log"; then
    gate_tail="$gate_tail
(the full log: $root/.logs/verify-$slug.log)"
  fi
  if [ "$tid" != - ] && ! "$cli" record-verify "$tid" "$slug" "$code" "$name" "$gate_tail"; then
    echo "workline-verify: could not record evidence for '$name' (exit $code) — is the service up?" >&2
    unrecorded=1
  fi
  return $code
}

fail=0
# RUN_TASK (branch mode, `run_task`): another mise task in place of the full check
task=check; [ -n "${LAND_REF:-}" ] && task="${RUN_TASK:-check}"
run_gate "mise run $task" mise run "$task" || fail=1

# A steering edit earns a canary A/B (#632): the roles it moved benched from origin/main and the
# branch's rebased checkout, each contrast a bench_contrast CHECKS row and one note — evidence for the
# reviewer, never a red. A workline's own verify only, once its gate is green, in a tree that has the
# task (a menard thread's doesn't). Only rows are kept: mix's compile lines share its stdout.
# Main's side is a throwaway worktree of origin/main beside $fresh, as check-main.sh makes — never the
# root checkout, which holds whatever branch the operator has out and is the tree the service reads.
# It is made whenever the step runs: whether the diff is steering is the task's call
# (Server.Workline.Grade.steering/1), not a second classifier here.
# The task clamps itself to 15 minutes and kills each side's process group at its wall
# (Server.Bench.Contrast); the timeout here is a backstop a minute past it, for a VM that hangs
# before its own wall fires.
if [ "$fail" -eq 0 ] && [ -z "${WORKLINE_GATE:-}" ] && [ -f "$fresh/server/lib/mix/tasks/server.bench_contrast.ex" ]; then
  rows="$(mktemp)"
  mainwt="$(mktemp -d -p "$vroot" main-XXXXXX)"
  if git -C "$repo" worktree add -q --detach "$mainwt" origin/main; then
    mise trust -q "$mainwt" >/dev/null 2>&1
    copy_deps "$fresh" "$mainwt" server
    (cd "$mainwt/server" && "${clean[@]}" MISE_YES=1 mise exec -- mix deps.get >/dev/null 2>&1)
    (cd "$fresh/server" && "${clean[@]}" MISE_YES=1 timeout -k 30 960 mise exec -- mix server.bench_contrast --branch "$fresh" --main "$mainwt" >"$rows" 2>/dev/null)
    [ $? -eq 124 ] && echo "bench_contrast error: the canary A/B's VM hung past its wall and was killed" >>"$rows"
  else
    echo "bench_contrast error: no worktree of origin/main for main's side" >>"$rows"
  fi
  drop_tree "$mainwt"; mainwt=""
  contrast="$(grep '^bench_contrast ' "$rows")"
  rm -f "$rows"
  if [ -n "$contrast" ]; then
    while IFS= read -r line; do
      "$cli" record-verify "$tid" "$slug" 0 bench_contrast "$line" || unrecorded=1
    done <<<"$contrast"
    note "$tid" "verify: canary A/B for the steering this branch edits —
$contrast" || true
  fi
fi

if [ -n "${WORKLINE_GATE:-}" ]; then
  [ "$fail" -eq 0 ] && exit 0
  printf '%s\n' "$gate_tail"
  exit 1
elif [ "$fail" -eq 0 ] && [ "$unrecorded" -eq 0 ]; then
  "$cli" advance "$tid" verify
elif [ "$fail" -eq 0 ]; then
  # Green gates with no evidence on record cannot advance: the verify stage owes a CHECKS
  # artifact, and advancing here would be exactly the self-report this script exists to replace.
  msg="verify for workline $slug ran green but its evidence could NOT be recorded — not advancing; re-run once the service is up: mise run workline:verify -- $tid $slug"
  echo "workline-verify: $msg" >&2
  note "$tid" "$msg" || true
  exit 1
else
  # red goes back to build on the same branch, the finding with it; the note only if that can't
  "$cli" red-verify "$tid" "mise run check failed — ${fails:+failing:
$fails
}see the check_failed evidence (workline:$slug:verify)" ||
    note "$tid" "verify FAILED for workline $slug — ${fails:+failing:
$fails
}see the check_failed evidence (workline:$slug:verify); fix it on work/$slug, then call advance_stage: the server runs verify again"
fi
