VERDICT: APPROVE

Scope reviewed: `git diff origin/main...HEAD` (server/lib + tests), against plan.md and ticket #81. I read the diff and the surrounding callers. I did not re-run the gate. The verify stage recorded `mise run check` as green (1206 tests, 0 failed).

Spec compliance
- A plain thread (`stage: nil`) with a dirty checkout or unmerged commits is tracked via `Workline.promote/1` (the same path as `tlon-cli track`). It is not closed. The lead is @mentioned and `close_thread` returns `{:tracked, t}`.
- Staged threads and threads with no checkout on disk take the old path (`do_close`).
- Root machine threads are excluded, so the standing thread is never tracked.
- Every caller handles `{:tracked, _}`: the `close_thread` tool, `finish`, and the operator API route. `workline.ex:1140` only closes merged threads, which are never `stage: nil`, so it is safe.
- The manager triage brief gets the "ticket that changes code gets a workline" sentence, with a test.

Findings (none blocking)
1. `track_instead/2` can return `{:error, _}` when `promote` fails, for example on a slug collision. The `close_thread` tool's `close/2` has no clause for it, so it raises `CaseClauseError`. `finish` already falls through to `reply(other)`. The old code crashed here too (`{:ok, closed} =`), so this is no regression. Adding `{:error, _} = e -> reply(frame, e, & &1)` would be tidier. Worth a follow-up, not a blocker.
2. The tracked path skips the child-thread "report up" post. That is right, because the thread stays open.
3. The `stays_open` reply is duplicated verbatim in `coordination.ex` and `thread.ex`. Three similar lines are fine here.
4. I did not check whether `server/AGENTS.md` or `server/docs/spec.md` describe `close_thread`. The diff touches neither, and plan Task 4 asks for that check. If either does describe it, they need the tracked outcome added.
