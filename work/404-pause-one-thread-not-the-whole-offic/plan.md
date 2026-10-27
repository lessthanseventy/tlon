# #404 plan — pause one thread

Spec: `spec.md` beside this. Start only once #384 (#403) is on main (same files, other functions);
rebase onto main first. All paths are under `server/`. Run tests with `menard run test <file>`;
the final gate is `mise run check`. Every task = failing test first, then code, then its own commit.

Shared test setup (tasks 2–6): copy the `setup` block and the `bodies/1` helper from
`test/server/pause_test.exs` (operator_config_path tmp file, `Server.TestDB.clean!()`, a workspace,
a lobby, a `busy` thread with an `emma` session). Name the new file `test/server/thread_pause_test.exs`,
module `Server.ThreadPauseTest`, `use ExUnit.Case, async: false`. Do not extract a shared helper (YAGNI).

## Task 1 — the mark (migration + schema), needs operator approval (limit gate)

Files: new `priv/repo/migrations/20261027080000_thread_paused_at.exs`, edit `lib/server/thread.ex`.

```elixir
defmodule Server.Repo.Migrations.ThreadPausedAt do
  @moduledoc false
  use Ecto.Migration

  # A thread the operator paused on its own (Server.Pause.pause_thread/1). Not a `state`: a paused
  # thread stays "open" to every query.
  def change do
    alter table(:thread) do
      add :paused_at, :utc_datetime
    end
  end
end
```

In `Server.Thread`'s schema, after `memory_pass_last_id`:

```elixir
    # set while the operator has paused this one thread (Server.Pause); nil = not paused
    field :paused_at, :utc_datetime
```

Test (first, in `thread_pause_test.exs`): `Server.Repo.get(Server.Thread, busy.id).paused_at == nil`
(red: unknown field). Done: `menard run test test/server/thread_pause_test.exs` green; commit
"thread: paused_at mark".

## Task 2 — Pause API: pause_thread / resume_thread / thread_paused?

File: `lib/server/pause.ex`. Tests first, in `thread_pause_test.exs`:

1. `Pause.pause_thread(busy.id)` returns `{:ok, thread}` with `paused_at` set, `thread_paused?(busy.id)`
   true, `thread_paused?(quiet.id)` false; `bodies(busy)` has one `"✎ paused — finish this turn…"`
   notice (kind "notice"); calling it again adds no second notice. The lobby is not told.
2. `Pause.resume_thread(busy.id)` clears the mark and posts one chat by `"tlon"` on `busy` starting
   `"@emma ▶ back to work"` (emma leads it: `Channel.thread_lead/1`). Resuming a not-paused thread
   returns `{:ok, thread}` and posts nothing.
3. A missing id returns `{:error, :not_found}`; a closed thread `{:error, :not_open}`.
4. Interplay: with a thread paused, `Pause.pencils_down()` does not tell it again, and
   `Pause.back_to_work()` does not wake its lead nor clear the mark (operator decision).

Code. The tell/wake bodies are split out of the office-wide loops (they take one thread now):

```elixir
  @thread_told "✎ paused — finish this turn"

  @doc "Whether the operator has paused this one thread."
  def thread_paused?(thread_id),
    do: Server.Repo.exists?(from t in Server.Thread, where: t.id == ^thread_id and not is_nil(t.paused_at))

  @doc "Every thread paused on its own, as a set: one query for a list of candidates."
  def paused_thread_ids do
    from(t in Server.Thread, where: not is_nil(t.paused_at), select: t.id) |> Server.Repo.all() |> MapSet.new()
  end

  @doc "Pause one thread: its lead is told to finish the turn; nothing but the operator's posts wakes it until resumed."
  def pause_thread(thread_id) do
    with {:ok, thread} <- open_thread(thread_id) do
      if thread.paused_at do
        {:ok, thread}
      else
        {:ok, thread} = thread |> Ecto.Changeset.change(paused_at: DateTime.truncate(DateTime.utc_now(), :second)) |> Server.Repo.update()
        tell(thread_id, @thread_told)
        {:ok, thread}
      end
    end
  end

  @doc "Undo `pause_thread/1`: clear the mark, deliver what was held, wake the lead. Order matters: the mark goes first, or the wake itself is held."
  def resume_thread(thread_id) do
    with {:ok, thread} <- open_thread(thread_id) do
      if thread.paused_at do
        {:ok, thread} = thread |> Ecto.Changeset.change(paused_at: nil) |> Server.Repo.update()
        wake(thread_id)
        Server.Switchboard.drain()
        {:ok, thread}
      else
        {:ok, thread}
      end
    end
  end

  defp open_thread(thread_id) do
    case Server.Repo.get(Server.Thread, thread_id) do
      nil -> {:error, :not_found}
      %Server.Thread{state: "open"} = thread -> {:ok, thread}
      _ -> {:error, :not_open}
    end
  end
```

Refactor the two private loops to use shared one-thread helpers (behaviour unchanged for the office):

```elixir
  defp tell_live_threads do
    for tid <- live_threads(), do: tell(tid, @told)
  end

  defp tell(tid, head) do
    body = head <> ", commit what you have, and stop; don't start anything new. You'll hear when it's back to work."
    _ = Channel.post(%{thread_id: tid, author: "tlon", body: body, kind: "notice"})
  end

  defp wake_stopped_threads, do: for(tid <- stopped_threads(), do: wake(tid))

  defp wake(tid) do
    with lead when lead != nil <- Channel.thread_lead(tid) do
      _ = Channel.post(%{thread_id: tid, author: "tlon", body: "@#{lead} ▶ back to work — pick up where you stopped, from the brief."})
    end
  end
```

