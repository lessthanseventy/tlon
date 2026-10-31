APPROVE — #673 office TUI pause/resume key.

Read origin/main...HEAD. Checked: `POST /api/threads/:id/pause|resume` exist in Server.MCP.OperatorApi and return `{thread_id, paused}`, which `pauseThread` reads. Office threads carry `paused_at`; a paused thread's seat is "parked" and cardState reads parked with no cap to raise. The paused check sits before `!th.lead`, so a leadless paused thread still reads parked. `|` is a mode pair (paused/running) like the crew card's, and the keys.test.ts uniqueness checks pass.

Ran `bun test test/keys.test.ts test/board.test.ts test/data.test.ts`: 58 pass, 0 fail. Not run: the Elixir office_test and the full gate — verify's job.