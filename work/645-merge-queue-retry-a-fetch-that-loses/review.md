VERDICT: approve

No free reviewer is at the builder's grade (greybeard); this review is by tzinacan on sonnet-5-5.

My earlier request_changes is addressed in 9832b17. I ran the two test files; I did not run the full gate.
- `Workline.land/3` now matches `{:error, {:interrupted, why}}` and shares `could_not_merge/2` with the plain error clause. The brief reads "couldn't merge …", the gate stays parked, and nothing raises.
- `Merge.merge/3`'s `@spec` and moduledoc cover the interrupted shape.
- New test: an approve-now merge whose fetch was cut off returns `{:error, {:merge, why}}`, the thread stays in review with `awaiting` set, and the brief is posted.
- The "queue was cut off three times" wording is also fixed.
- `workline_merge_test.exs`: 20 tests, 0 failures. `workline_test.exs`: 86 tests, 0 failures.

Retry shape: 3 tries with a 250ms and 500ms backoff, and only on "cannot lock ref". The lock-race tests hold the lock for 400ms and then free it, which is a timing dependence but a generous one. Not blocking.

Narrowing `fetch_main` so only the lock race is classed interrupted is already filed as its own low ticket (from the earlier review).

Minor: the two `land/3` error clauses have identical bodies, so a single `{:error, why}` clause would do if `why` were stringified. Not worth a round trip.