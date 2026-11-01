# A review's verdict ends the reviewer's session last, from a job

Closes #796.

`record_verdict` ended the reviewer's session right after recording the check, before the park, the
bounce and the follow-ups. Closing the reviewer's window takes its client down, and the client's
teardown cancels the request still running on the server (anubis: `notifications/cancelled`
terminates the tool call's task, a session DELETE stops its process), so the park died mid-way: the
thread sat at review, awaiting nil, nobody told, until it surfaced as stalled an hour later.

What changed:

- `Server.Jobs.EndReview`: an Oban worker (unique per thread) that runs `Staffing.end_review/1`.
- `Server.Workline.record_verdict/5` no longer ends the session inline; it enqueues `EndReview` after
  the park, the hand to QA or the bounce and the follow-ups. A node without Oban (a test, a dev shell)
  ends it inline at that same point, so the ordering holds there too.
- `review_verdict/4`'s doc and `server/AGENTS.md` describe the new order.

Not touched: `finish_approval` (#789 is a separate fault inside it) and `BranchReview`'s own
`end_review` for `review_branch` (#793's ground, same shape).

How it was checked:

- RED first: two tests in `review_fresh_session_test.exs` with a live reviewer session. An approval
  must park the gate (awaiting the operator) and a request_changes must bounce to build while the
  session is still live, with `EndReview` enqueued; performing the job ends the session and closes
  the leaf. Both failed on the old code at the "session still live" assertion.
- GREEN: `menard run test --in server` over review_fresh_session, workline, workline_qa,
  workline_review_head and jobs/grade: 137 tests, 0 failures (check event 15515).
- `mise run server:check` passed on 6d5a01a via `run_task` (message #28098).

The server half of the cancellation path is confirmed in anubis source (`scheduler.ex`:
`async_nolink` tool tasks, `cancel_in_flight` → `terminate_child`; `plug.ex`: DELETE →
`stop_session_process`). That Claude Code sends the cancel or DELETE when its window is killed is
inferred from the ticket's "client exited" stamp, not proven here.
