Ticket: closing a plain thread (one with no workline `stage`) whose checkout holds unmerged commits
strands the work — `Server.Channel.close_thread/1` closes it and the branch is orphaned. Fix it.

Wanted behaviour:

- `Server.Channel.close_thread/1` on a plain thread whose worktree (`Server.Worktree.stranded/2` is the
  existing check) holds unmerged work does NOT close it. It tracks the thread as a workline instead
  (`Server.Workline.promote/1`: stage `build`, state stays `open`, the worktree kept) and returns
  `{:tracked, thread}` where `thread` is the promoted thread.
- It also posts on the thread, as author `tlon`, a message whose body says why (it contains the word
  "unmerged"; mention the thread's lead when it has one).
- A plain thread with nothing stranded closes as before: `{:ok, closed}`. Threads that already have a
  stage, and the root/machine thread, behave as before.
- The MCP tools that close threads (`close_thread` in `mcp/tools/coordination.ex`, `finish` in
  `mcp/tools/thread.ex`) must handle the new `{:tracked, thread}` return: reply (not an error) with
  `{"stays_open": true, "tracked": <slug>, "why": "unmerged commits — tracked as a workline instead of closed"}`.

The existing tests in `test/server/channel_test.exs` and `test/server/mcp/server_test.exs` show the
helpers; add your own tests there. Keep `mix test` green.
