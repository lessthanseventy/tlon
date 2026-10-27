# Every review runs in a fresh session

Closes #356.

A review is a throwaway session on the reviewer's seat, briefed with the branch, the diff, the
spec/plan and the checklist, and it ends when the verdict is in.

- **The verdict ends the reviewer's session.** `Server.Staffing.end_review/1` ends the thread's
  live sessions and closes its leaf window, recording nothing for `left_off/2`. Both verdict doors
  call it once the verdict is durable: `BranchReview.record/1` (`review_branch`) and
  `Workline.record_verdict` (`submit_review`).
- **A reviewing lead is not shown the builder's conversation.** `Board.brief/2` takes `viewer:`; the
  MCP reads (`get_brief`, the brief resource) name the caller, so a workline's reviewer gets OPENING,
  RECENT, DONE and LEARNINGS hidden with their counts kept. The operator API's read is unchanged.
  `last_reviewed` still points a round-2 reviewer at its own review.md in the stage brief.
- **`review_branch` from the standing thread is refused**: a PR review runs on its own thread, not
  the warm lobby window.
- **Follow-ups are addressed to the lead the verdict hands to.** With the reviewer's session gone at
  the verdict, `submit_review`/`submit_qa` post their `follow_ups` after the move, from
  `review_verdict`/`qa_verdict` (`follow_ups:`): `@builder` on a bounce, `@qa` when QA is owed, the
  operator when it goes to their gate. Before, the post named the thread lead, the reviewer itself.

Review follow-ups (tzinacan): (1) hiding the conversation on `review_branch` threads — dropped: a
per-review thread is opened for the review and carries no builder conversation, so the spec holds
there without `reviewing?` reading it. (2) scoping `end_review` to the verdict's author — dropped:
the leaf is one window per thread and killing it ends every pane in it, so an author-scoped session
end would leave the window kill unscoped; with `review_branch` refused off the lobby no shared
thread takes a verdict.

Not reused: `Staffing.roll_leaf/1`, whose `pane_retired` note would open the next session with
"two turns ended without the stage's artifact".

Checked: `server/test/server/review_fresh_session_test.exs` (8 cases, red before each change,
green after; three pin the follow-ups' addressee per verdict) and the lobby refusal in
`server/test/server/mcp/server_test.exs`;
`menard run check --in server` on the branch head.
