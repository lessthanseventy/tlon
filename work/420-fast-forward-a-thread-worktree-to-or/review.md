# Review — workline 420-fast-forward-a-thread-worktree-to-or @ 7a8c8e4 (round 4)

**Verdict: request_changes.** The two follow-ups from round 3 are fixed and fixed well. The two *blocking findings* of round 3 are untouched: `git diff f779c33..7a8c8e4` changes `server.ex`, `worktree.ex`, `worktree_test.exs` only; `spawn.ex` and the outside-citizen test are byte-identical to e82312e. emma's note (#15384) calls them "the grader's other suggestions" and declines them. They are not the grader's; they are findings 1 and 2 of review.md at f779c33, and finding 1 is the case the tech lead ruled out in #15362 ("a fast-forward mid-turn under a live pane is what I don't want"). Verify's `mise run check` passed on 7a8c8e4 (exit 0, 14:15:31Z); no bench_contrast row among the CHECKS shown.

## Fixed since round 3

- `tell_catch_up({:ahead, n}, …)` goes through `Worktree.moved_past/1`, which uses `git/2`, and stays quiet on a failed `rev-list` (`:no`). Test "own commits are not told when git cannot say whether main moved" injects a 128 on `HEAD..origin/main` and asserts no line.
- `{:error, why}` is told once as a notice via `say_once(wt, thread, "error", …)` as well as logged. Test injects `index.lock` on `merge`, calls twice, asserts exactly one notice.

## Still blocking (unchanged from round 3)

1. **A rider join moves the checkout under the lead's live pane.** `cwd_export/2` (spawn.ex:168) calls `catch_up_worktree` for every non-outside join. Three production callers join with `assign: false`: `Server.Crew.Tmux` (crew/tmux.ex:49, a `spawn_crew` the lead calls mid-turn), `Server.Switchboard` (switchboard.ex:368) and `Coordination.seat/2` (coordination.ex:177). A crew spawn is the lead's own tool call, so a clean checkout at an older main gets `merge --ff-only` while the lead is mid-turn. Patch:

```
server/lib/server/mcp/spawn.ex
-         {:ok, cwd} <- cwd_export(thread, agent) do
+         {:ok, cwd} <- cwd_export(thread, agent, opts) do
…
-  defp cwd_export(thread, agent) do
+  defp cwd_export(thread, agent, opts) do
…
-        if agent.name not in Server.Outside.names(), do: Server.catch_up_worktree(thread, path)
+        if Keyword.get(opts, :assign, true) and agent.name not in Server.Outside.names(),
+          do: Server.catch_up_worktree(thread, path)
```

RED test first, a copy of spawn_test.exs:109 that joins with `assign: false` after main moves and does `refute File.exists?(Path.join(wt, "NEW"))`. It fails on 7a8c8e4.

2. **The Outside guard is unpinned.** spawn_test.exs:142 has no origin remote, so `catch_up/1` returns `:level` with or without the `not in Server.Outside.names()` guard; delete the guard and the suite stays green. Pin it: in that test add the remote, push main, `git reset --hard HEAD~1` in the repo so its main is a clean ancestor of origin/main, fetch, join the outside citizen, and assert `rev-parse HEAD` of the repo is unchanged. Without the guard that test fast-forwards the live main checkout, which is the one thing this feature must never do.

## Follow-ups (not blocking)

- `say_once` keys the error path on the constant `"error"`, so a second, different failure after the first is silent until the state changes. Keying on a hash of `why` would re-tell it; low value, note only.