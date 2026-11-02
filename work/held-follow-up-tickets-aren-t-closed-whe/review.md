Review by ulrikke at haiku-5-5: no free reviewer is at the builder's grade (senior), so this is a reduced-grade review.

VERDICT: approve.

Checked: the branch diff f8d534b against main, covering server/lib/server/intake.ex, server/lib/server/jobs/intake.ex and server/test/server/intake_test.exs. The spec.md and plan.md named in the REVIEW brief are not in this worktree (only pr.md is under work/held-follow-up-tickets-aren-t-closed-whe/), so spec compliance is checked against the commit message and the moduledoc only.

Ran: menard run test --in server test/server/intake_test.exs gave ok, 28 tests, 0 failed.

Reasoning:
- landed_on_main returns the newest commits first (git log -n 300). Map.put_new in close_landed keeps the newest sha per ticket id, which matches the comment.
- The closing-number regex only takes a "(#N)" at the very end of the subject. A non-matching subject is dropped by the [_, id] pattern.
- With no :landed option the path is a no-op, so existing tests are unaffected.

Follow-ups below are non-blocking.