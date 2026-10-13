REVIEW: approve. Note: no free reviewer at the builder's grade (greybeard) was available; reviewed by tzinacan at a lower grade.

Change: requeue_stranded's discard cap now counts only Land jobs discarded since the standing approval (`inserted_at >= approval.at`), so a fixed branch approved again gets a fresh cap. Approval is no longer re-recorded on requeue/reopen under a standing approval, so the cap window is stable.

Verified:
- Diff read (workline.ex, workline_test.exs, pr.md). `record_approval` runs before the Land job is enqueued, so job.inserted_at >= approval.created_at; a requeue under a standing approval keeps it, so its discards keep counting; a changed branch makes `approval/1` nil, so queue records a new approval and the window resets.
- `Workline.approval/1` callers (reopen, requeue_stranded, queue) only pattern-match on by/sha, so the added "at" key is safe.
- Ran `menard run test --in server test/server/workline_test.exs` unsandboxed (the sandbox blocks the Postgres socket): ok, 63 tests, 0 failures, including the new per-approval cap test.
- Not run: full `mise run check` gate.

Follow-up (non-blocking): queue/3 keeps the old approval's `by` when unchanged code is re-approved by someone else.