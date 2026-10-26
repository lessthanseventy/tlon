# Review — workline 251-the-switchboard-never-re-delivers-a, round 2 (0c06dd7)

**Verdict: request_changes.**

## Last round's finding

Fixed. `unheard?/1` for a tlon-authored message now reads `reply_author(message) ++ mentioned_agents(message) != [] and unheard_by_addressees?(message)` (switchboard.ex:161), exactly the escalated patch; `++` binds before `!=`, so an addressee-less post is skipped and one that @mentions or replies to a seat keeps the 10–30 min retry. Two tests cover both arms (addressee-less notice → 0 redelivered; "@Sandra ✓ `mise run check` passed" → 1). CHECKS: `mise run check` exit 0 on this head (20:08Z); no bench_contrast row in the brief.

## Findings

1. **pr.md describes the first fix, not this one.** It says "`Switchboard.redeliver_unheard/1` no longer hands back tlon-authored messages" and "the one-clause fix … 57 tests, 0 failures". After 0c06dd7 a tlon post that names a seat is handed back, and the suite is 58. The PR body is GitHub's permanent record of the change and states the opposite of the code on the point the review turned on. Replacement text posted on the thread (message #14257); one commit, no code.

Not verified by me beyond reading the diff and callers: I ran nothing.