(`wake/1` keeps the comment "runs before the lobby's back-to-work notice".) In `stopped_threads/0` and
`live_threads/0` add `and is_nil(t.paused_at)` to the `where:` so the office never tells or wakes a
thread that is paused on its own. `@thread_told` differs from `@told` so `stopped_threads` never sees
it. Update the moduledoc with one paragraph on the per-thread pause. Done: the new tests plus the whole
`test/server/pause_test.exs` green; commit "pause: pause and resume one thread".

## Task 3 — hold delivery

File: `lib/server/switchboard.ex`, replace `paused_for?/1` (end of file):

```elixir
  defp paused_for?(%Message{author: author, thread_id: thread_id}),
    do:
      not Server.Channel.operator?(author) and
        (Server.Pause.state() != :working or Server.Pause.thread_paused?(thread_id))
```

Also extend the comment above `deliver/1`'s condition: "…or a paused thread holds every wake but the
operator's own." Tests first (`thread_pause_test.exs`), using the pattern of `pause_test.exs:177`:

1. With `busy` paused, `Switchboard.deliver(msg)` of a chat by `emma` on `busy` returns `{:pending, _}`;
   the same on `quiet` (not paused) is not held (`{:pending,_}` only because nobody is warm — assert
   by posting on a thread with a session instead: use a second live thread and assert it is delivered).
2. An operator-authored post (`Server.Channel.operator()` as author) on the paused `busy` is not held.
3. After `resume_thread(busy.id)`, the held message has `delivered_at` set (drain re-delivered it).

Done: tests green; commit "switchboard: hold a paused thread's wakes".

## Task 4 — excuse the nudges

Three one-line changes, each with a test first:

- `lib/server/workline/continuation.ex`, in `run/2`'s `with`, right after `false <- Server.Blocked.blocked?(thread_id),`:
  `false <- Server.Pause.thread_paused?(thread_id),`
  Test (add to `test/server/workline_continuation_test.exs` beside its Blocked test; copy that test's setup):
  a workline that gets a nudge when not paused gets none after `pause_thread`.
- `lib/server/office/needs.ex` `stalled/2`: add `paused = Server.Pause.paused_thread_ids()` under `blocked = …`
  and `not MapSet.member?(paused, t.id),` under the `blocked` filter. Test beside the existing Blocked
  stalled test (grep `Blocked` in `test/server/office/`): stalled item present, then absent once paused.
- `lib/server/wake.ex` `report_overdue/1`, in the `with` after the `%Server.Thread{state: "open"} = thread <-` line:
  `false <- Server.Pause.thread_paused?(w.thread_id),`
  Test in `test/server/wake_test.exs` next to the existing report_overdue case: unpaged when paused.

Done: the three test files green; one commit "pause: a paused thread owes no nudge, stalled Need or wake alert".

## Task 5 — refuse staffing a child of a paused thread

File: `lib/server/mcp/tools/coordination.ex`. In `execute/2`'s `with`, after `:ok <- paused(),` add
`:ok <- parent_active(parent),`; next to `paused/0` add:

```elixir
  defp parent_active(%{id: id}),
    do: if(Server.Pause.thread_paused?(id), do: {:paused, "thread ##{id} is paused: resume it first"}, else: :ok)

  defp parent_active(_unbound), do: :ok
```

The existing `{:paused, line}` branch already fails with `staff_child refused: <line>`. Test first
(follow the existing office-pause staff_child test; grep `staff_child refused` in `test/`): a lead on a
paused thread calling staff_child gets `"staff_child refused: thread N is paused: resume it first"`;
after resume it succeeds. Done: green; commit "staff_child: refuse a paused parent".

## Task 6 — operator_api routes

File: `lib/server/mcp/operator_api.ex`. Add the two lines to the moduledoc route list next to
`POST /api/office/pause` (line ~122):

```
      POST   /api/threads/:id/pause    → Server.Pause.pause_thread/1: {thread_id, paused: true}
      POST   /api/threads/:id/resume   → Server.Pause.resume_thread/1: {thread_id, paused: false}
```

and beside the other `on_thread(conn, "POST", …)` clauses:

```elixir
  defp on_thread(conn, "POST", ["pause"], t), do: paused(conn, Server.Pause.pause_thread(t.id))
  defp on_thread(conn, "POST", ["resume"], t), do: paused(conn, Server.Pause.resume_thread(t.id))

  defp paused(conn, {:ok, thread}), do: json(conn, 200, %{thread_id: thread.id, paused: thread.paused_at != nil})
  defp paused(conn, {:error, why}), do: json(conn, 409, %{error: "cannot pause or resume: #{why}"})
```

(`with_thread` already 404s a missing id; the 409 is for a closed thread. Rename `paused/2` if it
collides with an existing function — compile will say.) Test first, in the file that tests operator
routes (`grep -rln OperatorAPI test`, found `test/server/mcp/gateway_test.exs`): POST pause → 200
`paused: true`; POST resume → `paused: false`; POST pause on a closed thread → 409. Done: green; commit
"operator_api: pause and resume one thread".

## Final gate

`mise run check` green from the worktree. Out of scope (file as a junior follow-up ticket, not here):
the office TUI key for pause/resume. The migration is a limit gate: pass it up with this plan's
recommendation, don't approve it yourself.
