## #694 hold_thread: the hold and release notices name who did it

A lead's hold or release of its thread now says who did it on the thread.

- Pause notice: `✎ paused — finish this turn … (held by <who>: <why>)`, from `Server.Pause.pause_thread/3`.
- Release wake: `@<lead> ▶ back to work — … (released by <who>)`, from `Server.Pause.resume_thread/2`.
- `hold_thread` passes the calling agent's handle; the operator API passes `"operator"`.
- Callers with no actor (the office's back-to-work wake) keep the current text; the `@told`/`@resumed` prefixes are unchanged, so `stopped_threads/0` still matches.

Closes #694.

Checked:
- Red first: the new test in `server/test/server/thread_pause_test.exs` failed on `Pause.pause_thread/3` undefined.
- Green: `thread_pause_test` and `mcp/server_test` 118 tests, 0 failures.
- Server gate `menard run check --in server`: format, warnings-as-errors and 2546 tests, 0 failures.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
