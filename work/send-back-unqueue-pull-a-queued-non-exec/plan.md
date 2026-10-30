# Plan — send_back `unqueue` (#569)

Goal: `Workline.send_back(thread, to, why, by, unqueue: true)` pulls a queued (not executing) landing and
sends the thread back in ONE transaction, so `requeue_stranded/0` (stage `review` only) has nothing to
re-queue. No new verb; three surfaces call the one function. Leave `office/needs.ex` and `needs_test.exs`
alone (PR #675); reading `Needs.landing?` is fine. Run Elixir through `~/projects/menard/bin/menard`
(`edit`, `run test --in server FILE`), never sed/python.

Facts the builder can rely on (all in `server/`):
- `lib/server/workline.ex`: `send_back/4` (~l.1049) builds `allowed` and hands it to `move_back/6`, which
  runs `allowed` on the thread row locked FOR UPDATE inside `Repo.transaction`; `{:error, r}` rolls back.
  `not_in_flight/1` (~l.1932) refuses on any `verify`/`landing` Oban job in
  available|scheduled|executing|retryable for `args->>'thread_id'`.
- `Server.Jobs.Land` has `unique: [..., states: [:available, :scheduled, :executing]]`, so a cancelled
  job does not block a later approval's enqueue.
- Tests: `test/server/workline_send_back_test.exs` (helper `at_review/1`; a queued landing is
  `%{thread_id: id} |> Server.Jobs.Land.new() |> Repo.insert!()`; Oban is `testing: :manual`).

## Task 1 — the core: `unqueue:` in `Workline.send_back` (one commit)

Files: `server/test/server/workline_send_back_test.exs`, `server/lib/server/workline.ex`.

Tests first (new `describe "unqueue"` in the send-back test module; red before the code):
1. Assumption pin: `Oban.cancel_job(job.id)` inside `Repo.transaction(fn -> ...; Repo.rollback(:x) end)`
   leaves the job `available` (cancel joins the caller's transaction). If this is red, STOP and tell
   the thread: the whole design needs another lock.
2. Available Land job + `unqueue: true` by `"hronir"` (tech lead) → `{:ok, %{stage: "build"}}`, job
   `state == "cancelled"`, and `Workline.requeue_stranded() == []`.
3. Executing job (`Repo.update_all` its state to `"executing"`) + `unqueue: true` →
   `{:error, {:in_flight, _}}`, job still `executing`, thread still `review`.
4. No `unqueue` → refused as today (existing test at l.101 stays green, unchanged).
5. A queued `verify` job + `unqueue: true` → `{:error, {:in_flight, _}}`, job untouched
   (insert via `Server.Jobs.Verify.new(%{thread_id: id, slug: slug})`).
6. Not permitted (`by: "stranger"`, `unqueue: true`) → `{:error, {:not_yours, _}}` and the job is still
   `available` (cancel runs only after every check passes).
7. After test 2, `Workline.approve` again enqueues a fresh Land job (unique does not block): assert a new
   `available` Land job exists for the thread once it is back at review.
   Keep this one only if it needs ≤10 lines with the existing helpers; otherwise assert the cheaper
   `Server.Jobs.Land.new(%{thread_id: id}) |> Repo.insert!()` yields `conflict? == false`.

Code (`workline.ex`): `send_back/4` → `send_back/5` with `opts \\ []`, and update its `@doc` (drop "not
while ... landing is queued or running" to say a queued landing is pulled with `unqueue: true`; a running
landing and any verify still refuse; spec list gains opts):

```elixir
def send_back(%Thread{} = thread, to, why, by, opts \\ []) do
  unqueue? = Keyword.get(opts, :unqueue, false)

  allowed = fn locked ->
    with :ok <- movable(locked),
         :ok <- not_in_flight(locked, unqueue?),
         :ok <- behind(locked, to),
         :ok <- may_send_back(locked, to, by),
         do: if(unqueue?, do: cancel_landings(locked), else: :ok)
  end

  move_back(thread, to, "sent back by #{by}: #{why}", send_back_brief(to, why, by), allowed, by)
end
```

Replace `not_in_flight/1` with `/2`:

```elixir
defp not_in_flight(thread, unqueue?) do
  jobs =
    Repo.all(
      from j in Oban.Job,
        where:
          j.queue in ["verify", "landing"] and j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("?->>'thread_id'", j.args) == ^to_string(thread.id),
        select: {j.queue, j.state}
    )

  blocking =
    if unqueue?,
      do: Enum.filter(jobs, fn {q, s} -> q == "verify" or s == "executing" end),
      else: jobs

  case blocking do
    [] -> :ok
    [{q, _} | _] -> {:error, {:in_flight, "its #{if q == "verify", do: "verify", else: "landing"} is queued or running; let it finish"}}
  end
end

# Inside move_back's transaction and under the thread row's lock. The one window left: a landing job
# that starts executing between not_in_flight's select and this cancel — Land takes the same row lock
# (see move_back), so it waits on us, then finds the thread moved and does nothing.
defp cancel_landings(thread) do
  ids =
    Repo.all(
      from j in Oban.Job,
        where:
          j.queue == "landing" and j.state in ["available", "scheduled", "retryable"] and
            fragment("?->>'thread_id'", j.args) == ^to_string(thread.id),
        select: j.id
    )

  Enum.each(ids, &Oban.cancel_job/1)
end
```
(`cancel_landings` returns `:ok` via `Enum.each`.) Builder: confirm in Oban's source (`deps/oban`) that
`cancel_job/1` on a non-executing job is one `update_all` through the configured Repo (so it joins the
transaction — task test 1 proves it) and that it sends no notifier message that matters for a queued job.

Verify: `~/projects/menard/bin/menard run test --in server test/server/workline_send_back_test.exs` green;
commit "Workline.send_back: unqueue pulls a queued landing in the same transaction (#569)".

## Task 2 — MCP tool `send_back`

Files: `server/lib/server/mcp/tools/workline.ex` (`Server.MCP.Tool.SendBack`, ~l.219),
`server/test/server/mcp/server_test.exs` (find the existing send_back case with `grep -n send_back`).

Test first: calling `send_back` with `unqueue: true` on a review thread holding a queued Land job returns
ok / stage build and the job is cancelled; without it the old refusal text is unchanged.

Code: add `field :unqueue, :boolean, description: "Pull a queued (not running) landing in the same step; a running landing or a verify still refuses"`
to the schema; call `Workline.send_back(thread, params[:stage], params[:why], identity.agent, unqueue: params[:unqueue] == true)`.
`may_send_back/3` unchanged. Update the moduledoc with one line.

Verify: the touched test file green via menard; commit.

## Task 3 — operator API `POST /api/threads/:id/send_back`

Files: `server/lib/server/mcp/operator_api.ex` (docs l.70, handler ~l.559), its test (find with
`grep -rn send_back server/test/server/mcp/`; add beside the existing one, else
`gateway_test.exs`).

Test first: body `{"stage":"build","why":"x","unqueue":true}` on a review thread with a queued Land job →
200, job cancelled; the same body without `unqueue` → the existing in-flight refusal.

Code: pass `unqueue: b["unqueue"] == true` as the 5th arg; add `"unqueue"` to the route's doc comment.

Verify: that test green; commit.

## Task 4 — `tlon-cli.sh send-back --unqueue`

Files: `scripts/tlon-cli.sh` (`send-back)` case, ~l.577); its script test if one exists
(`grep -rn "send-back" scripts/ server/test | head`; if none, no test file is invented).

Code: accept an optional `--unqueue` right after the stage:
```bash
send-back)
  tid="${1:-}"; to="${2:-}"; shift 2 2>/dev/null || true
  unq=false; if [ "${1:-}" = "--unqueue" ]; then unq=true; shift; fi
  ...usage: tlon-cli.sh send-back <thread-id> spec|plan|build [--unqueue] <why…>
  ... Server.Workline.send_back(t, "$to", "$(esc "$*")", Application.get_env(:server, :operator, "andrew"), unqueue: $unq)
```
(`$unq` is the literal `true`/`false`, a valid Elixir boolean.)

Verify: `bash -n scripts/tlon-cli.sh`; usage line printed by `scripts/tlon-cli.sh send-back` (exit 2).
Commit.

## Task 5 — docs + end to end

- `grep -rn "send_back\|send-back" docs AGENTS.md server/AGENTS.md server/docs 2>/dev/null` — add `--unqueue`
  where the verb is described; update only what is already there.
- Live check after the release is cut (outside the build): queue a real landing, then
  `scripts/tlon-cli.sh send-back <tid> build --unqueue <why>`; expect "sent back — thread #N now at build",
  the Land job `cancelled` in `oban_jobs`, and the next `requeue_stranded` tick does not re-queue it. That
  retires the hand rpc in hronir #11839.
- Gate: `~/projects/menard/bin/menard run check --in server` green on the branch, then `advance_stage`.

## Notes
- Limit surface (merge queue + operator API): the gate goes to the operator; do not self-approve.
- Do not touch `Needs`, `requeue_stranded` or Land: the fix is that the thread has left `review`.
