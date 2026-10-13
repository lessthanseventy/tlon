# Review: search_history times out at the 15s db checkout

**Verdict: approve.** Branch at 4942b6d (rebased onto main 958fe83; `HEAD..origin/main` is empty).

## Since the last review (2c25491)

The code diff against main is byte-identical to what I approved: `idf AS MATERIALIZED` plus its load-bearing comment in `Server.Search.history/3`, and the seeded 5-term perf test. Everything else in `2c25491..HEAD` is main's own commits (office bathroom, adapter register retry) picked up by the rebase; nothing of this change touches them.

The merge-gate red (check_failed #5226) was not this branch: tests were 1595/0, and the failure was `server:check`'s dev-env step reporting a `decimal` lock mismatch. The branch does not touch `mix.exs`/`mix.lock`; in this worktree `deps/decimal` matches the lock. Stale deps in the gate's checkout — infra, tracked alongside #251.

## Standing assessment

`idf` referenced once was inlined, so each term's document frequency was re-counted per candidate row (cost ∝ candidates × terms × table). MATERIALIZED counts it once. GIN index on `body_tsv` already exists; `stats` was already materialized. Search suite 14/14 at last review; verify's full `mise run check` passed on this branch before the gate.

## Findings

None blocking. Follow-ups unchanged from the first review (listed below).