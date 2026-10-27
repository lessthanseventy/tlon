**Verdict: approve** — 473cc57 on work/worktree-for-thread-293-drive-smoke-dies (reviewer: lonnrot; the previous round's verdict at 895714d was ulrikke's, not mine, so I read the whole branch diff against main, not only the delta).

The previous round's four requests, checked against the diff since 895714d:

1. Docstring: now reads `an existing checkout is checked and repaired if its gitfile does not resolve, otherwise returned as is`. Fixed.
2. Lock: `:global.trans({{__MODULE__, path(Path.expand(repo_path), slug)}, self()}, fn -> do_ensure(repo_path, slug) end, [node()])`. Keyed on the expanded path, scoped to this node. Fixed.
3. Lock comment ends `a gitfile to nowhere`, no ticket ref. Fixed.
4. Describe label is `ensure/2 — a checkout's gitfile always resolves`. Fixed. The "double blank line" was never in the file; the context lines around the label show one blank, as the builder said.

The change itself, read whole:

- `do_ensure` routes an existing checkout through `resolve(repo_path, wt)` and a fresh one through `add` then `resolve`, with `seed_deps` only after both. `resolve` runs `rev-parse --git-dir` in the checkout, and on failure `worktree repair wt` from the repo then re-checks; a repair that doesn't take returns `{:error, "worktree gitfile does not resolve: …"}`. Honest error, no raise, per the module's own contract.
- Nothing else in server/lib or scripts runs `git worktree add` on `.worktrees/<slug>`: `Server.Workline.Merge` adds a tmp path, the scripts add their own detached dirs. Only `Server.Worktree.ensure` (via `worktree_for_thread` and `Scribe`) writes that path, and both go through the lock.
- The ticket's "sandbox allowlist names `<slug>1`" symptom is downstream: `adapters/claude-code/launch.sh` reads the gitdir with `rev-parse` at launch, after `Server.MCP.Spawn` has called `worktree_for_thread`, so a repaired gitfile is what the allowlist gets.

Verified by me, in this seat:
- `menard run test --in server test/server/worktree_test.exs`: `{"ok":true,"tests":36,"failed":0}`.
- The server's `mise run check` on 473cc57 passed (brief, 16:24:35Z).
- I did not re-run the concurrency test without the lock; that it went red first is the builder's claim.

No bench_contrast row among the checks the brief shows (five of nine), so no contrast finding from me.

Already filed, not re-listed as a follow-up: ticket 681, `rename/3`, `remove/2`, `retire/2` don't take the lock.

Handing to the merge gate.