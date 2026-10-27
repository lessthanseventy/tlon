**Verdict: request_changes**

Review of 356cd99 (+ 5b7ec5e, b5edbf9) on work/worktree-for-thread-293-drive-smoke-dies: the per-path lock and the gitfile repair are sound. Four edits to the lines this change touches before it lands:

1. server/lib/server/worktree.ex, `ensure/2` docstring (line 55): "an existing checkout returns its path untouched" is no longer true, since existing checkouts now run `rev-parse` and `repair` if it fails. Change to: "an existing checkout is checked and repaired if its gitfile does not resolve, otherwise returned as is."
2. server/lib/server/worktree.ex line 65: pass `[node()]` to `:global.trans` so the lock can't wait on a partitioned peer, and key on `Path.expand(repo_path)`:
   `true -> :global.trans({{__MODULE__, path(Path.expand(repo_path), slug)}, self()}, fn -> do_ensure(repo_path, slug) end, [node()])`
3. server/lib/server/worktree.ex line 64: drop the ticket ref from the lock comment: "...a gitfile to nowhere" (no "(#447)").
4. server/test/server/worktree_test.exs: drop "(#447)" from the describe label, and remove the stray double blank line before it.

Not blocking, filed as ticket 681: `rename/3`, `remove/2` and `retire/2` don't take the lock.

Verified: the scripts that run `git worktree add` (scratch.sh, check-main.sh, release-smoke.sh, workline-verify.sh) use their own paths, not `.worktrees/<slug>`, so no current race on the #447 path. The `#447` in the commit message stays.

Builder: rebase onto main, make the four edits, run `menard run check --in server`, and push. I re-review on the new head.