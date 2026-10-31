Adds the office TUI's half of per-thread pause (#404's server half, `Server.Pause.pause_thread/2` and `resume_thread/1`, was already on main).

- A thread card gets a `|` key: `pause it` while the thread runs, `resume it` while it is paused. It calls `POST /api/threads/:id/pause` or `/resume`.
- The office snapshot's open-thread row carries `paused_at`. A paused thread's `seat` reads `parked`, and the card's title gains `⏸ paused`.
- A paused thread reports "paused: nothing starts on it until you resume it" as its state, not "waiting for a seat": no cap is raised, so the card offers no settings jump.

Closes #673.

How it was checked:
- RED then GREEN, one commit per half. `office_test.exs` "a paused thread carries its paused_at and reads as parked" failed on the missing row key, then passed (`menard run test`, 25 tests).
- `board.test.ts` (paused card state) and `data.test.ts` (`pauseThread` pause and resume round-trip) failed first, then passed.
- `mise run office:check`: typecheck clean, 967 tests passing at both 03:00 and 15:00, exit 0.
- Server gate: `menard run check --in server` (see the verdict on the thread).
