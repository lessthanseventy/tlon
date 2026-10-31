# Review: workline 628-search-test-restore-query-embedding

**Verdict: approve.** Head 1e98207, diffed against 064bd88 (origin/main). Tests and pr.md only; `Search` untouched, as the ticket required.

## Spec compliance

1. Both calls pass `query_embedding: [1.0, 0.0]` again: the idf plan test (search_test.exs:131), the lock-held timeout test (:189) and the details/window timeout tests (:215). Done-when met.
2. The idf CTE is still asserted MATERIALIZED: `captured_history_query` now selects the ranking query by the marker `"idf AS MATERIALIZED"` (default argument), and the test still asserts `"Actual Loops" => 1` on `CTE idf`.
3. The semantic query gets its own plan check (new test, :139-158): captured by the marker `"embedding IS NOT NULL"`, asserting no `Sort` node and exactly one `Index Scan` on `message_pkey` reading `semantic_window` rows. That is the property tertius asked for and a regression dropping the key order or the LIMIT would break it. Sound.
4. Timeout covers the semantic query: `semantic_ranked/2` always issues its `SELECT id, embedding …` before it looks at `query_embedding`, and the ACCESS EXCLUSIVE lock holds any read of `message`, so the semantic query is under the timeout in every one of those tests.

## Findings

5. **Portability (non-blocking, follow-up filed).** `"Actual Rows" => 2.0` at :156 matches a float only. This box is PostgreSQL 18.6, whose JSON EXPLAIN emits `"Actual Rows": 2.00` (checked: `EXPLAIN (ANALYZE, FORMAT JSON)` here prints `0.00`). Postgres 17 and earlier emit the integer `2`, and Elixir's `2.0` pattern does not match an integer, so the test is red on any older Postgres. Not verified on 17 here (none installed), reasoned from PG 18's fractional-row-count change. Fix is one line: bind the value and compare with `==`.
6. **Wording nit in pr.md.** "so the whole hybrid `Search.history` runs under them" overstates it: the semantic SELECT ran under these tests before this change too (see 4). What `query_embedding` adds, the cosine scoring, is reached only when embedded rows exist, and the plan and timeout tests seed none. The new test in 3 is the one that actually exercises the hybrid scoring. The ticket's literal ask is still met; the sentence just claims more than the tests do.

## Checks

- `run_verb test test/server/search_test.exs` on 1e98207 in this worktree: 19 tests, 0 failures (exit 0).
- CHECKS: `mise run check` exit 0 at 13:53Z (verify). Note verify entered at df4f606 (13:34Z) and 1e98207 was pushed 13:40Z, so that gate may have read the earlier head; landing rebases and gates the merged head again, so nothing is lost. No `bench_contrast` row.
- `captured_history_query` now scans the test process mailbox for the marker instead of `assert_received`; each test is its own process, so there is no cross-test leakage.