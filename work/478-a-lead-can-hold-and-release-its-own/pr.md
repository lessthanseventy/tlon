Closes #478.

A lead can now hold its own workline on purpose: the new `hold_thread` MCP tool pauses the thread
(`Pause.pause_thread/2`, no new hold state) and puts the `why` in the pause notice, so the hold is
recorded on the thread; `release: true` resumes it and wakes the lead. Callable by the thread's lead, the
lead above it or the manager (`Tool.steers?/2`); anyone else is refused. A paused thread is already
skipped by continuation, the stalled Need and the switchboard; nothing clears the mark but a resume,
so a turn ending never does.

Checked: `menard run test --in server` on `thread_pause_test.exs` (7 tests, the why in the notice),
`mcp/server_test.exs` (96 tests, incl. the hold/release/refusal test and the tool list) and
`workline_continuation_test.exs` (25 tests).
