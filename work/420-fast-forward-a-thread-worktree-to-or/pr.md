Fast-forward a thread worktree to origin/main on wake. Closes #420.

A thread checkout on a branch with no commit of its own sat on its birth commit forever. Now `Server.worktree_for_thread` (the wake path) calls the new `Server.Worktree.catch_up/1`: a branch, clean tree, HEAD an ancestor of origin/main → `merge --ff-only origin/main`. Detached HEAD (verify-frozen) is skipped. Own commits or a dirty tree are left alone and told to the thread once per state (tip+ahead count / dirty), remembered in the checkout's git dir (`tlon-reported`) so a lobby wake doesn't repeat it. No fetch: KeepUp keeps origin/main fresh.

Deviation: the hook is in the facade, not `ensure/2` — `ensure` has no thread to post to; the facade is the single wake door anyway.

Checked: `menard run test --in server test/server/worktree_test.exs` — 40 tests, 0 failures (6 new, RED first: undefined `catch_up/1`). The full gate is for verify; a seat can't run it (no checks queue; an overlapping run on the shared test DB gave FK noise).
