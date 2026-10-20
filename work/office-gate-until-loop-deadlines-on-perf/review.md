Approve.

# Review — office-gate-until-loop-deadlines-on-perf @ 01ea570

Goal: office test `until`-loop deadlines read `performance.now()` (monotonic, unaffected by `setSystemTime`) instead of `Date.now()` (frozen by the gate's `OFFICE_TEST_HOUR` clock in `test/clock.ts`), so a missed wait throws `never saw X; pane:…` instead of hanging to bun's 30 s timeout. Issue #42, #470.

## Completeness — good

All 10 office test files with the `until` polling pattern (`while (!ok() && <clock> < deadline)`) now read `performance.now()`:
confirm, entry-keys, hall-hire, margin-tip, persona-reroll, refresh, stalled-need, ticket-back, triage-actions (changed here) + navigation, reply-box (already used `performance.now()`, correctly untouched).

Remaining `Date.now()` calls are wall-clock timestamps for app data / fixtures / mock responses — not polling deadlines, correct to leave:
- `margin-tip.test.ts` mock response `at: Math.floor(Date.now()/1000)`
- `triage-actions.test.ts` fixture `created_at: new Date(Date.now() - 3*3600_000)`
- `reply-box.test.ts` `focusAt = Date.now()` (value sent to the mock `/office/focus` endpoint)
- `sandbox.test.ts`, `souls.test.ts`, `down.test.ts` — freshness assertions / file mtimes / heldAt bounds

## Correctness — sound

`setSystemTime` (bun:test) freezes `Date.now()` and `new Date()` but does NOT affect `performance.now()`, which reads a monotonic clock. So the 25 s (20 s in triage-actions) deadlines elapse in real time even under `OFFICE_TEST_HOUR`, and a missed wait throws its descriptive error with the pane dump instead of hanging to bun's 30 s timeout. The elapsed-time display in the thrown messages (`performance.now() - t0`) stays meaningful.

## Scope — surgical

Test-only; no production code touched. 21 insertions, 21 deletions across 10 files, each a straight `Date.now()` → `performance.now()` swap in the deadline/loop/error sites. The `test/clock.ts` comment (`// freezes Date.now(): a wait's deadline reads performance.now()`) is load-bearing — it states the non-obvious *why* — and earns its place.

## Verify — green

- `mise run office:check` exit 0 — 775 tests across 111 files, 0 fail (OFFICE_TEST_HOUR=3 and =15).
- `mise run check` exit 0 — full gate, verify evidence recorded.

## Non-blocking note (checked, not a finding)

`git status` shows `M server/test/server/release_smoke_script_test.exs`, but `git diff` is empty (content identical to HEAD) — a phantom stat/sandbox artifact, not real uncommitted work. The `TLON_STALE_SCRIPTS_OK` smoke-test fix it tracked is already on origin/main (both `smoke/1` and `flagged` helpers, lines 52 & 71), so it is not on this branch and will not ride into the merge.

## Verdict

Approve. No blocking findings, no follow-ups.