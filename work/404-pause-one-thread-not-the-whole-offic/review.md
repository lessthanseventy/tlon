NOTE: no free reviewer at the builder's grade (greybeard); tzinacan reviewed. Read-only static review; I did not run the suite (a coworker seat has no Postgres or checks queue), so tests are unverified by me. Verify runs the gate.

# Verdict: approve

I read the full code diff: pause.ex, switchboard, wake, continuation, needs, staff_child, operator_api, the migration, the tests and AGENTS.md.

What checks out
- One mark (`thread.paused_at`) and the thread stays "open" everywhere. `@thread_told` differs from `@told`, so `stopped_threads/0` never mistakes a thread pause for an office pause.
- The office's pencils_down and back_to_work leave a paused thread alone both ways, and the tests cover it.
- The switchboard hold exempts the operator and covers every wake that goes through `deliver`. Resume clears the mark before it wakes the lead, and the comment says why. It then drains.
- Continuation, the stalled Need and `Wake.report_overdue` are silenced for a paused thread, and `staff_child` is refused under a paused parent.
- A grep of the other `Pause.state()` and `Blocked` consumers (intake, schedules, banter) finds no other per-thread nudger that was missed.
- Pause and resume are idempotent. A missing thread gives 404 and a closed one gives 409. Each lever has a test.
- AGENTS.md is updated in the same change.

Notes (not blocking)
- The migration adds a nullable column. That is fine, but it is a schema change, so the merge gate should treat it as one.
- `paused_for?` now runs one extra `thread_paused?` query per undelivered wake. That is cheap at this scale.
- A thread closed while paused keeps `paused_at`. This is harmless, because every reader also checks that the state is open.