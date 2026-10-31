# Review: workline 628-search-test-restore-query-embedding

**Verdict: approve.** Round 2. Head adb4e06, diffed against 064bd88 (origin/main). Tests and pr.md only; `Search` untouched, as the ticket required.

## What changed since the last verdict (e8bbc28)

1. One file, four lines (`git diff e8bbc28..adb4e06 -- . ':!work/…'`): search_test.exs:156 now binds `"Actual Rows" => rows` in the Index Scan match and asserts `rows == 2` beneath it. That is exactly the fix the send-back named and nothing else. Elixir's `==` holds for `2.0 == 2`, so PG 18's fractional row count and PG ≤17's integer both pass. The round-1 portability finding is closed.

## Spec compliance (unchanged from round 1, re-read on this head)

2. Both calls pass `query_embedding: [1.0, 0.0]` again: the idf plan test (:131), the lock-held timeout test (:191) and the details/window timeout tests (:217). Done-when met.
3. The idf CTE is still asserted MATERIALIZED via the default marker `"idf AS MATERIALIZED"`; `"Actual Loops" => 1` on `CTE idf` stands.
4. The semantic pass has its own plan check (:139-160): no `Sort` node, one `Index Scan` on `message_pkey` reading `semantic_window` rows. A regression dropping the key order or the LIMIT breaks it.
5. The timeout tests still cover the semantic query: `semantic_ranked/2` issues its `SELECT id, embedding …` before it reads `query_embedding`, and the ACCESS EXCLUSIVE lock holds every read of `message`.

## Checks

- `run_verb test test/server/search_test.exs` on adb4e06 in this worktree: 19 tests, 0 failures, exit 0.
- CHECKS: `mise run check` exit 0 at 18:34:33Z (verify), after the branch row `work/628-search-test-restore-query-embedding @ adb4e063e82d` at 18:18:45Z, so the gate read this head. No `bench_contrast` row, so nothing to grade there.
- The two red verify runs before it (17:07Z, 17:14Z) failed five `Server.WorklineVerifyScriptTest` cases (the PR landing gate's canary A/B tests), which this branch does not touch; the 18:34Z run passed them. Not this change's, but noted in case they recur on another branch.

## Still open, non-blocking

6. pr.md's "so the whole hybrid `Search.history` runs under them" overstates it: the plan and timeout tests seed no embedded rows, so the cosine scoring is reached only by the new semantic-pass test. Cosmetic; listed as a follow-up.