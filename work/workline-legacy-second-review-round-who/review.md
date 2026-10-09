APPROVE

Reviewed `git diff main...HEAD` (3 commits, `server/lib/server/workline.ex` + `workline_review_head_test.exs`). `mise run check` is recorded green on this head (1234299).

**The fix.** `this_round/2` guarded "review.md is the last round's" with `last_reviewed(thread) != nil`, but `last_reviewed` selects the verdict's `sha`. A round-one verdict recorded before shas existed has a nil `sha`, so the guard let round two advance on round one's stale review.md. `reviewed_before?/1` asks whether any review event exists, which is the right question. The `since_review` nil check is unchanged. Surgical: one new 5-line predicate and one call-site swap.

**Tests.**
- The legacy round test strips `sha` from the round-one event, bounces through verify back to review, and asserts the "this round" error.
- The moved-workline test pins that the brief wakes the lead the bounce staffed (emma), not the reviewer pane (lonnrot). `flush_woken` clears earlier wakes before the `refute_received`, so the negative assertion is sound.

**Nit, non-blocking.** `last_reviewed` and `reviewed_before?` run near-identical queries on the same correlation. Fine at two callers; fold if a third appears.

No follow-ups. Approve.