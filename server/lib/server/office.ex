defmodule Server.Office do
  @moduledoc """
  The office's read models — what the desktop rail and the office TUI draw: one snapshot of every
  workspace (`status/0`) and a close look at one thread (`thread_view/1`). Plain maps, JSON-ready;
  served at `GET /api/office` and `GET /api/office/threads/:id` (`Server.MCP.OperatorAPI`) and by
  `scripts/tlon-cli.sh shell-status` / `shell-thread`, so every surface reads the same function.
  """

  import Ecto.Query

  alias Server.Office.Room
  alias Server.Repo

  @consult_window_s 180
  @page 60

  @doc """
  Every workspace at once: the roster (each row with its thread's workspace, bench seat, and
  whether that agent is mid-turn), the benches with their policies, the open threads (lead,
  whether a window runs it, whether it is the workspace's standing thread, any open prompt, who is
  mid-turn on it, `seat`: its lead at a `"desk"` (a window runs it, or a warm session with a window to wake in), `"parked"` for a seat
  under the leaf cap (`Server.Staffing.parked_note?/1`) or `"idle"`, and `duty`: a standing duty,
  not work (`Server.Staffing.duty_threads/1`)), projects, unstarted tickets, notes, the consults and hand-offs of the last
  three minutes, the archetypes and model choices, counts, how many
  threads await the operator, each workspace's triage count (the beacon), the service's health
  (the rack), the days this month each workspace has something scheduled (the wall calendar),
  today's birthdays and anniversaries (`celebrations`, from the .ics feeds) and the feature flags
  (`Server.Flags.office/0`).
  A surface shows one workspace and filters by `workspace_id`.
  """
  @spec status() :: map()
  def status do
    wss = Server.Workspaces.all()
    ws_ids = Enum.map(wss, & &1.id)
    benches = Server.Workspaces.bench_by_workspace(ws_ids)
    projects = for ws <- ws_ids, p <- Server.Projects.in_workspace(ws), do: %{id: p.id, workspace_id: ws, name: p.name}
    prompts = Server.Attention.open_prompts_by_thread()
    thinking = thinking()
    tabs = Map.new(ws_ids, &{&1, Server.Tmux.list_windows(&1)})
    roster = roster(benches, thinking, tabs)

    %{
      roster: roster,
      bench: bench(benches),
      threads: threads(ws_ids, prompts, thinking, roster, tabs),
      projects: projects,
      tickets: tickets(ws_ids),
      notes: notes(projects),
      visits: visits(),
      workspaces: Enum.map(wss, &%{id: &1.id, name: &1.name, shift: &1.shift}),
      shifts: shifts(ws_ids),
      archetypes: archetypes(),
      models: models(),
      counts: Map.new(Repo.all(from(t in Server.Thread, group_by: t.state, select: {t.state, count(t.id)}))),
      awaiting: awaiting(prompts),
      triage: Map.new(ws_ids, &{&1, Room.triage(&1).count}),
      life: Map.new(home_ws_ids(wss), &{&1, &1 |> Server.Life.status() |> Map.take([:level, :xp, :due])}),
      health: Map.take(Room.health(), [:state, :problems]),
      weather: Server.Office.Weather.now(),
      # a TUI started on an older office revision offers a reload (Server.Rollout)
      revs: Server.Rollout.revs(),
      flags: Server.Flags.office(),
      calendar: Room.calendar(ws_ids),
      celebrations: Server.Calendar.celebrations(Date.from_erl!(elem(:calendar.local_time(), 0)))
    }
  end

  @doc """
  A workspace's finished work, for the office's filing cabinet: its done tickets (newest closed
  first) and its closed threads (newest activity first — a thread keeps no close time), 60 of each.
  """
  @spec archive(integer()) :: map()
  def archive(workspace_id) do
    tickets =
      Repo.all(
        from t in Server.Ticket,
          where: t.workspace_id == ^workspace_id and t.status == "done",
          order_by: [desc: t.closed_at, desc: t.id],
          limit: 60
      )

    last = from(m in Server.Message, group_by: m.thread_id, select: %{thread_id: m.thread_id, at: max(m.created_at)})

    threads =
      Repo.all(
        from t in Server.Thread,
          where: t.workspace_id == ^workspace_id and t.state == "closed",
          left_join: l in subquery(last),
          on: l.thread_id == t.id,
          order_by: [desc: coalesce(l.at, t.created_at), desc: t.id],
          limit: 60,
          select: %{id: t.id, title: t.title, stage: t.stage, at: coalesce(l.at, t.created_at)}
      )

    %{
      tickets: Enum.map(tickets, &%{id: &1.id, title: &1.title, closed_at: &1.closed_at}),
      threads: threads
    }
  end

  @doc """
  One thread up close: a page of its messages, oldest first — the newest #{@page}, or with `before`
  the #{@page} before that message id; `more` says older ones remain — and what its worker's pane
  shows now: the thread's own window, or the lead's window for a standing thread; `peek`/`window`
  nil when nothing runs it. `activity`: what its coworkers have done, oldest first
  (`Server.Presence.Thinking.activity/2`) — the card's timeline.
  """
  @spec thread_view(Server.Thread.t(), integer() | nil) :: map()
  def thread_view(%Server.Thread{} = t, before \\ nil) do
    page =
      from(m in Server.Message, where: m.thread_id == ^t.id, order_by: [desc: m.id], limit: @page + 1)
      |> then(&if(before, do: where(&1, [m], m.id < ^before), else: &1))
      |> Repo.all()

    messages =
      page
      |> Enum.take(@page)
      |> Enum.reverse()
      |> Enum.map(&%{id: &1.id, author: &1.author, body: &1.body, at: &1.created_at, kind: &1.kind})

    tab = window_of(t)

    %{
      messages: messages,
      more: length(page) > @page,
      peek: tab && peek(t.workspace_id, tab),
      window: tab && tab.name,
      activity: activity(t.id)
    }
  end

  @doc """
  An aside: one question to a coworker outside any thread, as the command that asks it — its own
  harness, model and persona, read-only, no saved session (`Server.Harness.aside/2`) — and the
  directory to run it in (the workspace's first repo). The CALLER runs it, so a model call never
  blocks the server.
  """
  @spec aside_spec(integer(), integer(), String.t()) ::
          {:ok, %{argv: [String.t()], cwd: String.t() | nil}} | {:error, :not_on_bench}
  def aside_spec(workspace_id, agent_id, question) do
    case Enum.find(Server.Workspaces.bench(workspace_id), &(&1.agent_id == agent_id)) do
      nil ->
        {:error, :not_on_bench}

      c ->
        profile = c |> Server.Profiles.roster_entry() |> Server.Profiles.instantiate(workspace_id)
        repo = List.first(Server.Workspaces.repos(workspace_id))
        {:ok, %{argv: Server.Harness.aside(profile, question), cwd: repo && repo.path}}
    end
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
      {out, 0} -> out |> String.replace_invalid() |> String.trim_trailing()
      _ -> nil
    end
  end

  # who is mid-turn, by thread: the harnesses' own thinking/idle declarations (Presence.Thinking),
  # so a surface can tell working from a session that is merely warm
  defp thinking do
    Server.Presence.Thinking.thinking_all()
  catch
    :exit, _ -> %{}
  end

  defp roster(benches, thinking, tabs) do
    rows = Server.Staff.roster()
    thread_ws = rows |> Enum.map(& &1.thread_id) |> workspaces_of()
    everyone = List.flatten(Map.values(benches))

    Enum.map(rows, fn r ->
      ws = thread_ws[r.thread_id]
      seat = Enum.find(Map.get(benches, ws, []), &(&1.name == r.agent)) || Enum.find(everyone, &(&1.name == r.agent))
      turn = Enum.find(Map.get(thinking, r.thread_id, []), &(&1.agent == r.agent))
      windowed = windowed?(Map.get(tabs, ws, []), r.thread_id, r.agent)

      %{
        agent: r.agent,
        thread_id: r.thread_id,
        title: r.thread_title,
        warm: windowed and Server.Presence.warm_for?(r.last_active_at, r.agent, ws),
        warmth: if(windowed, do: Float.round(Server.Presence.warmth(r.last_active_at, r.agent, ws), 3), else: 0.0),
        workspace_id: ws,
        archetype: seat && seat.archetype,
        lead: !!(seat && seat.lead?),
        thinking: turn != nil,
        doing: turn && turn.doing
      }
    end)
  end

  # the shift board: every seat, both crews, and the shift it is on (`all` for both)
  defp shifts(ws_ids) do
    for ws <- ws_ids,
        c <- Server.Workspaces.bench_all(ws),
        do: %{workspace_id: ws, seat_id: c.id, name: c.name, archetype: c.archetype, crew: c.crew}
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
  defp home_ws_ids(wss), do: wss |> Enum.filter(&(&1.type == "home")) |> Enum.map(& &1.id)

  # a session is only warm with a window to wake in: the thread's leaf, or the coworker's own on the standing thread
  defp windowed?(tabs, thread_id, agent) do
    Enum.any?(tabs, fn tab ->
      leaf? = (tab.thread_id == thread_id or tab.name == "t#{thread_id}") and tab.agent in [nil, agent]
      own? = tab.thread_id == nil and (tab.agent || tab.name) == agent
      leaf? or own?
    end)
  end

  defp threads(ws_ids, prompts, thinking, roster, tabs) do
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

    warm = MapSet.new(for r <- roster, r.warm or r.thinking, do: {r.thread_id, r.agent})

    open =
      Repo.all(
        from(t in Server.Thread,
          where: t.state == "open",
          order_by: [desc: t.id],
          select: %{id: t.id, title: t.title, stage: t.stage, awaiting: t.awaiting, workspace_id: t.workspace_id}
        )
      )

    duties = open |> Enum.map(& &1.id) |> Server.Staffing.duty_threads()

    Enum.map(open, fn t ->
      ws_tabs = Map.get(tabs, t.workspace_id, [])
      std = standing[t.workspace_id] == t.id

      live =
        Server.Tmux.leaf_tab(ws_tabs, t.id) != nil or (std and Server.Tmux.named(ws_tabs, leads[t.id] || "") != nil)

      on_it = thinking |> Map.get(t.id, []) |> Enum.map(& &1.agent)
      lead = leads[t.id]

      desk? = live or lead in on_it or MapSet.member?(warm, {t.id, lead})

      Map.merge(t, %{
        prompt: prompts[t.id],
        lead: lead,
        live: live,
        standing: std,
        thinking: on_it,
        seat: seat(t.id, lead, desk?),
        duty: MapSet.member?(duties, t.id)
      })
    end)
  end

  defp seat(_id, _lead, true), do: "desk"
  defp seat(_id, nil, false), do: "idle"
  defp seat(id, _lead, false), do: if(Server.Staffing.parked_note?(id), do: "parked", else: "idle")

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

  defp activity(thread_id) do
    Server.Presence.Thinking.activity(thread_id)
  catch
    :exit, _ -> []
  end
end
