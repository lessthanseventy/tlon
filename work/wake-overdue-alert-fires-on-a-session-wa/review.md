# verdict: request_changes

Reversing the prior approve. The grader's finding 1 is a real gate-corruption bug I missed last round (I dismissed −1 as "harmless" without tracing a concurrent new submit). Verified against `submitWakes`/`session.end`.

## required to merge

1. **A late-settling abandoned submit drives `pendingSubmits` negative and breaks the gate for the next conversation.** `session.end` resets `pendingSubmits = 0` and `submitting = Promise.resolve()`, but a submit abandoned at `/clear` is still chained on the *old* `submitting` promise. If the host later **rejects** it (not abandons — exactly what #546 has not settled), the orphaned `finally { pendingSubmits-- }` (`mod.ts:258`) fires after the reset: 0 → −1. The next conversation's `submitWakes` does `pendingSubmits++` → 0, so the `drainWakes` gate `if (draining || pendingSubmits > 0) return` is **false during a genuinely-held submit** — `drainWakes` takes the next wake into memory, re-opening the in-memory loss window this change exists to close, for the conversation right after a reject-`/clear`. (The rejected wake itself is recovered via `put_back_wakes` in the `catch`; the bug is the count corruption, which exposes *subsequent* wakes.) Nothing logs it.

   Whether this triggers hinges on #546 (host abandons vs rejects on `/clear`), but the fix is cheap, defensive either way, and sits in lines this change touches.

   Fix: a submit-generation counter — module-level `submitGen`, incremented in `session.end` alongside the resets; `submitWakes` captures `const gen = submitGen` and only decrements `pendingSubmits` in `finally` when `gen === submitGen`, so an orphaned prior-session submit can't touch the current count. Test: held submit → `session.end` → release the abandoned hold (late reject) → new `session.start` + new held submit → advance the clock → assert **no further `take_wakes`** while the new submit is pending (the gate holds), and that releasing the new hold then delivers in order.

## non-blocking follow-ups (carried forward)

1. **#545 (med, held) — a never-completing subagent pins the seat busy.** A subagent that crashes/aborts without `turn.complete` stays in `running` until `session.end`, so `presence_idle` never fires and the `~180 s` refresh claims "waiting on a background agent" indefinitely — the very refresh meant to beat the stale-turn check, so a dead seat looks alive forever. Fix: store each `agentId` with the tick it started and drop entries older than a bound in the poll callback, with a `note()` line; also reset `mainEnded`/`waitTicks` in `session.end`. Test: `turn.start` with agentId, main `turn.complete`, advance past the bound, expect one `presence_idle` and that refreshes stop. (This is the grader's fix 2.)

2. **#546 (med) — prove live.** Launch a citizen, background a subagent, confirm `turn` events carry `agentId` live (so the running-set path engages) and the seat stays off the overdue clock. This also settles whether the host abandons or rejects the held submit on `/clear` — i.e. whether the required fix above is load-bearing or belt-and-suspenders in production.

3. **#548 (low, held, blocked by #545) — `waitTicks` drift.** `waitTicks` is module-level, only incremented, never reset, so a second wait's first refresh fires at `60 − N%60` rather than 60. Non-functional (max gap stays under 180 s against the 600 s clock). Reset on main `turn.start`, with a two-waits test.

4. **(low) — recover the in-flight batch at `session.end`.** The single wake taken *before* the gate engages ("wake one") sits in the in-memory chain during a held submit; on an abandoned `/clear` it is lost (the recovery test asserts `submitted = ["wake two"]`, accepting that loss). `submitWakes` could record the in-flight texts and `put_back_wakes` them in `session.end` before the reset, so a `/clear` doesn't lose a delivered wake. Closes the last residue of #547; an improvement, not a regression — the change already narrows the loss from "all wakes" to "one batch". (The grader's fix 3.)

#545 remains the next build after this lands.