search_test: restore query_embedding on the plan and timeout tests (#628)

The idf-plan test and the timeout tests (lock-held, details, window) had lost `query_embedding: [1.0, 0.0]`, so they ran the lexical path only. They pass it again, so the whole hybrid `Search.history` runs under them. Tests only; `Search` is untouched.

Note: the keyword ranking query (the one holding the MATERIALIZED idf CTE) is separate from the semantic pass, so the plan test still asserts that query; the semantic pass runs beside it but its own SQL is not plan-checked.

Checked: `menard run test test/server/search_test.exs`, three runs, 18 tests, 0 failures each.
