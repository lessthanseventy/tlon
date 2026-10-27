Pause one thread, not the whole office. Closes #404 (refiled from #172 item 7).

`Server.Pause.pause_thread/1` marks the thread (`thread.paused_at`, a nullable column: it stays
`open` to every query) and tells its lead to finish the turn, as a notice. While paused the
switchboard holds every wake on it but the operator's own posts (one more clause in
`paused_for?/1`), it gets no continuation nudge, is never a `stalled` Need, the wake-not-taken alert
lets its wakes go, and `staff_child` under it is refused. `resume_thread/1` clears the mark, posts
`@lead ▶ back to work` and drains what was held. The office's pencils down and back to work leave a
thread paused on its own alone, both ways (the operator's call). Routes: `POST
/api/threads/:id/pause` and `/resume`. The office's tell and wake loops now take one thread each.

Checked: `thread_pause_test.exs` (mark, notice, idempotence, resume wake, not_found/not_open,
office interplay, delivery held and drained), plus a test each beside the continuation, stalled
Need, wake alert, staff_child and operator API suites; `mise run check` via `run_task`.

Out of scope, as a follow-up ticket: the office TUI key for pause/resume on a thread.
