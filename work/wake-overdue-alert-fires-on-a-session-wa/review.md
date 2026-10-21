# verdict: approve

Re-review of the re-build (ef9bd0a..2580039). The one required fix from the prior round landed exactly, and is RED-then-GREEN proven. Verify's full gate passed (exit 0).

## required to merge — fixed

1. **`session.end` resets the submit-lifecycle state.** `mod.ts:569` now resets `pendingSubmits = 0` and `submitting = Promise.resolve()` alongside `running.clear()`, with a load-bearing comment. Both halves are necessary:
   - `pendingSubmits = 0` reopens the `drainWakes` gate (`if (draining || pendingSubmits > 0) return`). The new test's RED was exactly this: 1 `take_wakes`, expected 2 — the gate stayed shut because the abandoned submit's `finally` never ran.
   - `submitting = Promise.resolve()` breaks the `submitting = submitting.then(...)` chain (`submitWakes`). Without it, a later `submitWakes` would chain onto the abandoned submit's never-settling promise and "wake two" would be taken but never delivered. The GREEN `world.submitted = ["wake two"]` confirms the chain recovers.

   The recovery test ("a submit the host abandons at session.end does not stop the next conversation taking wakes") proves end-to-end: held submit → `session.end` → second poll takes "wake two" (`take_wakes` length 2) → release → delivers. The defensive note from the prior round holds: if the host rejects rather than abandons, the orphaned `finally` decrements to −1, harmless under the `> 0` gate; no race, since an abandoning host never later resolves.

   `mise run adapters:claude-code:mod` → 46 pass, 0 fail. Diff is surgical: the test (+20 lines) and the two-line reset + comment. ✓

## non-blocking follow-ups (carried forward — all filed, held)

1. **#545 (med, held) — a never-completing subagent pins the seat busy.** A subagent that crashes or aborts without `turn.complete` stays in `running` until `session.end`, so `presence_idle` never fires and the heartbeat runs forever. Fix: store each `agentId` with the tick it started and drop entries older than a bound in the poll callback, with a `note()` line; also reset `mainEnded`/`waitTicks` in `session.end`. Test: `turn.start` with agentId, main `turn.complete`, advance past the bound, expect one `presence_idle`.

2. **#546 (med) — prove live.** Launch a citizen, background a subagent, confirm `turn` events carry `agentId` live (so the running-set path engages) and the seat stays off the overdue clock. This also settles whether the host abandons or rejects the held submit on `/clear` — i.e. whether the `session.end` reset is load-bearing or belt-and-suspenders in production.

3. **#548 (low, held, blocked by #545) — `waitTicks` drift.** `waitTicks` is module-level, only incremented, never reset, so a second wait's first refresh fires at `60 − N%60` rather than 60. Non-functional (max gap stays under 180 s against the 600 s clock). Reset on main `turn.start`, with a two-waits test.

#545 is the next build after this lands.