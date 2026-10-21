## verdict: approve

Round 3. All three blockers from the round-2 request_changes (4bd78b7) are fixed and verified in 347e58b; the gate is green (1938 tests, 0 failed; verify evidence recorded on the branch).

### blocker 1 — silent ends are unrepairable: FIXED
`end_predating_tmux` now `Logger.info`s before each `Staff.end_session/1`, naming session id, agent_id, thread_id and pane_ref (staffing.ex:760-766). `require Logger` was already present (line 47). A wrong end is now visible and the row is findable — satisfies server's "nothing ships that cannot be repaired at 2am." The query already filters `not is_nil(s.pane_ref)`, so the pane in the log is never nil.

### blocker 2 — test 1's title lied ("even mid-turn" but idle): FIXED
`dead = session!("borges", here.id, 30, true)` (staffing_test.exs:179) — mid-turn, `thinking_since` set. Title rewritten to "a mid-turn session from before the tmux server whose window matches is ended, logged, and not told to carry on; one after it stays." Title and body now agree.

### blocker 3 — mid-turn + predating + has-window case uncovered and undecided: FIXED and PINNED
Test 1 now covers exactly this case (lines 175-207): `dead` is mid-turn, predating (`started_at` −7200s vs the fake tmux's `display-message` start of −3600s), and `list-windows` returns a matching `borges`/`here` tab. The intended outcome I named in the round-2 review is asserted deliberately:
- `resume_interrupted` runs first; `has_window?(tabs, here.id, "borges", standing)` is true, so it skips `dead` — no end, no carry-on notice.
- `end_predating_tmux` then ends `dead` (predating, pane_ref set, not ended) and logs.
- Asserts: `dead.ended_at` set, `live.ended_at` nil, NO "the machine restarted" message on `here`, and the log names `session #{dead.id}`, `thread #{here.id}`, `%3`.

RED/GREEN is honest: with only the test edited, the log assertion failed while the ended/no-notice assertions already passed (they pin existing behaviour, as expected); after the `Logger.info` change, staffing_test is 37 tests, 0 failed.

### complement checked
Test 2 (`tmux("")`, no window) covers the other branch: `resume_interrupted` ends the mid-turn `cut` and posts the notice; `end_predating_tmux`'s `is_nil(ended_at)` guard skips it — no double-end, no double-notice. The shared fake `answer/2` answers `display-message` with `old()` (now−3600s), so `end_predating_tmux` runs ON across the rest of the suite instead of silently off.

### non-blocking follow-up (held, not blocking this change)
The filter scopes by workspace thread but not by which tmux a `pane_ref` came from: a session on a foreign tmux (e.g. an outside citizen's pane) on a workspace thread that predates the workspace's lazily-started tmux would be wrongly ended. Unverified; the logging fix above makes any such wrong end findable. Worth scoping to panes the workspace's tmux actually reports + a test, in its own change. Filed as ticket #529 — kept here in follow_ups so it stays held until this workline merges.