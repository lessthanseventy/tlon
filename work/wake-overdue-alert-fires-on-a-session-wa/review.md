# verdict: approve

Only change since the prior approve (7135259) is 5f29e87 — the stale-refresh characterization test (runeberg's follow-up #1), applied test-first and unchanged. No production code moved this round, so there is no new bug surface; the test is sound and the gate is green on the branch.

## what landed this round (5f29e87)

`mod.test.ts`: a new test advances the mod's own clock 60 × 3 s past `STALE_REFRESH_TICKS` with the main turn ended and a subagent still running, and asserts exactly one `presence_doing { summary: "waiting on a background agent" }`; then completes the subagent and asserts `presence_idle` fires. It re-uses the existing `engine(on, { ownClock: true })` / `mock.clock` / `clock.advance` / `settle` harness already proven by the "a push is held" test, so it exercises the real poll, not a stub.

## why it's sound

- The production path matches the assertion exactly: `STALE_REFRESH_TICKS = 60`, the heartbeat fires at `++waitTicks % 60 === 0` only when `thread && mainEnded && running.size`, and `waitTicks` increments once per poll tick. 60 ticks → `waitTicks == 60` → one fire; the test stops there, so `toHaveLength(1)` is exact, not a floor.
- It is a regression test, not a vacuous pass: on the pre-change code there is no `mainEnded`/`running`/`waitTicks`, `presence_idle` would fire on main-turn-end (failing the `toEqual([])` assertion) and the heartbeat would not exist (failing `toHaveLength(1)`).
- The 60-tick loop runs green under the kit (`mise run adapters:claude-code:mod` → 43 pass, 0 fail) and the full gate (`mise run check` exit 0; verify passed 13:15). emma's report that the loop is not too slow for the kit is confirmed by the green run.

## the change as a whole (unchanged from runeberg's review)

Two root causes, both fixed test-first: `drainWakes` no longer holds `draining` across `$.prompt.submit` (submits run on their own serial `submitWakes` chain, so the poll keeps taking), and `presence_idle` is withheld while a subagent runs, with a ~180 s `presence_doing` heartbeat against the 600 s stale-turn clock. `presence_doing` resets `thinking_since` (verified server-side in `Server.Presence.Thinking`), so the unchanged `Wake.report_overdue` guard reads the seat as busy. The `main..HEAD` "deletions" of #534 are the branch being behind main (merge-base 8cdbe48), not a revert — the landing rebase brings #534 back.

## non-blocking follow-ups (replace the prior review's set)

1. **Not proven live.** The fix is green under the gate and sound by reading the server, but the mod's AGENTS.md asks it be proven on a live seat: launch a citizen, background a subagent, confirm `turn` events carry `agentId` live (so the running-set path engages) and the seat stays off the overdue clock.

2. **Wakes queued behind a held submit are lost if the session ends first.** `take_wakes` deletes the server row; `submitWakes` queues the text onto the in-memory `submitting` promise chain. If the session ends (crash, abort, `/clear`) while a submit is still held, the chain is abandoned and those wakes never reach `put_back_wakes` — silent data loss with no server row to report stale. The old code risked only the one wake mid-submit; this change widens the window to every wake that arrived during the held submit. Fix: keep not-yet-submitted wakes in a module-level list and `put_back_wakes` them in the `session.end` hook next to `running.clear()`, or have `drainWakes` skip `take_wakes` while a submit is pending so they stay on the server. Test: `submitHangs: true`, `wakes: [["wake one"], ["wake two"]]`, advance two polls, fire `$.session.end`, expect `put_back_wakes` to carry the unsubmitted wakes.

3. **A subagent that never sends `turn.complete` leaves the seat permanently busy.** If a background subagent crashes or aborts without `turn.complete`, its `agentId` stays in `running` until `session.end`, so `presence_idle` is never declared and the ~180 s heartbeat fires forever — the seat reads busy indefinitely (the opposite false state from the bug this change fixes). Fix: on a new main `turn.start`, or after a bound on `waitTicks`, drop stale entries from `running` and declare idle; also reset `mainEnded` and `waitTicks` in `session.end` next to `running.clear()`. Test: a subagent `turn.start` with no complete, then main `turn.complete`, then the bound passes, expect `presence_idle`.

Neither #2 nor #3 blocks: both are narrow-window silent modes, and the change's job — killing the active false overdue alarm — is done. Filing them so a future edit can't lose them.