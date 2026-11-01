search_test: the newest-embeddings plan check no longer depends on planner cost (closes #768)

The test asserts the meaning pass's plan has no Sort and reads two rows through message_pkey. On five rows the planner may pick a seq scan + top-N sort depending on table stats left by earlier tests, so it failed in full suites and passed alone. The EXPLAIN now runs with `enable_seqscan` and `enable_sort` off (SET LOCAL, in a transaction), so it asks only whether the primary key offers the order.

Checked: `menard run test --in server test/server/search_test.exs` — 19 tests, 0 failures. The flake needs a full-suite stats state to show; not reproduced alone, so the fix is by construction. The 50ms checkout timeout at :217 seen in the same run is a separate matter, not touched here.
