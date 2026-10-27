# #356 — every review runs in a fresh session

Ask (Andrew via Uqbar, 2026-10-13): each review runs in a fresh, throwaway session on the reviewer's
seat (its model, effort, read-only permissions), briefed only with the branch, the diff, the
spec/plan and the checklist; it ends when the verdict is submitted.

## Today (origin/main c639c80)
- A workline review is already fresh: on review entry the lead hands to the reviewer and
  `close_leaf` kills the builder's window (`Workline.hand_to/close_leaf`, one `t<id>` leaf per
  thread); approve's QA handoff closes the reviewer's window.
- A `review_branch` PR review runs on the reviewer's standing `w1:<handle>` window, which stays
  warm between reviews.
- A freshly spawned reviewer still reads the builder's back-and-forth via `get_brief`/the thread.
- No test pins "two reviews, two sessions".

## Decisions
1. **Where a PR-branch review runs (operator: A).** On a per-review leaf thread (as #358 is),
   a `t<id>` window spawned for that review and closed at the verdict. Not on the standing
   window, and no roll of it (`Staffing.roll_leaf/clear_context` stay for their current callers).
2. **What the reviewer's brief carries.** Branch, diff, spec/plan, checklist
   (`Brief.stage_message`'s read list stays) plus the `last_reviewed` pointer. The builder's thread
   conversation is not part of the brief: a review brief renders no thread posts.
3. **When the session ends.** At the verdict (`submit_review` / `review_branch`), not at the
   stage change: the review thread's window is closed and its Session ended in that call.
4. **Unchanged.** `last_reviewed` still points a round-2 reviewer at its own `review.md` and the
   diff since its last review; that memory lives in the artifact, not the session.

## Scope
Touches `Switchboard.maybe_spawn_absent`, `Arbiter.Tmux.spawn`, `Staffing` (verdict closes the
leaf), `Workline.Brief` (no thread conversation in a review brief). Not #376, #380; #357 builds
on this and stays held until it lands.

## Test (the definition of done)
In `server/test`: two consecutive reviews by one reviewer handle produce two distinct `Session`
rows (different ids, first has `ended_at` set at its verdict), and the second review's opening
brief contains no line posted on the first review's thread. Verify: `menard run test <that file>`,
then `mise run check`.

## Open for the plan
Whether the PR-review thread already exists at `review_branch` time (it does for "review and land
PR" tickets like #358) or must be created by the entry point; the plan settles this by reading
`Switchboard.maybe_spawn_absent` first.
