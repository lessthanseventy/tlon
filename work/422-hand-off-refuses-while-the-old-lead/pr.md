`Staffing.hand_off/3` now refuses with `{:error, :lead_mid_turn}`, changing nothing, when the old lead has a live turn on the thread (`turn/2` is `:busy`: `thinking_since` inside `Thinking.stale_turn_seconds`). A turn stuck past that limit reads as idle, so the operator is never locked out; `roll_leaf` and `kill_crew` still force it. The operator API and `assign_lead` pass the error through unchanged.

When hand_off does kill the old lead's window it now also ends the thread's sessions, as `roll_leaf` does, so no session row stays open under a dead pane.

Closes #422.

Checked: two new tests in `staffing_test.exs` (busy lead refused with lead, messages, session and windows untouched; stale-turn lead hands off and its session ends), red first for the right reasons, now green with the rest of the file (44 tests, 0 failures).
