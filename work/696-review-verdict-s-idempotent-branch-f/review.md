No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (sonnet-5-5) instead.

# Verdict: approve (#696)

Read the diff of `server/lib/server/workline.ex` and `workline_test.exs`. I did not re-run the suite; the pr.md cites 88/0 and 20/0 runs, which I take as the builder's claim.

- `review_verdict`'s already-approved branch now calls `finish_approval/2`. It reloads the thread. If the thread is at `review` with `awaiting: nil` and owes QA nothing, it retries `park_approved/2`. Any other state returns `{:ok, fresh}`.
- A refusal comes back as the same `{:error, {:not_parked, why}}`. `submit_review` therefore no longer reads a bare `{:ok, _}` as "queued" for a thread nothing queued. This fixes #696.
- No second verdict row is recorded and `end_review` is not called again. The first test asserts one `check_passed` row after the retries.
- A thread already in the merge queue sits at review with `awaiting: nil`, so the retry re-enters `park_approved`. The second test pins a single `Land` job, so the queue evidently dedupes. I did not trace the uniqueness mechanism itself.
- `qa_owed` runs with the retry's `opts`. A retry that passes a different `paths:` could decide differently from the first call. That is a corner, not worth blocking on.

Nit, non-blocking: each refused retry posts the "⚠ not parked" brief again. That is arguably right, since the thread is still stuck.