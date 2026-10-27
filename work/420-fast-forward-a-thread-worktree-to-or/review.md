# Review — workline 420-fast-forward-a-thread-worktree-to-or @ e82312e (round 3)

**Verdict: request_changes.** The grader's blast-radius point (msg #15376) holds, and I can name the pane it lands under. One fix, one test to pin it; the rest are follow-ups.

## Findings

1. **A rider join moves the checkout under the lead's live pane.** `cwd_export/2` runs `catch_up_worktree` for every non-outside join, staffing or not. Three production callers join with `assign: false` into the thread's worktree: `Server.Crew.Tmux` (a `spawn_crew` the lead calls mid-turn), `Server.Switchboard` (a benched agent or Aleph named on the thread) and `Coordination.seat/2`. A crew spawn is the lead's own tool call: a clean checkout at an older main gets `merge --ff-only` while the lead is still in its turn, which is the case `catch_up_worktree/2`'s docstring says the wake-only design exists to avoid (`a move would land under a live pane`). Fix: catch up only when the join staffs the thread, `Keyword.get(opts, :assign, true)`, passed into `cwd_export`. Test: in `spawn_test.exs`, after main moves, `Spawn.join(thread.id, "codex", assign: false)` and `refute File.exists?(Path.join(wt, "NEW"))`.

2. **The Outside guard is unpinned.** The existing outside-citizen test has no origin remote, so `catch_up/1` returns `:level` with or without the `not in Server.Outside.names()` guard; deleting the guard passes the suite. Add the remote-that-moved setup to that test and assert the repo's main checkout HEAD did not change.

## Follow-ups (not blocking)

- `tell_catch_up({:ahead, n}, …)` reads `HEAD` and `HEAD..origin/main` through bare `System.cmd`, not `git/2`. Correction to the grade: `System.cmd` does not raise on a non-zero exit, it returns `{out, code}`; it raises only when `git` is missing, and `Worktree.catch_up/1` would have returned `{:error, _}` before this clause. The real cost is the test seam (`:git_cmd` cannot reach these two) and that a failed rev-list reads as `"" != "0"`, so the ahead line is posted with no evidence main moved. Route both through a `Server.Worktree` helper.
- `{:error, why}` is a log line only; a spawn carries on with a stale checkout and nothing on the thread says so. Reaching it needs `merge --ff-only` to fail on a verified ancestor (a locked index, a merge in progress), so rare; a `say_once` notice would make it visible.

## Still true from round 2

Spec compliance and the first round's three fixes stand as reviewed at 14cc244. Verify's `mise run check` passed on e82312e; fix 1 changes `spawn.ex`, so the gate runs again.
