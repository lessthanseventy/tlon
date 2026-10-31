# Review — the-nightly-smoke-goes-red-when-another @ 904c981

**Verdict: request_changes** — one line in the new test; the script change itself is right.

Read: the diff 4234e3c..904c981 (5286f1f, 7b8e520, 904c981): `scripts/release-smoke.sh`, `server/test/server/release_smoke_script_test.exs`, `work/…/pr.md`. Spec (ticket #603, the opening) is met on every point: a live holder is waited on with `flock -w`, the bound is finite and 0 keeps the old refusal, expiry says `timed out waiting for (<holder>) after Ns`, the run then takes the lock, writes its own record and smokes (so its own ran-on), and the gone-holder reclaim is the old block verbatim under `if [ -z "$waited" ]`. The `TLON_SMOKE_LOCK_WAIT` read at :32 happens before the `TLON_*` unset at :41, so a schedule's own env can set it.

**The 1200 s default against Server.Schedules** (tertius's ask): `@script_timeout_ms` is 30 min from the script's START; only a line containing `checks queue:` moves the deadline (schedules.ex:302-326), ordinary output does not. So the wait and the whole smoke share one 30-minute budget: 1200 s leaves 600 s for fetch, worktree, bun install, the machine-wide build lock (`smoke_build_lock`'s `flock 5` is unbounded and prints no queue word either), build, boot and drive. The hand run in the ticket took about 5 min end to end (03:26:55 → 03:31:43), so the margin is roughly one smoke. Inside the limit; not blocking. Wording: the header comment (:14) and pr.md say "30 minutes of silence" — it is a 30-minute total clock, not a silence clock.

## 1. Blocking — the "waited for, then smoked" test also passes when the wait expires (test :235-254)

The witness statement:

    refute out =~ "already being smoked"
    assert out =~ "waiting for"
    assert out =~ ~r/smoke: [0-9a-f]{7} on :#{ctx.port}/

All three hold on a TIMEOUT: `smoke: <sha> on :<port>` is printed at release-smoke.sh:73, before the lock is even opened at :77; the expiry message `timed out waiting for (…)` contains "waiting for"; and the exit code is dropped (`{out, _}`). Reproduced with the branch's script, a holder sleeping 15 s and `TLON_SMOKE_LOCK_WAIT=1`:

    smoke: e1978fe on :4599, database tlon_smoke_x
    smoke: waiting for e1978fe to be smoked by (pid 16 on http://127.0.0.1:4777), up to 1s
    smoke FAILED: e1978fe: timed out waiting for (pid 16 on http://127.0.0.1:4777) after 1s

Every assertion of :251-253 is satisfied by that output. The sibling reclaim test (:276) has no such hole: its only failure after its message says "already being smoked", which it refutes. This test is the ticket's named deliverable ("the second run waits and gets past the lock"); as written it stays green if the wait regresses to always expiring.

Fix: prove the lock was taken, the way the truncation test at :303 does — the record at the path is this run's.

    @@ server/test/server/release_smoke_script_test.exs @@ test "a live holder that lets go within the wait bound …"
       refute out =~ "already being smoked"
       assert out =~ "waiting for"
    -  assert out =~ ~r/smoke: [0-9a-f]{7} on :#{ctx.port}/
    +  refute out =~ "timed out"
    +  # the record at the path is this run's: it came out of the wait with the lock, not out of time
    +  assert File.read!(lock) =~ ~r/\Apid \d+ on http:\/\/127\.0\.0\.1:#{ctx.port}\n\z/

## 2. Not blocking — a window the waited path has that a fresh run on main does not (release-smoke.sh:97-101, :125)

Between `flock -w` returning and `: >"$lock"` at :125, the file at the path still carries the OLD holder's record and mtime. A third run arriving then reads a dead pid, a dead url and, if the holder ran past 20 min (a hold, a slow build), an mtime past `-mmin +20` → "gone" → reclaims and builds beside this one. A fresh run's file has a fresh mtime, so main never has it. The window is a stat and a fork; same family as the races the script already names. Noted, nothing asked.

## Checks
- `menard run test --in server test/server/release_smoke_script_test.exs:235` → `{"ok":true,"tests":1,"failed":0}` (this session).
- CHECKS: `mise run check` green on the branch at verify (03:53:42Z). No `bench_contrast` row: no persona edited, nothing to contrast.
- Commit trailers: `Co-Authored-By: claude-sonnet-5-5`, `Tlon-Author: emma`, `Tlon-Model` on all three.

@emma one line, then back through verify.