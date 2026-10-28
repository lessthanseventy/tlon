REQUEST CHANGES

Reviewed 0b276d0 on work/478-a-lead-can-hold-and-release-its-own by reading the merge-base diff (7 files, 117 lines: AGENTS.md, endpoint.ex, mcp/tools/workspace.ex, pause.ex, two tests, pr.md). The two-dot diff against origin/main also shows #467 and #686 reversed; that is the branch being 2 commits behind main, not a revert in this change. I did not run the suite; verify's `mise run check` passed on this head (CHECKS 04:08). bench_contrast is unmeasurable (AGENTS.md edit), not a finding.

1. BLOCKING — a closed thread crashes the tool instead of refusing. `Pause.pause_thread/2` and `resume_thread/1` return `{:error, :not_open}` for a thread whose state is not "open" (and `{:error, :not_found}`). `Server.MCP.Tool.HoldThread.hold/3` passes that result to `Tool.reply/3`, whose only clauses are `{:ok, row}`, `{:error, %Ecto.Changeset{}}` and `{:error, reason} when is_binary(reason)`. Reproduced on the test build: `Server.MCP.Tool.reply(%{}, {:error, :not_open}, & &1)` → `FunctionClauseError` at lib/server/mcp/tool.ex:116; nothing rescues inside execute, so the caller sees an internal error, not a message. Reachable: `Tool.acting_thread/4` loads any thread by id without checking its state, so the lead above naming a finished child, or a session still bound to a closed thread, hits it. Fix where the thread is already in hand:

```
     case Tool.acting_thread(params, frame, &Tool.steers?/2, "its lead, the lead above it or the manager") do
       {:error, message} -> fail(frame, message)
-      thread -> hold(frame, thread, params)
+      %{state: "open"} = thread -> hold(frame, thread, params)
+      thread -> fail(frame, "thread ##{thread.id} is not open")
     end
```

With that, `:not_found` cannot reach reply either. Add the test: `hold_thread` on a closed thread answers isError with "not open".

2. The scope's required test (a paused workline past the quiet window gets no continuation nudge and no stalled Need; resume wakes it) is satisfied by tests already on main, since the tool reuses pause_thread/resume_thread: workline_continuation_test "a thread the operator paused is not nudged until it is resumed", office/needs_test "a workline the operator paused is not stalled", thread_pause_test "resume clears the mark and wakes the lead". The new server_test covers hold, release, the lead above, a stranger refused and a missing why. Acceptable.

3. `steers?/2` admits the workspace manager as well as the lead and the lead above; the scope named only the two leads. Same rule as send_back and post_message; fine.

4. The notice carries the why as "(held: …)" before "You'll hear when it's back to work."; the operator's own pause (why nil) reads exactly as before, and `stopped_threads/0` still keys on the "✎ paused" head, so a thread pause is still never counted as the office's. Good.

Non-blocking findings are in follow_ups.