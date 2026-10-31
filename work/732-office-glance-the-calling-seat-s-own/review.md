# Review: 732-office-glance-the-calling-seat-s-own @ ce002af

**Verdict: request_changes.** The shape is what tertius asked for (option 2: `me` added, `crew` untouched, a moduledoc line), the test is red-then-green, and verify's full `mise run check` is green. One finding blocks: `me` is not reliably the caller's row.

## 1. `me` is the agent's newest session anywhere in the workspace, not the caller's thread (blocking)

The witness:

```elixir
defp me(ws, me), do: Enum.find(rows(ws), &(&1.agent == me))
```

`rows/1` is `Server.Office.roster/1`, which is `Server.Staff.roster/0` filtered to the workspace: one row per **live session**, `order_by: [desc: s.id]`. The uniqueness index is `session_one_live_per_thread_agent ON session (thread_id, agent_id)`, so one agent holds a live row on every thread it is seated on. That is the normal case for a lead: a lobby session on the standing thread and one on each workline it was staffed to. `Enum.find` on agent alone then returns whichever of those sessions is newest, and after a lobby respawn (staffing rolls panes between turns) that is the lobby row, with the lobby's `thread_id`, `doing` and `status`, not the caller's. The ticket's need was "a seat checks its own presence through MCP"; for a multi-seated agent this field answers with another seat's presence. The glance already has `thread.id` in scope and the moduledoc says it is "scoped to the caller's workspace and thread", so match on both.

The new test passes because its agent has exactly one live session. The red test for the fix: give the caller a second, newer live session on another thread in the same workspace, and assert `me.thread_id == thread.id`.

## 2. `roster/1` runs twice per glance (fold into the fix)

`crew/2` and `me/2` each call `rows(ws)`, so every glance now does `Staff.roster` (a Repo query), `thinking()`, `Server.Tmux.list_windows` and `Attention.open_prompts_by_thread` twice. The mod reads the glance on a timer in every seat's window. Compute the rows once and split.

## Patch

Both findings in one change, `server/lib/server/mcp/tools/glance.ex`:

```elixir
  defp glance(%Thread{workspace_id: ws} = thread, agent) when is_integer(ws) do
    seat = Enum.find(Server.Workspaces.bench_all(ws), &(&1.name == agent))
    rows = rows(ws)

    %{
      archetype: seat && seat.archetype,
      crew: Enum.reject(rows, &(&1.agent == agent)),
      me: Enum.find(rows, &(&1.agent == agent and &1.thread_id == thread.id)),
      red: red(ws, thread.id),
      persona: persona(ws, agent),
      line: line(ws),
      landed: landed(ws)
    }
  end
```

and delete `crew/2` and `me/2` (`rows/1` stays as is). `crew` still drops every row of the caller's, on any thread, as before.

Red test, added to the new test in `server/test/server/mcp/server_test.exs` before the `handshake` (the second session is newer, so it sorts first and the current code picks it):

```elixir
    {:ok, other} = Channel.open_thread(%{title: "my other seat", workspace_id: ws.id})
    {:ok, _} = Staff.start_session(%{thread_id: other.id, agent_id: agent.id, pane_ref: "%9"})
```

The existing `assert ... tid == thread.id` then goes red on ce002af and green with the patch. Keep the `start_session` after `register` if the register call would otherwise end up on the wrong row; the order above should be fine since `register` binds to the token's thread.

## Checks read

- `mise run check` green on the branch (verify row 14:44:10Z); `tlon/check` not posted because the server's checkout had its own uncommitted state, which is the verifier's doing, not the branch's.
- No `bench_contrast` row: the diff touches no persona or skill, so none was owed.

## Nit, not a finding

The moduledoc line added is 130 columns wide; the rest of the block wraps near 100. Rewrap it when you are in the file.