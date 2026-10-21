# verdict: approve

The false alarm had two root causes and the change fixes both, test-first. No blocking findings.

## what the change does

1. **`drainWakes` no longer holds `draining` across `$.prompt.submit`.** Submits now run on their own serial chain (`submitWakes`); the poll only takes. The host holds a submit until the session is idle, so the old `await $.prompt.submit` inside `drainWakes` kept `draining=true` until idle — the next poll's `if (draining) return` skipped `take_wakes`, so a queued wake sat untaken past the overdue window. With the chain, `draining` releases in `finally` and the next poll takes again. The chain catches per-submit errors and `put_back_wakes` failures, so it never rejects and one failure can't break future submits.

2. **`presence_idle` is no longer declared while a subagent runs.** `turn.start`/`turn.complete` now track running subagents (`e.agentId`) and a `mainEnded` flag; idle is declared only once the main turn and the last subagent have ended. While the main turn has ended but a subagent still runs, the poll declares `presence_doing` every ~180 s (60 × 3 s) against the 600 s stale-turn clock.

## why it's sound

- **The `agentId` contract is pre-existing, not invented here.** `plan/mod.ts:12` and `mod.ts:723` already branch on `e.agentId` to separate subagent turns from the main turn, so the new tracking rests on an established harness contract.
- **`presence_doing` does refresh the stale clock — verified, not assumed.** `Server.Presence.Thinking` runs the stale window "from its declare or its latest `doing/4` report" (thinking.ex), and `Wake.report_overdue` skips a wake whose session has `thinking_since > live`. So with presence correct, the unchanged server guard reads the seat as busy.
- **The `mainEnded`/`running` logic handles interleaving.** A new main turn while a subagent runs resets `mainEnded=false` (no premature idle); a subagent ending after the main turn is what fires idle. `session.end` clears `running`. The mutations are synchronous at the top of each handler, before any await, so there's no race window.
- **The skipped live measurement is acceptable.** The brief's first commit was to measure whether `$.prompt.submit` blocks; Bash was down for the build, so it wasn't done. The pr's reasoning holds: if submit blocks, the chain fix applies; if it doesn't, the chain is harmless and the presence fix stands alone. The fix does not depend on the answer.
- The `main..HEAD` diff shows #534's `finish` feature and its tests disappearing — that is the branch being behind main (merge-base 8cdbe48), not a revert. The branch's own two commits touch only `mod.ts`, `mod.test.ts` and `pr.md`; the landing rebase brings #534 back. Not a finding.

## non-blocking follow-ups

- **No test for the ~180 s stale refresh.** The two new tests cover the held-submit and the idle-while-subagent-runs paths, but not the `presence_doing` refresh that keeps a long-running background subagent off the 600 s stale clock. A regression there would silently reintroduce the false alarm for a background subagent that runs past ten minutes. Worth a test that advances the clock past `STALE_REFRESH_TICKS` with `mainEnded && running.size` and asserts a `presence_doing` declare.
- **Not proven live.** The fix is green under the gate (`claude plugin test`, 42 pass) and sound by reading the server, but the mod's AGENTS.md asks it be proven live — launch a citizen, background a subagent, and confirm the running-set path engages (turn events carry `agentId` live) and the seat stays off the overdue clock. The brief's measurement was the seed of this; it is still owed.