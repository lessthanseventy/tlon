APPROVE — #648

Read the diff (origin/main...HEAD) only; I did not run the tests.

- `Office.leaf_for?/4` is the predicate Staffing already had inline, lifted into Office. `Office.windowed?/3` now lets an untagged leaf vouch for the thread's lead only, and `Staffing.windowed?` calls the shared function. The two `own?` clauses stay separate on purpose, as the PR says.
- The lead is looked up once per call instead of once per tab. A nil `thread_id` short-circuits to nil, so the standing-window path behaves as before.
- Tests cover both callers: office (lead is windowed, a non-lead is not) and wake (a non-lead's wake in an untagged pane is let go, not paged). The PR says they went RED first.
- The wake narrowing is stated in pr.md and is intended.

No blocking findings. The PR says the full `server:check` gate passed on the head; I did not check that.