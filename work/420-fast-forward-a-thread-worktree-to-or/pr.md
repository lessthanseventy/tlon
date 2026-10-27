Fast-forward a thread worktree to origin/main on wake. Closes #420.

A thread checkout on a branch with no commit of its own sat on its birth commit forever. Now a spawn (`Spawn.cwd_export`, bench agents only) calls `Server.catch_up_worktree/2` → the new `Server.Worktree.catch_up/1`: a branch, clean tree, HEAD an ancestor of origin/main → `merge --ff-only origin/main`. Detached HEAD (verify-frozen) is skipped. A dirty tree, or own commits while main has moved on, is left alone and told to the thread as a notice once per state (remembered in the checkout's git dir, `tlon-reported`, reset when the checkout catches up). A `{:error, _}` is logged. No fetch: KeepUp keeps origin/main fresh.

Wake-only by design: `Server.worktree_for_thread` is hit mid-turn by tools and gates, where a move would land under a live pane, so the facade does not move anything.

Checked: `menard run test --in server` on worktree_test.exs and mcp/spawn_test.exs — 60 tests, 0 failures (RED first). The full gate is for verify; a seat can't run it.
