# APPROVE — search_test: a many-term query is shaped by its plan, not a wall clock

Ticket #258, branch `work/search-test-no-wall-clock-bound-no-20k-r` @ f939733. Test-only: `server/test/server/search_test.exs`, +45/−23. No production code touched, matches the ask.

## What I verified myself (not taken from the report)

- `menard run test test/server/search_test.exs` in this worktree: **16 tests, 0 failed.**
- The plan assertion is a real guard, not a tautology. I captured the SQL `history/3` sends, then ran `EXPLAIN (ANALYZE, FORMAT JSON)` on it and on the same SQL with `idf AS MATERIALIZED (` rewritten to `idf AS (`:
  - with MATERIALIZED: one node `Subplan Name: "CTE idf"`, `Actual Loops: 1`
  - without: **no such node at all** (Postgres inlines it) → `assert [%{...}] = []` fails. Dropping `MATERIALIZED` reds the test, which is exactly the regression the old `micros < 1_000_000` bound was there for.
- The timeout test's mechanism holds: this suite runs with **no sandbox** (`Server.TestDB` — "the suite runs against one DB with no sandbox"), so the holder task's `LOCK TABLE message IN ACCESS EXCLUSIVE MODE` really is on another connection and really blocks `Search.history`. `timeout: 50` cannot pass by luck; it is blocked, so it always times out. The lock is released inside the test, so the orphaned waiter is gone before the next test's `clean!` — the exact failure mode the 20k seed caused (57014 in cleanup) can't recur.
- No embedding call is triggered by the new fixture: `semantic_ranked/2` returns `[]` when no message has an embedding, so `history/3` in both tests stays off the embedder.

## Findings

No blocking defects. Coverage note for the record: the old test also asserted `length(shown) == 10` over a busy channel; the new one asserts nothing about the result set. Not a regression worth a ticket — the cap is covered elsewhere — but worth knowing the fixture no longer exercises it.

Three non-blocking follow-ups are filed with the verdict (a residual wall-clock assert, keying the captured query off a prose comment, and the telemetry handler's lifetime). None change behavior; the change is sound as it stands.
