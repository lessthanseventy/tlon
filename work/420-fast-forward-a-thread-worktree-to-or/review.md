# Review — workline 420-fast-forward-a-thread-worktree-to-or @ 8a733ce (round 6)

**Verdict: approve.** The round-5 blocking finding is fixed exactly as posted, with the RED test. Verify's `mise run check` passed on 8a733ce (exit 0, 14:43:27Z); `menard run test` on spawn_test + worktree_test: 65 tests, 0 failed; no bench_contrast row among the CHECKS shown.

## Fixed since round 5

1. **Lead identity is the tell, not `:assign`.** `cwd_export/2` (spawn.ex) drops `opts` and gates on `agent.id == thread.agent_id and agent.name not in Server.Outside.names()`. Witness, every production join:
   - `switchboard.ex:368` wake spawn: joins the lead (`agent.id == thread.agent_id` is the filter one line above) with `assign: false` → catch-up fires. This is the #420 case.
   - `crew/tmux.ex:49` crew pane, `assign: false`, not the lead → skipped.
   - `coordination.ex:177` seats a child's lead on a fresh child with `assign: false` → fires on a checkout with no pane running on it; harmless.
   - A staffing join: `maybe_assign` runs `Staff.assign` before `cwd_export`, and `Staff.assign` returns the updated thread, so `thread.agent_id` is the joiner → fires.
2. **RED test** "the lead's wake spawn (assign: false) catches the checkout up": seats `codex`, moves main, joins `codex` with `assign: false`, asserts `NEW`. Fails on 94821b8 (builder's report; consistent with the old `:assign` gate). The rider test (`reviewer`, not the lead) and the outside test (`uqbar` leads the study, Outside guard) both still pin their cases under the new gate.

## Whole-branch state (ae4bc6a..8a733ce, 5 code commits)

- Catch-up lives in `Spawn.cwd_export`, once per spawn, never in `Server.worktree_for_thread` (hronir's wake-only call, e82312e), facade test pins it.
- Moves only a clean, non-detached branch with no commits of its own, `merge --ff-only origin/main`.
- Status lines are `kind: "notice"`; the ahead line speaks only when `HEAD..origin/main` is non-zero, through `Worktree.moved_past/1` on the injectable `git/2`; the marker resets on :moved/:level; a failed catch-up is logged and told once.

## Follow-ups (not blocking)

- `say_once` keys the error path on the constant `"error"`, so a second, different failure after the first is silent until the state changes. Note only.