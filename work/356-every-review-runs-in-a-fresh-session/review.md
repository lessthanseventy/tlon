APPROVE (round 2) — note: no free reviewer was at the builder's grade (greybeard); reviewed by tzinacan, read-only, diff only. I did not run the gate or tests (sandbox); pr.md's `menard run check --in server` → 2233 tests green is unverified by me — verify/landing runs the real gate.

Read: round-1 review.md, then `a9a323e..HEAD` (c9ffc73; workline.ex, tools/workline.ex, server/AGENTS.md, review_fresh_session_test.exs).

The send-back (follow-ups addressed to no one once the verdict ends the reviewer's session) is fixed:
- `review_verdict` and `qa_verdict` post `follow_ups:` AFTER the move, so `Channel.thread_lead` already names the new lead: builder on request_changes, qa seat when QA is owed. When approve hands to the operator's gate the lead is still the author, and `follow_ups/4` now falls back to `@operator()` instead of an empty prefix. `operator/0` exists (workline.ex:2214).
- `SubmitReview`/`SubmitQA` no longer post first; they pass `follow_up_items/1` through and report its count. QA's old `stage == "review" and verdict in pass/fail` guard is preserved by the clause guard on `qa_verdict`, so a bad verdict posts nothing.
- The idempotent-approve retry (`approved_at?`) returns before `record_verdict`, so a retried call does not double-post. Previously it would have.
- Three tests pin the three addressees (builder / qa seat / operator, each refuting `@lonnrot`). server/AGENTS.md and the tool docs say what the code does.

Round-1 follow-ups, both dropped by the builder with reasons in pr.md; I accept them. #1: a per-review thread (choice A) has no builder conversation to hide. #2: the leaf window is one per thread, the kill cannot be author-scoped, and no shared thread takes a verdict now that review_branch is refused off the lobby.

No new blocking findings.