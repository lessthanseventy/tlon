# Review — 366-release-smoke-serializes-its-build-s @ bd4c6ad

**Verdict: approve.**

Read: the full diff (6 files), scripts/release-smoke.sh around the lock, the CHECKS. Ran scripts/release-smoke.test.sh myself in this worktree: 8/8 ok, exit 0 (.logs/20261027T003819-scripts-release-smoke-test-sh.log). The server's verify gate passed on this head at 06:36:49Z (mise run check, exit 0). No bench_contrast row in CHECKS.

## Spec compliance

1. (a) The heavy step only — deps.get, mix release, ecto.drop/create, migrate — runs under a blocking flock on `<git-common-dir>/tlon-smoke-build.lock`, beside the db lock (line 111). The waiter prints `smoke: waiting for <holder>'s build`. The unlock (line 161) comes before the server start and the hold branch (line 253), so a TLON_SMOKE_HOLD never holds the build lock. ✔
2. (b) `smoke_pool_cause` matches `DBConnection\.ConnectionError|too_many_connections` on the last 20 lines of the log and yields the spec's verdict verbatim; otherwise the old message. ✔
3. Pool size untouched; smoke not in the checks queue. ✔
4. Script test exists and is wired into `check:names` (tasks/server.toml). Covers: two builds serialize, waiter names the holder, SIGKILLed holder frees the lock, both error strings, only the tail counts. ✔

## Lock choreography, checked against the existing locks

- fd 5 is unused elsewhere in the script (it holds 6 reclaim, 7 db, 8 commit, 9 dir). No clobber.
- `fail` exits 1 → EXIT trap → fd 5 closes with the process; a build that dies under the lock blocks no one.
- The sandboxed-refusal path is unchanged: sourcing lib/smoke-build.sh has no side effects, and bd4c6ad fixed the fake-checkout copy lists so the fake smoke no longer errors on the missing lib.

## Non-blocking (follow-ups below)

5. The build subshell and every child it spawns (mix, the migrate node, an epmd it may start on a box with no service up) inherit fd 5. A daemonized child that keeps it would hold the machine-wide lock after the smoke exits, and every later build on the box would wait on `waiting for pid N (sha)'s build`. The existing db/dir locks (fd 7, 9) have the same exposure and have not bitten, so I don't block on it, but the blast radius is now machine-wide. One redirection closes the door: `) 5>&- >>"$log" 2>&1`.
6. `check:names`' description in tasks/server.toml lists each self-test it runs; the new one isn't named.
7. Holder-name race: a waiter that reads the lockfile between the holder's `flock` and its `printf` sees the previous holder (or "someone"). Cosmetic.