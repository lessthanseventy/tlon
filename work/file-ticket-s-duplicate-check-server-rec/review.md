# Review: file-ticket-s-duplicate-check-server-rec (#713)

**Verdict: approve.** Reviewed a2fd47d; the code is 583ee4a. Diff: `server/lib/server/recurrence.ex`, `server/test/server/recurrence_test.exs`, `server/test/fixtures/recurrence_titles.tsv` (724 titles), `pr.md`. No spec.md or plan.md exist (the workline started at build).

I did not take the green on trust. I replayed the old scorer and the new one over the fixture corpus in plain Elixir (the same `words`/`best` arithmetic, titles read from the test file) and compared.

## Findings

1. **The false negative (#711 never found #712) is fixed, with margin.** Old: 9.7, two shared tokens (`lead`, `profiles.model_label`), tied with #722 and one point above #518. New: 41.8, nine shared tokens (`brief, hand, hand_to, label, lead, model, profil, profiles.model_label, rais`), cover 0.79. The tokenizer is the fix, as the send-back said; the threshold is untouched.

2. **The false positives are cut, not gone.** Title pairs matching across the whole corpus (self excluded): old 2748; new tokenizer alone 4366; new tokenizer with the 0.4 cover 431. Of the 13 refused titles, 11 had an unrelated look-alike under the old scorer on this corpus; 3 still have one under the new rule, each in a top-3 slot the negative test does not check:
   - "Roster trust tie-break follow-ups" → #712 (shared `follow-up, trust`, cover 0.45)
   - "read dirs left out of the brief post 7 times" → #138 MCP tool calls time out under load (`brief, post, tim`, cover 0.48)
   - "Script tests post fake gate and smoke runs…" → #370 a smoke or gate run from a stale worktree (`gat, run, script, smok`, cover 0.62)
   A short query makes the smaller-side cover easy to reach. The ticket's bar ("a match only on a shared fault, or at least on real shared terms") is met for the long-title case and mostly for the rest; the moduledoc's "a false match costs one more call with `distinct: true`" is the honest description of what remains.

3. **The smaller-side cover is the right side.** I checked the obvious tightening (cover against the larger side). It closes all three leaks above but also drops #715, #730, #731 and #778, which are real matches, and leaves #711→#712 at exactly 0.40. Not a change to make.

4. **The negative tests are weaker than asked and partly vacuous.** The send-back asked that every look-alike pair return `[]`; the tests refute three ids each. On the corpus 12 of the 13 titles' top hit is the title's own later ticket (cover 1.0), which takes one of the three slots, and the three leaks in finding 2 sit in the others unseen. The tests still went red on the old scorer (8 of 14), so they have teeth; they just do not pin the remaining behaviour. Follow-up below.

5. **Issues only got looser.** The stem and compound split raise matches (2748 → 4366 pairs on titles), and `similar_issues` skips the cover. The only issue test is the sheriff's "worded twice" true positive; nothing pins a false positive on issues. The commit's reason (200-char prose shares few words) is asserted, not shown. Not a regression the ticket reports, so not blocking.

6. **Stemming is sound on this corpus.** Every stem group merging three or more raw words (`pages/page/paging`, `lands/landing/land`, `wake/waking/wakes`, …) is a genuine inflection; I found no wrong merge. The `e$` strip yields odd stems (`cod`, `liv`, `gat`, `mod.t`) but both sides stem alike, so no false split.

7. **Nits (lines on the thread, not tickets).** The length filter runs before `stem/1`, so `uses` survives as `use` while a bare `use` is dropped. Hyphenated compounds (`tie-break`, `claude-code`) are not split while `.`/`_` ones are, which matches the ask. The arity strip handles `name/3` but not `Mod.fun/3` with a trailing `/`-path ambiguity; none in the corpus.

## Checks

- The gate passed on a2fd47d (`mise run check`, `tlon/check: success posted`). The tail shows a Postgrex connect error against a dropped `tlon_eval_*` database; the gate still exited 0, and that is the eval database teardown, not this diff (I could not confirm it predates the branch).
- `menard run test server/test/server/recurrence_test.exs`: ok, 19 tests, 0 failed (my own run, this worktree).
- No `bench_contrast` row: the diff touches no steering file.
- Commit trailers: `Co-Authored-By: claude-sonnet-5-5`, `Tlon-Author: emma`, `Tlon-Model` stamped. Author is not the reviewer.

## Not verified

- The cost of the new tests: each of the 14 files 724 tickets (`Tickets.file` is a sort query, an insert and a bus announce each). The verify's server gate grew from 358s to 598s between the two heads. I could not time the file: menard's MCP `run test --slowest` timed out at 620s (#760, seen again).
