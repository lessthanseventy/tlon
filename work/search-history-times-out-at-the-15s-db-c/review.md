# Review: search_history times out at the 15s db checkout

**Verdict: approve.** Branch at 8cef87e.

## What the change does

`Server.Search.history/3` scored each OR-matched message with a correlated subquery over the `idf` CTE. Referenced once, Postgres inlined it, so each term's document frequency was re-counted per candidate row — cost ∝ candidates × terms × table, which is exactly the "5-word query dies, 1–3 word queries answer" shape in the ticket. `idf AS MATERIALIZED` counts once per query. Builder's live-store EXPLAIN ANALYZE: 8789ms → 98ms (not re-measured here; the mechanism matches the symptom and the test reproduces it).

## Checked

- Diff read in full: one keyword plus a load-bearing SQL comment, a seeded perf test (3000 matching messages, 5 terms), and pr.md. Nothing else touched. Spec/plan docs don't exist (workline started at build) — expected.
- `stats` is referenced twice so it was already materialized; `terms` folds into the materialized `idf`. No other CTE has the same trap.
- `message_body_tsv_index` (GIN) exists in the baseline migration, so the per-term df counts and the main `@@` filter are index-served. No new index needed.
- Ran `menard run test --in server test/server/search_test.exs`: 14 tests, 0 failed (record_check event 5172). Server verify stage already passed the full `mise run check` on this branch.
- Not verified by me: that the perf test goes red without the fix. Builder reports `query_canceled` on the inlined version; plausible given 3000 × 5 × seq-count.

## Findings

None blocking. Non-blocking, filed as follow-ups:

1. The perf test asserts wall-clock `< 1_000_000` µs. ~10x headroom over the measured query, but a timing bound on a shared test box under a parallel `mise run check` is a flake waiting to happen. An assertion on the plan (EXPLAIN shows one `CTE Scan on idf`, loops=1) would be deterministic.
2. `semantic_ranked` still pulls every embedding row as JSON and does cosine in Elixir — ~260ms at 6.6k messages, linear in corpus. Noted in pr.md; carried here so it isn't lost.
3. The ranking still sorts every OR-match with a per-row `unnest` subquery before `LIMIT`. Linear now, fine at 10k; the ticket's "bound it" half (a statement timeout or a candidate cap) is not done and is worth doing before the store is 10x.
