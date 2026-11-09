VERDICT: approve

Second round. Commits read: 2eebeec (hold a parked review gate's Uqbar route while its grade job is live) and 7a14866 (a live grade job holds only the review gate, not other needs on its thread), on work/a-parked-gate-wakes-uqbar-before-the-ris against origin/main 92deeca. Diff since my first verdict (d730e3b): server/lib/server/office/needs.ex (+3/-2), server/test/server/office/needs_test.exs (+12). CHECKS: `mise run check` exit 0 on the branch at 7a14866 (16:52:44); the `tlon/check: not posted — gh 422` tail is the verify checkout's sha being absent from GitHub, reported and not red. No bench_contrast row.

## First-round finding

1. **The hold was keyed by thread, not by the gate item** — fixed. Both `hold/2` clauses are now guarded on `%{kind: "gate", stage: "review"}`; any other item on the thread falls through `hold(item, _) -> item` to `route_item/4` as before. Red-first test added: under `auto_land_risk`, a review gate with a live Grade job and an ask on the same thread; the ask is in `Needs.grouped().phone` as `pass_up`, and the gate (first test) is in no group.

## Read and not a finding

- Hold while the stage is review, `auto_land_risk` is set and the newest Grade job on the thread is available/scheduled/executing/retryable; ends on its own through `completed_at`/`discarded_at`/`cancelled_at`/`attempted_at`, so a failed grader (max_attempts 1) never holds a gate forever.
- `at` for the `uqbar_route_minutes` clock is the later of the park and the job's end, truncated to the second; a Uqbar verdict row is written only after the hold ends, so the bump cannot shadow it.
- With `uqbar_routing` off, `grade_jobs/1` is not called; with no review gate in the items, no Oban query.
- `grouped/1` drops `held` items before splitting, so `NeedsPage` sees no key enter the uqbar group while held; `Needs.list/0` still shows the gate.
- Two comment lines against ~45 of code, moduledoc's Routing paragraph updated, no ticket keys or history in code; pr.md names the ticket and the check.

No follow-ups.