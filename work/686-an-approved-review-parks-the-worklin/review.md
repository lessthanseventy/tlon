approve

No free reviewer is at the builder's grade (greybeard); tzinacan (cheap tier) reviewed. Read the diff only. I did not run the suites and rely on pr.md's claim that server:check passed on 7ae9a69 (HEAD adds only pr.md).

## Findings
- Spec: matches #686. After an approving verdict the session is gone, so `record_verdict` now calls `advance/2` itself (`park_approved`) when no QA is owed. The QA path is untouched, request_changes is untouched, and `end_review` stays where it was.
- `{:awaiting, t}` is returned as `{:ok, t}`, so the `review_verdict` contract holds. The standing-approval path (`{:ok, moved}`) is covered by a test.
- `{:error, _} -> {:ok, thread}` leaves the verdict standing with `awaiting` nil if the advance is refused. This is the old stall, but now only on a refusal, and the refusal is in the ledger. Acceptable; see the follow-up.
- Text consistency: the tool's `next`, the review brief, the exit line and the continuation no longer say `advance_stage`. The tests (including the new `refute ... "advance_stage"`) and the stage-discipline eval clause are updated to match.
- The new tests exercise the real door (`SubmitReview.execute`) and assert the thread ends up awaiting `andrew`.
- No migration, dependency, gate or AGENTS.md change.

## Follow_ups
No ticket for the swallowed advance error: the refusal is already in the ledger and the case is narrow.