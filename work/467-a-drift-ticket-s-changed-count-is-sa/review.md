APPROVE

Reviewed 157b3c3 (keep_up.ex, keep_up_test.exs, pr.md) by reading the diff. I did not run the tests; pr.md reports 23 tests, 0 failures from menard.

- `update/4` compares the ticket's old title with the new one. The title carries the commit count, so a changed count posts a `notice` on the lobby and an unchanged one posts nothing. The tests cover both cases.
- Failure paths are unchanged. A failed ticket update, a missing lobby or a failed post all fall through to `Rollout.note({:drift, repo}, body)`, so the operator still hears.
- The moduledoc is updated in the same commit, as the repo law asks.

Nit, not blocking: a body change with the same title (same count, different drift kind) updates the ticket silently. Today the title carries the only varying fact, so this is fine.