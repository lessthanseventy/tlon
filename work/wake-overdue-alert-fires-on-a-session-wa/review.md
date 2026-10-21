# verdict: approve

Re-reviewing only f7d8715 (the diff since the 5e05a0a request_changes): +6 in mod.ts, +26 in mod.test.ts. The one required fix is in, correct, and tested.

## required fix — resolved

1. **Submit-generation guard.** `submitGen` (module-level, bumped in `session.end`) is captured per-submit in `submitWakes` (`const gen = submitGen`), and the `finally` decrements `pendingSubmits` only when `gen === submitGen`. Trace: a submit held in conversation 1 captures gen 0; `session.end` resets `pendingSubmits = 0` and bumps `submitGen = 1`; the abandoned submit settles late and its `finally` sees `0 !== 1` → no decrement, count stays 0; the next conversation's submit captures gen 1, `pendingSubmits = 1`, and the `drainWakes` gate (`pendingSubmits > 0`) holds. An orphaned prior-session submit can no longer touch the current count. The guard sits in the shared `finally`, so it is path-independent — it covers both the abandon and reject cases #546 has not settled. Comment is load-bearing and states the why.

   Test ("an abandoned submit settling late does not corrupt the count…") pins it: held submit → session.end → late release of the abandoned hold → new advance; asserts `take_wakes` stays at 2 (the gate holds). RED was 3 (count corrupted → extra take), GREEN at 47 pass. The late release is a resolve, not a reject — fine, both paths share the finally.

Verify: `mise run adapters:claude-code:mod` → 47 pass, 0 fail; `mise run check` exit 0 (workline verify evidence recorded).

## non-blocking follow-ups (carried forward, all open)

1. #545 (med, held, blocked by #547) — a never-completing subagent pins the seat busy: one that crashes/aborts without turn.complete stays in `running` until session.end, so presence_idle never fires and the ~180 s refresh claims "waiting on a background agent" indefinitely, so a dead seat looks alive forever. Fix: store each agentId with the tick it started and drop entries older than a bound in the WAKE_POLL_MS clock callback, with a note() line; also reset mainEnded and waitTicks in session.end. Test: turn.start with agentId, main turn.complete, advance the clock past the bound, expect one presence_idle and that refreshes stop. Next build.
2. #546 (med) — prove live: launch a citizen, background a subagent, confirm turn events carry agentId live (so the running-set path engages) and the seat stays off the overdue clock. This also settles whether the host abandons or rejects the held submit on /clear — i.e. whether the generation guard above is load-bearing or belt-and-suspenders in production.
3. #547 (high, held) — recover the in-flight batch at session.end: the single wake taken before the pendingSubmits gate engages sits in the in-memory chain during a held submit; on an abandoned /clear it is lost (the recovery test accepts submitted = ["wake two"]). submitWakes could record the in-flight texts and put_back_wakes them in session.end before the reset, so a /clear doesn't lose a delivered wake. Closes the last residue of the in-memory loss window; an improvement, not a regression — the change already narrows the loss from "all wakes" to "one batch".
4. #548 (low, held, blocked by #545) — waitTicks drift: waitTicks is module-level, only incremented, never reset, so a second wait's first refresh fires at 60 − N%60 rather than 60. Non-functional (max gap stays under 180 s against the 600 s clock). Reset on main turn.start, with a two-waits test.

#545 remains the next build after this lands.