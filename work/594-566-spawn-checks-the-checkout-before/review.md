# Review — 594-566-spawn-checks-the-checkout-before @ db25b2e

**Verdict: approve.**

The witness: `mint_and_export` now reads `resolve_thread → ensure_agent → checkout_or_close → maybe_assign`, and `cwd_export` has no `{:error, _} -> {:ok, ""}` left in it. That is the fix the tech lead asked for, in the order he asked for it.

## Findings

1. **Spec compliance — all four pins hold.** (a) refused `join(assign: true)` leaves `agent_id` as it was: `spawn_test.exs:210`; (b) refused `env` leaves no open thread: `:222`; (c) a non-`:not_a_checkout` worktree failure (`:not_a_repo`) on a repo thread refuses: `:237`; (d) no repo still exports nothing: the pre-existing `:271` ("no repo anywhere → no TLON_CWD line") still passes, because `checkout_for` maps only `{:error, :no_repo}` to `{:ok, nil}`. I checked `Projects.repo_for_thread`: `:no_repo` is the only error it returns, so the `{:error, _} = refused` arm is reached only through `Worktree.ensure` (`:bad_slug | :not_a_repo | reason`), as intended.

2. **The close on a refused `env` does close.** `Channel.close_thread(%{stage: nil})` consults `stranded_reason` first, which only bites when `<worktree>/.git` exists. Both refusal shapes that matter here (`:not_a_repo`, `:not_a_checkout`) mean no such `.git`, so it falls to `do_close`. Its side effects on a thread that is seconds old (`Tickets.done_for`, `report_to_parent`, `release_follow_ups`) are no-ops.

3. **Catch-up stays after the assign.** `cwd_export(thread, agent, path)` runs with the assigned thread, so its `agent.id == thread.agent_id` lead test is unchanged in meaning. Correct; the comment moved with it.

4. **Behaviour change for riders, intended.** The `assign: false` joins (switchboard wake spawn `switchboard.ex:368`, crew `crew/tmux.ex`, coordination `:211`) on a repo thread whose worktree fails any way now refuse instead of booting cwd-less. That is #566's ask, and the two read-dirs tests were rightly moved off `/nonexistent/a` onto a real `git init` repo for it.

5. **No bench_contrast row** in CHECKS (the diff touches no persona), so nothing to grade there. Verify: `mise run check` green at 21:41:58Z.

Non-blocking items are in follow_ups.