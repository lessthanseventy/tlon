staff_child on a workline no longer answers ok with a nil lead.

A workline's lead is staffed once, when it opens. If that handoff fails, the thread is left
unled and `staff/2` used to answer `{:ok, nil}`. It now returns `{:error, {:unled, thread_id}}`,
and `explain/1` names the thread and says to `restaff_now` it, so the manager does not open a
second thread.

Ticket #722.

Checked:
- New test: a registered agent off the bench, named as lead on a workline, leads it as asked
  (reply and `Channel.thread_lead`). It passes before and after this change; it pins existing behaviour.
- New test: `explain({:unled, id})` names the thread and `restaff_now`. Red before, green after.
- Not driven through the tool: the nil-lead branch only fires on a `Repo.update` failure in
  `Staff.assign/2`, and the tool cannot reach that without a new seam. The clause stands on its type.
- `menard run test test/server/mcp/server_test.exs`: 124 tests, 0 failures.

Scope note: `explain/1` lives in `lib/server/mcp/tool.ex`, so that one-line clause sits outside
`coordination.ex` and `server_test.exs`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
