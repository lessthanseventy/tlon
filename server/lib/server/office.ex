defmodule Server.Office do
  @moduledoc """
  The office's read models — what the desktop rail and the office TUI draw: one snapshot of every
  workspace (`status/0`) and a close look at one thread (`thread_view/1`). Plain maps, JSON-ready;
  served at `GET /api/office` and `GET /api/office/threads/:id` (`Server.MCP.OperatorAPI`) and by
  `scripts/tlon-cli.sh shell-status` / `shell-thread`, so every surface reads the same function.
  """

  import Ecto.Query

  alias Server.Repo

  @consult_window_s 180

  @doc """
  Every workspace at once: the roster (each row with its thread's workspace and bench seat), the
  benches with their policies, the open threads (lead, whether a window runs it, whether it is the
  workspace's standing thread, any open prompt), projects, unstarted tickets, notes, the consults
  and hand-offs of the last three minutes, the archetypes and model choices, counts, and how many
  threads await the operator. A surface shows one workspace and filters by `workspace_id`.
  """
  @spec status() :: map()
  def status do
    wss = Server.Workspaces.all()
    ws_ids = Enum.map(wss, & &1.id)
    benches = Server.Workspaces.bench_by_workspace(ws_ids)
    projects = for ws <- ws_ids, p <- Server.Projects.in_workspace(ws), do: %{id: p.id, workspace_id: ws, name: p.name}
    prompts = Server.Attention.open_prompts_by_thread()

    %{
      roster: roster(benches),
      bench: bench(benches),
      threads: threads(ws_ids, prompts),
      projects: projects,
      tickets: tickets(ws_ids),
      notes: notes(projects),
      visits: visits(),
      workspaces: Enum.map(wss, &%{id: &1.id, name: &1.name}),
      archetypes: archetypes(),
      models: models(),
      counts: Map.new(Repo.all(from(t in Server.Thread, group_by: t.state, select: {t.state, count(t.id)}))),
      awaiting: awaiting(prompts)
    }
  end

  @doc """
  One thread up close: its last 60 messages, oldest first, and what its worker's pane shows now —
  the thread's own window, or the lead's window for a standing thread; `peek`/`window` nil when
  nothing runs it.
  """
  @spec thread_view(Server.Thread.t()) :: map()
  def thread_view(%Server.Thread{} = t) do
    messages =
      t
      |> Server.Channel.thread_messages()
      |> Enum.take(-60)
      |> Enum.map(&%{id: &1.id, author: &1.author, body: &1.body, at: &1.created_at, kind: &1.kind})

    tab = window_of(t)
    %{messages: messages, peek: tab && peek(t.workspace_id, tab), window: tab && tab.name}
  end

  defp window_of(t) do
    tabs = Server.Tmux.list_windows(t.workspace_id)

    Server.Tmux.leaf_tab(tabs, t.id) ||
      (standing?(t) && Server.Tmux.named(tabs, Server.Channel.thread_lead(t.id) || "")) || nil
  end

  defp standing?(t) do
    case Server.Channel.machine_thread(t.workspace_id) do
      nil -> false
      m -> m.id == t.id
    end
  end

  defp peek(ws, %{index: i}) do
    case Server.Tmux.run(ws, ["capture-pane", "-p", "-J", "-t", Server.Tmux.target(ws, i)]) do
      {out, 0} -> String.trim_trailing(out)
      _ -> nil
    end
  end

  defp roster(benches) do
    rows = Server.Staff.roster()
    thread_ws = rows |> Enum.map(& &1.thread_id) |> workspaces_of()
    everyone = List.flatten(Map.values(benches))

    Enum.map(rows, fn r ->
      ws = thread_ws[r.thread_id]
      seat = Enum.find(Map.get(benches, ws, []), &(&1.name == r.agent)) || Enum.find(everyone, &(&1.name == r.agent))

      %{
        agent: r.agent,
        thread_id: r.thread_id,
        title: r.thread_title,
        warm: r.warm?,
        workspace_id: ws,
        archetype: seat && seat.archetype,
        lead: !!(seat && seat.lead?)
      }
    end)
  end

  defp bench(benches) do
    for {ws, cs} <- benches, pols = Server.Workspaces.policies(ws), c <- cs do
      p = pols[c.agent_id]

      %{
        workspace_id: ws,
        seat_id: c.id,
        agent_id: c.agent_id,
        name: c.name,
        archetype: c.archetype,
        lead: c.lead?,
        model: p && p.model,
        ask: p && p.ask_default
      }
    end
  end

  # each open thread with its lead, whether a tmux window is running it (asked of tmux: a Claude
  # Code worker registers no session until it calls register, so the roster alone misses it), and
  # whether it is the standing thread of its workspace
  defp threads(ws_ids, prompts) do
    tabs = Map.new(ws_ids, &{&1, Server.Tmux.list_windows(&1)})

    standing =
      Map.new(ws_ids, fn ws ->
        {ws, with(%{id: id} <- Server.Channel.machine_thread(ws), do: id)}
      end)

    leads =
      Map.new(
        Repo.all(
          from(t in Server.Thread,
            join: a in Server.Agent,
            on: a.id == t.agent_id,
            where: t.state == "open",
            select: {t.id, a.name}
          )
        )
      )

    from(t in Server.Thread,
      where: t.state == "open",
      order_by: [desc: t.id],
      select: %{id: t.id, title: t.title, stage: t.stage, awaiting: t.awaiting, workspace_id: t.workspace_id}
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      ws_tabs = Map.get(tabs, t.workspace_id, [])
      std = standing[t.workspace_id] == t.id

      live =
        Server.Tmux.leaf_tab(ws_tabs, t.id) != nil or (std and Server.Tmux.named(ws_tabs, leads[t.id] || "") != nil)

      Map.merge(t, %{prompt: prompts[t.id], lead: leads[t.id], live: live, standing: std})
    end)
  end

  defp tickets(ws_ids) do
    for ws <- ws_ids, t <- Server.Tickets.open_in_workspace(ws), t.status != "doing" do
      %{
        id: t.id,
        workspace_id: ws,
        project_id: t.project_id,
        title: t.title,
        priority: t.priority,
        routed: t.status == "todo"
      }
    end
  end

  # notes, newest first, placed in a workspace by their scope (a global one in none)
  defp notes(projects) do
    proj_ws = Map.new(projects, &{&1.id, &1.workspace_id})
    rows = Repo.all(from(n in Server.Note, order_by: [desc: n.id], limit: 40))
    thread_ws = rows |> Enum.filter(&(&1.scope == "thread")) |> Enum.map(& &1.scope_id) |> workspaces_of()

    Enum.map(rows, fn n ->
      ws =
        case n.scope do
          "workspace" -> n.scope_id
          "project" -> proj_ws[n.scope_id]
          "thread" -> thread_ws[n.scope_id]
          _ -> nil
        end

      %{id: n.id, author: n.author, body: String.slice(n.body, 0, 400), workspace_id: ws, at: n.created_at}
    end)
  end

  # the consults of the last few minutes as who asked whom, and a manager staffing a child as a
  # hand-off to whoever they picked — for the office to walk them over
  defp visits do
    since = DateTime.add(DateTime.utc_now(), -@consult_window_s)

    consults =
      Repo.all(
        from(m in Server.Message,
          join: t in Server.Thread,
          on: t.id == m.thread_id,
          join: a in Server.Agent,
          on: a.id == t.agent_id,
          where: m.consult_id == m.id and m.created_at > ^since,
          select: %{from: m.author, to: a.name, workspace_id: t.workspace_id, at: m.created_at}
        )
      )

    handoffs =
      Repo.all(
        from(c in Server.Thread,
          join: p in Server.Thread,
          on: p.id == c.parent_thread_id,
          join: pa in Server.Agent,
          on: pa.id == p.agent_id,
          join: ca in Server.Agent,
          on: ca.id == c.agent_id,
          where: c.created_at > ^since,
          select: %{from: pa.name, to: ca.name, workspace_id: c.workspace_id, at: c.created_at}
        )
      )

    consults ++ handoffs
  end

  defp archetypes do
    for {k, t} <- Enum.sort(Server.Profiles.archetypes()) do
      %{
        name: to_string(k),
        meta: Server.Profiles.meta?(k),
        read_only: get_in(t, [:permissions, "permission", "write"]) == "deny",
        model: key(t.model)
      }
    end
  end

  defp models do
    env = Server.OperatorConfig.environment()

    for m <- Server.Profiles.model_choices() do
      %{
        key: key(m),
        provider: m.provider,
        model: m.model,
        thinking: m.thinking,
        harness: Server.Harness.resolve(m, env)
      }
    end
  end

  defp awaiting(prompts) do
    Repo.one(
      from(t in Server.Thread,
        where: t.state == "open" and (not is_nil(t.awaiting) or t.id in ^Map.keys(prompts)),
        select: count(t.id)
      )
    )
  end

  defp workspaces_of(thread_ids) do
    Map.new(Repo.all(from(t in Server.Thread, where: t.id in ^thread_ids, select: {t.id, t.workspace_id})))
  end

  defp key(m), do: "#{m.provider}/#{m.model}"
end
