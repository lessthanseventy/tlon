# A retried approval finishes a refused park (#696)

`Workline.review_verdict`'s already-approved branch handed back the stale thread as `{:ok, thread}`.
After a refused park (review.md not committed, the queue down) that thread sits at review awaiting
nobody, and `submit_review` read the reply as "in the merge queue — your session ends here" with
nothing queued: the reviewer left, and the workline sat at review until its lead noticed.

The retry now reloads the thread and, at review with no one awaited and nothing owed to QA, parks
it again through the same `park_approved/2`: the same `advance`, the same refusal text if it still
fails. No second verdict is recorded, no second `end_review`, no re-posted follow-ups. A thread
already parked, already in the merge queue or handed to QA is left as it is.

Closes #696.

Checked: `workline_test.exs:467` (approve twice with review.md missing → not parked twice; commit it
→ the retry parks on andrew; one `check_passed` row for the review correlation) was red on a9505e4
and is green with the fix; `:500` pins one Land job for a retry on a queued thread.
`menard run test test/server/workline_test.exs` 88/0, `workline_review_head_test.exs` 20/0;
`server:check` via run_task on this head.
