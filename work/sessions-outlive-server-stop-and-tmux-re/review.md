# REQUEST CHANGES — sessions-outlive-server-stop-and-tmux-re (round 2, revised)

## Verdict

**Request changes.** My round-2 approve is withdrawn: the risk grader's pass (msg #10597) caught three real, cheap problems I under-weighted, and the workline is still at the operator's gate so the cost is one small rebuild round. The core fix and the round-1 ordering fix remain correct; these are about repairability and the suite's honesty, not the mechanism.

## Blocking

### 1. Silent ends are unrepairable — log each session `end_predating_tmux` ends

`end_predating_tmux/1` calls `Staff.end_session/1` on every predating session — an irreversible stored write that runs every minute, in every workspace, with no log line and no thread message (only the nil-start-time branch logs). A wrong end is currently unfindable: a git revert stops new ends but reopens nothing, and no ids are recorded. This is exactly what `server/AGENTS.md` bars — "Nothing here ships that cannot be repaired at 2am."

↳ ` |> Enum.each(&Staff.end_session/1)` (staffing.ex:760)

**Fix:** `Logger.info` with the session id, agent and pane_ref before each `Staff.end_session/1`. A wrong end then becomes visible, and the rows can be found and reopened if a revert is needed.

### 2. Test 1's title overclaims — "even mid-turn" but the session is idle

`"a session from before the tmux server started is ended, even mid-turn; one after it stays"` creates `dead = session!("borges", here.id, 30)` — the 4th arg defaults to `thinking? = false`, so `dead` is idle, not mid-turn. The title claims coverage it does not have.

↳ ` dead = session!("borges", here.id, 30)` (staffing_test.exs:176)

**Fix (preferred):** make it `session!("borges", here.id, 30, true)`. The fake `list-windows` reports a window for `borges` on `here.id`, so `resume_interrupted` skips it (`has_window?` true) and `end_predating_tmux` is what ends it — this pins the mid-turn + has-window + predating case nothing currently covers, and makes the title honest. Otherwise drop "even mid-turn" from the title.

### 3. The mid-turn + predating + has-window case is uncovered and the behavior is undecided

Test 2 (`"a mid-turn session from before the tmux server is ended and its coworker still told to carry on"`) gives its mid-turn session no window (`tmux("")`), so `resume_interrupted` ends it and posts the `@borges the machine restarted` notice with `end_predating_tmux` doing nothing — the test passes with the step deleted. It pins the round-1 ordering fix but not `end_predating_tmux` itself. The case it does NOT cover, and nothing does: a mid-turn predating session that HAS a matching window. There `resume_interrupted` skips it (window present) and `end_predating_tmux` ends it silently with no carry-on notice. That behavior is currently "works by accident, not asserted."

↳ ` test "a mid-turn session from before the tmux server is ended and its coworker still told to carry on"` (staffing_test.exs:204)

**Fix:** add a case (or reshape test 1 per finding 2) with a mid-turn predating session that has a matching window. Assert: the session IS ended (its `pane_ref` is stale), and the carry-on notice is NOT posted (the window is present, the turn reads as alive). This pins the intended outcome deliberately — after `server:stop`+`restart` all windows are gone, so this case is a coincidental id-reuse by the same agent on the same thread, where the stale row should be ended and the fresh spawn left alone.

## Follow-ups (non-blocking, filed)

- **Scope the filter to the workspace's own tmux.** The query filters by workspace thread (`t.workspace_id == ^workspace_id`) but not by which tmux a `pane_ref` came from. `pane_ref` is `$TMUX_PANE` cast in at session start (session.ex:39); bench-coworker panes run on the workspace's private tmux, but an outside-citizen session (uqbar's pane runs on a foreign tmux) on a workspace thread that predates the workspace's lazily-started tmux would be wrongly ended. Unverified (pane_ref origin is not in this diff); the logging fix in finding 1 makes a wrong end findable in the meantime. Worth matching `pane_ref` against the panes `list-windows` reports, or recording which socket a `pane_ref` came from, plus a test with a pre-tmux session whose pane_ref is not in the workspace's tabs.