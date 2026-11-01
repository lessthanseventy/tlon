# Review — work/search-test-exs-139-flaky-fts-over-the-m @ d2b146b

**Verdict: approve.**

The witness: one hunk in `server/test/server/search_test.exs` (the :139 plan check) plus `pr.md`. The EXPLAIN now runs inside `Repo.transaction` with `SET LOCAL enable_seqscan = off` and `SET LOCAL enable_sort = off`. Nothing in `lib/` changes.

## Findings

1. **The fix matches the cause.** The statement under EXPLAIN is `semantic_ranked/2`'s `SELECT id, embedding FROM message WHERE embedding IS NOT NULL ORDER BY id DESC LIMIT $1` — one table, one ORDER BY on the primary key. On five rows the planner may legitimately pick seq scan + top-N Sort over a backward index scan by cost, so the assertion was about `pg_class.reltuples` after a full suite, not about the query. Disabling both leaves the index scan as the only unpenalised path. Verified by reading the SQL, not by repro (the builder says the same; neither of us saw the flake).
2. **The test still has teeth.** `enable_sort = off` is a cost penalty, not a prohibition: if the query ever ordered by a column no index serves, Postgres still emits a Sort node and `refute … "Sort"` goes red. The assertion is now exactly its title: the primary key offers the order.
3. **SET LOCAL is scoped correctly.** The suite runs with no Ecto sandbox (`test/support/test_db.ex` cleans rows instead), so `Repo.transaction` here is a real transaction and both settings die at its COMMIT. Nothing leaks to the next statement or test.
4. **Pattern match is right.** `Repo.transaction/1` wraps the fn's return in `{:ok, _}`; `{:ok, %{rows: [[[%{"Plan" => plan}]]]}}` matches the EXPLAIN JSON shape as before.
5. **Evidence.** CHECKS: `mise run check` exit 0 on the branch at 04:30:18 (full gate, one more full-suite pass through :139, n=1). No bench_contrast row (no persona files touched), so nothing to call.
6. **pr.md** names the ticket (#768), the cause, the check and what it does not touch. Fine.

Spec/plan docs: none exist (ticket-born at build), as the stage brief allows. No security surface.
