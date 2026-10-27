# Review — 366-release-smoke-serializes-its-build-s @ 85bef10

**Verdict: approve.** Both findings from my review at bd4c6ad are fixed in 70c7042, and the manual drift 70c7042 introduced is regenerated in 85bef10. The server's full `mise run check` passed on this head at 06:59:33Z.

Delta since my last verdict (`git diff 41073ea..85bef10 -- . ':!work/…'`): lib/smoke-build.sh gains `smoke_isolated() { ( "$@" ) 5>&-; }`; release-smoke.sh moves the build chain into `build_steps()` and runs it as `smoke_isolated build_steps >>"$log" 2>&1 || { … }`; release-smoke.test.sh gains the leaver case; tasks/server.toml's check:names description names the new test; docs/manual/tasks.md regenerated.

## 1. Finding 1 (children inherit the lock fd) — fixed, and the test is a real red/green

The subshell `( "$@" ) 5>&-` closes fd 5 before `build_steps` and anything it spawns runs, so only the parent shell holds the flock; `smoke_build_unlock` still follows at the call site, before the server start and the hold branch, as before.

Checked, not eyeballed:
- `scripts/cap.sh scripts/release-smoke.test.sh` on this head: 9/9 ok, exit 0.
- The same test against a copy of the lib with `5>&-` removed from `smoke_isolated`, run under bash: `FAIL a build's leftover child does not keep the lock: got [] want [got]`, exit 1. The case goes red without the fix. (Under zsh the orphan does not inherit the fd, so a zsh harness passes either way; the script is bash, so this is not a finding.)

## 2. Finding 2 (check:names description) — fixed

The description now reads "…checks-queue.sh runs waiters first come first served, and release-smoke.sh builds one at a time machine-wide and names a Postgres pool failure"; the run line already carried release-smoke.test.sh since 960e11c. `scripts/manual-gen.sh --check` exit 0 is on the brief (06:51:25Z).

## 3. The `||` / `set -e` seam survives the refactor

`smoke_isolated build_steps … || {` is still an OR list, so `set -e` stays off inside the subshell and the `&&` chain in `build_steps` is what stops a failed step; the comment above it still describes what runs. `cd` and `export MIX_ENV/TLON_DATABASE` stay inside the subshell as before.

## Unchanged from the last round

Spec (a) and (b) met; fd 5 collides with none of 6/7/8/9; `fail` exits so a dead build frees the lock; the fake-checkout copy lists carry lib/smoke-build.sh.

Cosmetic, no action: the leaver case's `sleep 30` outlives the test (its EXIT trap kills `jobs -p`, and the sleep is a subshell's grandchild), with stdout and stderr on /dev/null so nothing waits on it; the full gate passed with it.

No bench_contrast row in CHECKS.