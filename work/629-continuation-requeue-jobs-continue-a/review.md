Verdict: request_changes. Reviewed 92fe705 (the diff since 2e5a83f plus the whole branch against ebf276c); run, not only read.

1. **Fixed: the quiet nudge survives the requeue.** `{:later, at} -> requeue(thread_id, at, opts[:quiet] == true)`; `Continue.perform` passes `quiet: args["quiet"] == true`. ulrikke's blocker is closed, with tests.

2. **Blocker: the requeued check swallows its own re-requeue.** `requeue/3` inserts with
`unique = [period: gap + 60, keys: [:thread_id, :quiet], states: [:available, :scheduled, :executing]]`.
Oban's unique query (`deps/oban/lib/oban/engines/basic.ex:487`, `unique_query/1`) matches any job in those states inserted within the period and does not exclude the inserting job. The requeued check was inserted one gap before it runs, inside `period`. When it runs and `gap_wait` says `{:later, _}` again (the lead posted inside the gap), its `requeue` finds itself (state executing) and returns the conflict; nothing is scheduled. The nudge waits for the hourly sweep: the fault #629 set out to close, in the gap's own case (an active lead).

Evidence (scratch test against this worktree's test db, `mise x -- mix test`): executing `Continue` job for the thread, `quiet: true`, `inserted_at` now-9min; lead posts; `Continuation.run(t.id, artifacts: Present, quiet: true)` → `:ok`, scheduled Continue jobs for the thread: `[]`. The same insert with `states: [:available, :scheduled]` → `conflict?: false`, `state: "scheduled"`. With the branch's states → `conflict?: true`, `state: "executing"`. The branch's own 29 tests in `workline_continuation_test.exs` pass.

Fix (one token) in `server/lib/server/workline/continuation.ex`, `requeue/3`:
```
-    unique = [period: period, keys: [:thread_id, :quiet], states: [:available, :scheduled, :executing]]
+    unique = [period: period, keys: [:thread_id, :quiet], states: [:available, :scheduled]]
```
A sweep that runs while the check executes may then add one scheduled job beside it; the gap caps nudges and the next sweep dedupes against that scheduled one, so nothing multiplies.

Red-first test, in `describe "spacing"` of `server/test/server/workline_continuation_test.exs` (gap 10, thread opened 11 min ago):
```elixir
    test "the requeued check, run while the lead spoke inside the gap, is requeued again, not swallowed by itself", %{thread: t} do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      {:ok, a} = Server.Staff.register_agent(%{name: "hronir", mandate: "builds", engine: "claude-code"})
      {:ok, _} = Server.Staff.assign(Repo.get!(Server.Thread, t.id), a)
      # the check requeued 9 minutes ago is the one running now
      {:ok, job} = Server.Jobs.enqueue(Server.Jobs.Continue.new(%{thread_id: t.id, quiet: true}, scheduled_at: DateTime.utc_now()))
      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
        set: [state: "executing", inserted_at: DateTime.add(DateTime.utc_now(), -9 * 60), attempted_at: DateTime.utc_now()])
      {:ok, _} = Server.Channel.post(%{thread_id: t.id, author: "hronir", body: "still on it"})

      :ok = Continuation.run(t.id, artifacts: Present, quiet: true)

      scheduled =
        from(j in Oban.Job,
          where: j.worker == "Server.Jobs.Continue" and j.state == "scheduled" and
            fragment("(? ->> 'thread_id')::bigint", j.args) == ^t.id)

      assert [_] = Repo.all(scheduled)
    end
```
Red on 92fe705 (`[]`), green with the one-token change. Update the `requeue` comment to say the executing check is not a duplicate of its own requeue.

3. Spec: the rest holds. `gap_wait` returns the later of last nudge and lead's last post plus the gap; `lead_last_post_at` on `agent_id: nil` is epoch, so an unled thread never waits; gap 0 is `:go`. The `maintain_test` default-gap test and the lead-post-one-gap test cover the regressions the plan named. CHECKS: `menard run check --in server` 2500/0 and `mise run check` green on 92fe705; no bench_contrast row.