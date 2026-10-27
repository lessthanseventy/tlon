# #356 plan — every review runs in a fresh session

Spec: `spec.md` (approved). Rule for every task: write the test first, watch it fail
(`menard run test <file>`), make it pass, commit alone. Final gate: `menard run check --in server`.
Where a task says "read first", the named lines are the contract; match their idiom.

Findings that shape the plan (from reading origin/main):
- `Server.MCP.Tool.ReviewBranch.execute/2` records the verdict (`Server.BranchReview.record/1`) and
  then does nothing to the session: the reviewer's window and Session stay warm (a "review and land
  PR" thread like #358 stays open until GitHub merges; a review run from the lobby sits on
  `w1:<handle>`).
- The leak into a fresh reviewer is `Server.Board.brief/1` → `Server.MCP.Brief.scope/1`
  (`lib/server/mcp/brief.ex:23-42`): `opening`, `recent`, `done`, `learnings` carry the builder's
  conversation. `Workline.Brief.stage_message/2` (the stage brief) carries none; it stays.
- Ending a session + closing its leaf already exist: `Staff.end_thread_sessions/1`
  (`staff.ex:167`) and `Staffing.roll_leaf/1` (`staffing.ex:342`, which also closes the window).

## Task 1 — pin the property (failing test only)
File: `server/test/server/review_fresh_session_test.exs` (new). Using the fixtures of
`switchboard_test.exs` ("autonomous cold-thread spawn", ~l.412) and `server_test.exs:1968`
(review_branch over MCP), write:
1. `two consecutive reviews on one reviewer handle get two distinct sessions`: reviewer R reviews
   branch A on review thread T1 (spawn stub gives it a Session), calls `review_branch`; then reviews
   branch B on T2. Assert: two `Session` rows for R, different ids; the first has `ended_at` set;
   `Server.Staffing.leaf_window(T1, "test")` is nil after the verdict.
2. `the second review's opening brief carries nothing from the first thread`: post a distinctive
   line ("builder-chatter-7f3a") on T1; `Server.Board.brief(T2_as_reviewer)` rendered through
   `Server.MCP.Brief.scope/1` contains no such string anywhere (`inspect/1` of the map).
3. `a round-2 workline review keeps its last_reviewed pointer without thread posts`
   (Uqbar's note): build a workline in review with a prior review event carrying a `sha`; the
   stage brief (`Workline.Brief.stage_message(t, last_reviewed: sha)`) still contains the
   "since your last review" text, and the reviewer's `Server.MCP.Brief.scope` has `"recent" => []`.
DONE: `menard run test server/test/server/review_fresh_session_test.exs` fails on 1 and 2
(3's brief half passes, its `"recent" => []` half fails). Commit: "test: pin fresh-session reviews (red)".

## Task 2 — a reviewer's brief omits the conversation
Files: `server/lib/server/board.ex` (read first: the `brief/1` build near l.200-280, `recent:` at
l.273), `server/lib/server/mcp/brief.ex` (unchanged unless the map shape needs it).
Change: in `Board.brief`, when the thread is a workline in `stage: "review"` or a branch-review
thread, and the caller is its lead reviewer, set `recent: []` and `opening: nil` (and drop `done`
and `learnings`, which are the builder's write-ups). Keep `workline`, `checks`, `commits`,
`goal`, `cited` — the diff, spec/plan and checklist live behind `workline`/`goal` and the stage
brief's read list. One private predicate `reviewing?(thread, caller)` is the only new function.
DONE: Task 1 tests 2 and 3 green. Commit: "brief: a reviewing lead is not shown the builder's conversation".

## Task 3 — the verdict ends the reviewer's session
Files: `server/lib/server/mcp/tools/branch_review.ex` (`ReviewBranch.execute/2`),
`server/lib/server/workline.ex` (`record_verdict`, so `submit_review` does the same).
Change: after a recorded verdict, call a new `Server.Staffing.end_review(thread)`: ends the
thread's live sessions and closes its leaf window, ie `Staff.end_thread_sessions(thread.id)` plus
the window close that `roll_leaf/1` does, but it must NOT respawn (roll_leaf's contract is "next
wake spawns fresh", which is what we want on the NEXT review, so reuse it unchanged:
`def end_review(thread), do: roll_leaf(thread)`, a one-line named seam so the intent reads at the
call site). Do it AFTER the verdict is durably recorded and ignore `:ok` results; the tool's reply
to the reviewer is composed before the window dies.
DONE: Task 1 test 1 green. Commit: "review: the verdict ends the reviewer's session".

## Task 4 — a PR review from the lobby runs on its own thread
Read first: `Switchboard.maybe_spawn_absent/1` + `spawn_home/3` + `elsewhere/2`
(`switchboard.ex:345-380`): on the standing thread a named coworker gets one window there (the
warm `w1:<handle>`).
Change (smallest): `ReviewBranch.execute/2`, when `identity.thread_id` is the workspace's standing
thread (`Server.Channel.machine_thread/1`), refuses with: "open a review thread for this PR
(`open_thread`, lead you) and review there: a review runs in its own session, ended by its
verdict." Test: calling `review_branch` with the standing thread's identity returns
`isError` with that text; from a normal thread it records. No auto-creation of threads (YAGNI;
"review and land PR" tickets already create theirs).
DONE: `menard run test server/test/server/mcp/server_test.exs` green incl. the new case. Commit:
"review_branch: refuse from the lobby; a review gets its own thread".
RISK to confirm with the operator if the lobby path is used in practice: this makes a lobby
`review_branch` an error rather than a silent warm-session review.

## Task 5 — docs and gate
`AGENTS.md` (the `review_branch` sentences at l.27 and l.137): add "Each review runs in its own
thread and session, ended by its verdict." Run `menard run check --in server`; record with
`record_check`. DONE: exit 0. Commit: "docs: reviews are fresh sessions".
