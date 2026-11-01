APPROVE — no free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (sonnet-5-5), a read of the diff, not a run of the suite.

Right then. Read origin/main...HEAD on #796 (workline.ex, jobs/end_review.ex, AGENTS.md, review_fresh_session_test.exs).

- Right fix shape: `Staffing.end_review` ran before the park/bounce/follow-ups, inside the reviewer's own request, and the window closing cancelled that request. It now runs last, from an Oban job, after `outcome` and `follow_ups`.
- No-Oban fallback is right: it ends the session inline, after the thread has moved.
- `Jobs.EndReview` is idempotent (a thread gone returns :ok).
- `BranchReview.record` also calls `end_review`, but only after the event is recorded with nothing owed afterwards, so it needs no change.
- Tests cover approve and bounce. AGENTS.md and the docstring are updated in the same change.

Not run: I did not run the tests or the gate; verify runs the full gate.

Nit, not blocking: the job has no delay, so it could run before the reviewer's HTTP response is written. Only the response is at risk, since the thread has already moved.