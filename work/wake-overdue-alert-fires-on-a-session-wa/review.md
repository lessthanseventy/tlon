# verdict: request_changes

Re-review of the re-build (bbd1c66..765e7c2). The prior round's four required items all landed and I re-ran the suite: `mise run adapters:claude-code:mod` → 45 pass, 0 fail.

- `pendingSubmits` counter + `drainWakes` early-return while a submit is pending — wakes behind a held submit stay on the server, at most one taken batch in memory. ✓
- The hung-submit test re-specified: first wake taken + submitted (held); a second arriving during the hold is NOT taken (stays on the server); release → next poll takes it; both deliver in order. ✓
- `session.end`-before-release case: a wake that arrived during the held submit survives (never taken, no `put_back_wakes`). ✓
- `presence_thinking` test: a subagent `turn.start` declares none; the main turn's stands. pr.md states the choice. ✓
- `STALE_REFRESH_TICKS` comment (~180 s, under the 600 s stale-turn clock). ✓

One new required fix the prior round missed.

## required to merge

1. **`session.end` must reset the submit-lifecycle state.** `pendingSubmits` and `submitting` are module-level; `session.end` clears `running`, `briefed`, `captured` but not them (mod.ts:569). If a held submit is abandoned by the host at `/clear` — the host never resolves or rejects `$.prompt.submit` for the cleared conversation — `pendingSubmits` stays > 0 and the next conversation's `drainWakes` returns early forever (mod.ts:268): **the mod silently stops taking wakes.** This is a new failure mode introduced by the `pendingSubmits` gate — before it, `drainWakes` only checked `draining`, so a hung chain didn't block taking. The survival test proves the wake stays on the server across `session.end`; it does not prove the *next* session can take it.

   Whether the host abandons vs. rejects on `/clear` is exactly what #546 has not verified, so the leak is unconfirmed in production — but the defensive fix is safe either way: if the host rejects, the orphaned `finally` decrements once (0 → −1, harmless; the gate is `> 0`); if it abandons, the `finally` never runs and the reset is clean. No race: a host that abandons never later resolves, so an orphaned `finally` cannot overlap a new session's submit.

   Fix: in `session.end`, alongside `running.clear()`, reset `pendingSubmits = 0` and `submitting = Promise.resolve()`. Add a test: after the held-submit `session.end`, start a new session, advance the clock, and assert the next wake is taken (`take_wakes` count increments) — proving the gate recovers.

## non-blocking follow-ups (carried forward — all filed, held)

1. **#545 (med, held) — a never-completing subagent pins the seat busy.** A subagent that crashes or aborts without `turn.complete` stays in `running` until `session.end`, so `presence_idle` never fires and the heartbeat runs forever. Fix: store each `agentId` with the tick it started and drop entries older than a bound in the poll callback, with a `note()` line; also reset `mainEnded`/`waitTicks` in `session.end`. Test: `turn.start` with agentId, main `turn.complete`, advance past the bound, expect one `presence_idle`.

2. **#546 (med) — prove live.** Launch a citizen, background a subagent, confirm `turn` events carry `agentId` live (so the running-set path engages) and the seat stays off the overdue clock. This also settles whether the host abandons or rejects the held submit on `/clear` — i.e. whether the reset above is load-bearing or belt-and-suspenders.

3. **#548 (low, held, blocked by #545) — `waitTicks` drift.** `waitTicks` is module-level, only incremented, never reset, so a second wait's first refresh fires at `60 − N%60` rather than 60. Non-functional (max gap stays under 180 s against the 600 s clock). Reset on main `turn.start`, with a two-waits test.

None of these three blocks the re-build; #545 is the next build after this lands.