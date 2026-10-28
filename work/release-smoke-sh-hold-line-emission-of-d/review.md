# Review — release-smoke-sh-hold-line-emission-of-d (#440)

**Verdict: approve.** Commit 0db473f, 4 files, +24/−3. Both gaps the ticket named are closed, each by a test that pins the behaviour.

## Spec compliance

1. **Proof — hold/5's dir capture is now exercised end to end.** The job test's `@stub` prints the real hold line, `smoke: holding http://127.0.0.1:4999 up (dir /tmp/tlon-smoke/Ab1) — …`, and "the job posts the held url on the thread, and stop tears it down" asserts `Smoke.held(t.id).meta["dir"] == "/tmp/tlon-smoke/Ab1"` before `stop`. Exactly the grader's fix.
2. **Proof — the script's emission is pinned.** `release_smoke_script_test.exs:424` goes from `=~ "smoke: holding"` to `=~ ~r/smoke: holding http\S+ up \(dir \S+\)/`, which is stricter than the ticket's `(dir ` and matches the job's `hold_line/0` shape, so a drift in `release-smoke.sh:253` fails here rather than silently dropping `dir`.
3. **Detectability — the fallback is visible.** `drive/3` returns `@old_hold_note <> out` when `meta["dir"]` is nil (`smoke.ex:119`); the note is the first line of the drive's output, where the `drive_smoke` tool hands it to the reader. The new test inserts a hold with a url and no dir and asserts the note. The builder says it was red first; I did not re-run it red.

## Verified

- `menard run test --in server test/server/jobs/smoke_test.exs` — 17 tests, 0 failures.
- `menard run test --in server test/server/release_smoke_script_test.exs` — 27 tests, 0 failures.
- Together 44, matching pr.md. Verify's full `mise run check` passed on this sha (CHECKS 01:14:39Z). No `bench_contrast` row in CHECKS.

## Not blocking

See follow-ups: the fallback test drives the checkout's real `office-drive.sh` (tmux + bun + the TUI against a dead port) inside the unit suite, and there is a stray blank line between `@spec drive` and `def drive`.