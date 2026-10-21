# REQUEST CHANGES — sessions-outlive-server-stop-and-tmux-re

## Verdict

**Request changes.** The core fix is right, but the ordering suppresses the restart carry-on notice — a behavioral regression in the restart-pickup flow — and the test harness runs the new step switched off, so neither the regression nor the interaction is covered. Two blocking findings below. (This supersedes my earlier approve; the grader's blast/detectability/proof grades traced the interaction I missed.)

## Blocking

### 1. Ordering before `resume_interrupted` drops the "machine restarted, pick it up" notice

`end_predating_tmux/1` runs in `pass/3` BEFORE `resume_interrupted/3`. It ends every predating session with a `pane_ref`, including mid-turn ones (`thinking_since` set). `Staff.interrupted/1` then filters `is_nil(s.ended_at) and not is_nil(s.thinking_since)` — so every session just ended is excluded, `resume_interrupted` sees nothing, and the `@<agent> the machine restarted while you were mid-turn here — pick it up from the brief` carry-on notice is never posted.

After a real `server:stop` + `server:restart`: the tmux server is gone, all panes dead, mid-turn session rows still open. Before this change, `resume_interrupted` ended them AND posted the notice (that post is the wake that re-spawns the coworker onto the thread). With this change, the session is silently ended first and the coworker is never re-woken — the cut-off turn stalls on the floor.

↳ `end_predating_tmux(workspace_id)` placed before `resume_interrupted(workspace_id, tabs, standing)`

**Fix (either):**
- Move `end_predating_tmux(workspace_id)` to AFTER `resume_interrupted/3`. Mid-turn predating sessions get their carry-on notice and are ended by `resume_interrupted`; `end_predating_tmux` then cleans up the idle and reused-pane ones, skipping the already-ended via its `is_nil(s.ended_at)` guard. No double-end. This keeps `end_predating_tmux` out of warmth's semantic lane entirely, OR
- Exclude mid-turn sessions from `end_predating_tmux` (`and is_nil(s.thinking_since)`), leaving them for `resume_interrupted`.

The first is cleaner — `resume_interrupted` owns the mid-turn-carry-on contract; `end_predating_tmux` shouldn't have to know about it.

### 2. The shared fake tmux disables the new step across the entire existing suite

`answer/2`'s catch-all `true -> {"", 0}` answers `display-message -p #{start_time}` with `""`, which `Integer.parse/1` rejects → `server_started` returns nil → `end_predating_tmux` does nothing. So every existing staffing test that uses the shared `tmux/1` helper runs with the new step switched OFF. The new path's interaction with `resume_interrupted`, `end_windowless` and the restart flow has zero regression coverage — which is precisely how finding 1 escaped the suite.

↳ `true -> {"", 0}` in `answer/2`

**Fix:** add a `"display-message" in args -> {"#{System.os_time(:second) - 3_600}\n", 0}` clause to `answer/2`, returning a `start_time` older than any fixture session. The existing restart/regression tests then run with `end_predating_tmux` switched ON, and finding 1 surfaces in the suite rather than only in review.

## Follow-ups (non-blocking)

- Log a warning in `end_predating_tmux` when `server_started` returns nil. A `display-message` that fails in production (a tmux without `#{start_time}`, or a fault) silently switches the safety step off with nothing behind it; the module's "skips the pass" contract covers a tmux that is down, not one that is up but partially unaskable.
- Once the step is ON under the shared fake, make the new test's `dead` session mid-turn (`session!("borges", here.id, 30, true)`) with no window and assert the `@borges the machine restarted` notice IS posted — locking the `resume_interrupted` interaction that finding 1 breaks.
- The `started_at < start_time` comparison is UTC-on-UTC (`:utc_datetime` and `DateTime.from_unix!/1` both UTC), so a clock/timezone skew is not a real risk; worth one explicit assertion once the step runs under the shared fake to pin that.