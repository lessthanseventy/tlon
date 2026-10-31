search_test: restore query_embedding on the plan and timeout tests (#628)

The idf-plan test and the timeout tests (lock-held, details, window) had lost `query_embedding: [1.0, 0.0]`, so they ran the lexical path only. They pass it again, so the whole hybrid `Search.history` runs under them. Tests only; `Search` is untouched.

New: the semantic pass's query (`SELECT id, embedding … ORDER BY id DESC LIMIT $1`) is captured like the ranking query and its plan asserted. Today EXPLAIN shows Limit over a backward `message_pkey` Index Scan that reads exactly `semantic_window` rows (2) with no Sort. That is the property a regression would break: dropping the index order or the LIMIT turns a window read into a sort of every embedding. `captured_history_query` now takes the SQL marker to pick the query by.

Checked: `menard run test test/server/search_test.exs`, three runs, 19 tests, 0 failures each.
