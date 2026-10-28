# Review — workline 686 (an approved review parks the workline itself)

No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan at a lower grade.

**Verdict: approve**

## What I checked
- `Server.Workline.review_verdict`: with no QA owed, an approval now calls `park_approved`, which runs `advance` itself. `{:awaiting, _}` and `{:ok, _}` return `{:ok, thread}`. An advance error posts a warning on the thread and returns `{:error, {:not_parked, why}}`, so a refused park is never reported as parked. The verdict stands either way.
- `SubmitReview`: the reply now carries `parked` and a `next` read off the outcome (awaiting the operator, queued under a standing approval, handed to QA, or not parked). `not_parked` takes the same reply path as success, so the reviewer sees the refusal.
- Brief, exit line and continuation text now say approve ends the session. They no longer say to call `advance_stage`, which would be a dead instruction.
- `menard run test --in server` on `workline_review_head_test`, `workline_test` and `workline_brief_test`: 113 tests, 0 failures. I did not run the full gate; verify and landing do.

## Notes (non-blocking)
- `next/2` tells "standing approval" apart from "handed to QA" by whether the thread's lead changed. That is a heuristic and would misreport if QA were ever staffed with the same lead. Nothing in this change triggers it.
