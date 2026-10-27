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

Not reused: `Staffing.roll_leaf/1`, whose `pane_retired` note would open the next session with
"two turns ended without the stage's artifact".

Checked: `server/test/server/review_fresh_session_test.exs` (5 cases, red before each change,
green after) and the lobby refusal in `server/test/server/mcp/server_test.exs`;
`menard run check --in server` on the branch head.
