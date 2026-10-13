# search_history: stop re-counting document frequencies per row

Closes ticket #202.

`Server.Search.history/3` scored each OR-matched message with a subquery over the `idf` CTE. Postgres
inlined that CTE (referenced once), so every term's document frequency was re-counted for every
candidate row: with 5 common terms on the live store (6.7k messages) the query ran 8.8s and under
load hit the 15s checkout/cancel. `idf` is now `MATERIALIZED`, counted once per query.

Checked: EXPLAIN ANALYZE of the 5-word query on the live store 8789ms → 98ms; new
`search_test.exs` perf test (3000 matching messages, 5 terms) went red with `query_canceled`, now green;
`menard run test --in server` search suite 14/14.

Not changed: `semantic_ranked` still loads every embedding (~260ms at 6.6k messages) — grows
linearly; worth a pgvector/ANN follow-up when the store is 10x.
