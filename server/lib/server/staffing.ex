defmodule Server.Staffing do
  @moduledoc """
  Keeping the workspace's tmux in step with who is actually working. Nobody is spawned ahead of
  need: a coworker's window is opened when a message is addressed to them (`Server.Switchboard`
  through `Server.Arbiter.Tmux`), and this pass takes away what is no longer needed —

    * a window whose coworker has gone COLD (no live session warm within the cache window, none
      mid-turn) and is past its boot grace is closed: the lounge is no window at all, and the next
      message spawns a fresh, brief-seeded session;
    * an orphan leaf (its thread closed or unstaffed while nobody looked) is swept;
    * a stale coworker (a live process minting under a handle the bench no longer has) is torn down.

  And it picks up a turn a machine restart cut off: a session still marked mid-turn
  (`Server.Presence.Thinking`'s durable mark) with no window left is ended, and its coworker is
  told on the thread to carry on — that message spawns them as any other would.

  Runs on Oban's cron every minute (`Server.Jobs.Staff`) and on demand (`pass/0`). Stateless:
  the tmux session and the session rows are the state; a spawned window carries its thread,
  coworker and birth time as window options (`Server.Tmux.parse_windows/1`).
  """

  import Ecto.Query

  alias Server.Agent
  alias Server.Channel
  alias Server.Message
  alias Server.OperatorConfig
  alias Server.Presence
  alias Server.Repo
  alias Server.Session
  alias Server.Staff
  alias Server.Thread
  alias Server.Tmux
  alias Server.Workspaces

  # a window this young is still booting — its coworker may not have registered a session yet
  @boot_grace_s 600

  @doc "The pass over every workspace."
  def pass do
    for %{id: id} <- Workspaces.all(), do: pass(id)
    :ok
  end

  @doc "The pass over one workspace: reap stale, sweep orphans and the cold, pick up cut-off turns."
  def pass(workspace_id) do
    case Workspaces.bench(workspace_id) do
      [] ->
        :ok

      bench ->
        standing = with %Thread{id: id} <- Channel.machine_thread(workspace_id), do: id

        tabs =
          workspace_id
          |> reap_stale(bench, Tmux.list_windows(workspace_id))
          |> sweep_orphans(workspace_id, standing)
          |> sweep_cold(workspace_id, standing, bench)

        resume_interrupted(workspace_id, tabs, standing)
        :ok
    end
  end

  # Tear down a coworker whose identity no longer matches the bench; the next message to whoever
  # holds that seat now spawns them.
  defp reap_stale(workspace_id, bench, tabs) do
    stale = stale_coworkers(tabs, Enum.map(bench, & &1.name))
    for tab <- stale, do: Tmux.kill_window(workspace_id, tab.index)
    tabs -- stale
  end

  # A leaf is live while its thread is open and staffed, of any scope: a delegated child (staff_child)
  # is a project-scope thread, and a machine-scope-only test reaped every one within the minute.
  defp sweep_orphans(tabs, workspace_id, standing) do
    live =
      from(t in Thread,
        where: t.workspace_id == ^workspace_id and t.state == "open" and not is_nil(t.agent_id),
        select: t.id
      )
      |> Repo.all()
      |> MapSet.new()

    live = if standing, do: MapSet.put(live, standing), else: live
    {orphans, kept} = Enum.split_with(tabs, &orphan_leaf?(&1, live))
    for tab <- orphans, do: Tmux.kill_window(workspace_id, tab.index)
    kept
  end

  # A coworker's window past its boot grace whose coworker has no warm or mid-turn session on its
  # thread: closed. Only windows this server can attribute to a coworker are touched (a spawn's
  # tags, else the identity its process holds) — a crew role's or a hand-made window never is.
  defp sweep_cold(tabs, workspace_id, standing, bench) do
    seats = MapSet.new(bench, & &1.name)
    now = System.os_time(:second)

    {cold, kept} =
      Enum.split_with(tabs, fn tab ->
        with {thread, agent} when is_integer(thread) and is_binary(agent) <- owner(tab, standing, seats),
             true <- now - (tab.born || 0) > @boot_grace_s do
          not on_the_clock?(thread, agent, workspace_id)
        else
          _ -> false
        end
      end)

    for tab <- cold, do: Tmux.kill_window(workspace_id, tab.index)
    kept
  end

  # whose window a tab is: the spawn's tags; else (a window from before the tags) the identity its
  # process holds, on its tagged thread or the standing one
  defp owner(%{agent: agent, thread_id: thread}, standing, _seats) when is_binary(agent),
    do: {thread || standing, agent}

  defp owner(tab, standing, seats) do
    case pane_author(tab) do
      nil -> nil
      author -> if MapSet.member?(seats, author), do: {tab.thread_id || standing, author}
    end
  end

  defp on_the_clock?(thread_id, agent, workspace_id) do
    cutoff = Presence.loosest_cutoff()

    from(s in Session,
      join: a in Agent,
      on: a.id == s.agent_id,
      where:
        s.thread_id == ^thread_id and a.name == ^agent and is_nil(s.ended_at) and
          (s.last_active_at > ^cutoff or not is_nil(s.thinking_since)),
      select: {s.last_active_at, s.thinking_since}
    )
    |> Repo.all()
    |> Enum.any?(fn {at, thinking} -> thinking != nil or Presence.warm_for?(at, agent, workspace_id) end)
  end

  # A session still mid-turn with no window to run it: the machine went down under it. End it (so
  # the switchboard does not try to wake a pane that is gone) and tell its coworker on the thread
  # to carry on — the message spawns them fresh, brief-seeded, like any other.
  defp resume_interrupted(workspace_id, tabs, standing) do
    for %{session_id: sid, thread_id: tid, agent: agent} <- Staff.interrupted(workspace_id),
        not has_window?(tabs, tid, agent, standing) do
      {:ok, _} = Staff.end_session(Repo.get!(Session, sid))

      {:ok, _} =
        Channel.post(%{
          thread_id: tid,
          author: "tlon",
          body: "@#{agent} the machine restarted while you were mid-turn here — pick it up from the brief."
        })
    end

    :ok
  end

  defp has_window?(tabs, thread_id, agent, standing) do
    Enum.any?(tabs, fn tab ->
      (tab.agent == agent and (tab.thread_id || standing) == thread_id) or
        (is_nil(tab.agent) and thread_id == standing and tab.name == agent) or
        (is_nil(tab.agent) and thread_id != standing and Tmux.leaf_tab([tab], thread_id) != nil)
    end)
  end

  @doc """
  Hand a running thread to another coworker (the office): restaff it, post the handoff as the
  operator — which wakes the new lead, spawning them — and close the old worker's leaf. `{:ok,
  thread}`, or `Channel.assign_lead/2`'s error with nothing changed.
  """
  def hand_off(thread_id, handle) do
    with {:ok, thread} <- Channel.assign_lead(thread_id, handle) do
      with %{index: index} <- thread.workspace_id |> Tmux.list_windows() |> Tmux.leaf_tab(thread.id),
           do: Tmux.kill_window(thread.workspace_id, index)

      operator = Application.get_env(:server, :operator, "andrew")
      body = "Handing this to @#{handle}: pick it up from the brief."
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: operator, body: body})
      {:ok, thread}
    end
  end

  @doc """
  Clear a coworker's context: end their live sessions in `workspace_id` and close their windows.
  The next message addressed to them spawns a fresh, brief-seeded session. `:ok`.
  """
  def clear_context(workspace_id, agent) do
    ids = from(t in Thread, where: t.workspace_id == ^workspace_id, select: t.id)

    from(s in Session,
      join: a in Agent,
      on: a.id == s.agent_id,
      where: a.name == ^agent and is_nil(s.ended_at) and s.thread_id in subquery(ids)
    )
    |> Repo.all()
    |> Enum.each(&Staff.end_session/1)

    seats = MapSet.new([agent])
    standing = with %Thread{id: id} <- Channel.machine_thread(workspace_id), do: id

    for tab <- Tmux.list_windows(workspace_id),
        match?({_, ^agent}, owner(tab, standing, seats)),
        do: Tmux.kill_window(workspace_id, tab.index)

    :ok
  end

  @doc "Is this tab a leaf whose thread is no longer open+staffed? Untagged coworker and crew windows never are."
  def orphan_leaf?(%{thread_id: tid}, live_ids) when is_integer(tid), do: not MapSet.member?(live_ids, tid)

  def orphan_leaf?(%{name: name}, live_ids) do
    case Regex.run(~r/\At(\d+)\z/, name) do
      [_, id] -> not MapSet.member?(live_ids, String.to_integer(id))
      nil -> false
    end
  end

  @doc """
  Tell a thread ONCE why nobody is working it yet (the leaf cap, `Server.OperatorConfig.max_leaves/1`)
  — durable: the note is skipped while it is the thread's latest message, so a minute's cadence never nags.
  """
  def note_parked(thread_id) do
    last = Repo.one(from m in Message, where: m.thread_id == ^thread_id, order_by: [desc: m.id], limit: 1)

    if !(last && last.author == "tlon" && String.starts_with?(last.body, "⏸ parked")) do
      _ =
        Channel.post(%{
          thread_id: thread_id,
          author: "tlon",
          body:
            "⏸ parked — the leaf cap (#{OperatorConfig.max_leaves()}) is reached. This thread keeps its lead " <>
              "and starts automatically when a seat frees (an idle leaf goes cold, or raise \"max_leaves\")."
        })
    end

    :ok
  end

  @doc """
  The coworker windows whose identity has gone stale: their live process still holds a `TLON_AUTHOR`
  that is no longer a handle on this workspace's bench. Conservative: a window is stale only when
  its author is READ successfully and is positively absent — an unreadable `/proc` is left alone.
  """
  @spec stale_coworkers([Tmux.tab()], [String.t()], (Tmux.tab() -> String.t() | nil)) :: [Tmux.tab()]
  def stale_coworkers(tabs, bench_handles, read_author \\ &pane_author/1) do
    handles = MapSet.new(bench_handles)

    Enum.filter(tabs, fn tab ->
      case read_author.(tab) do
        nil -> false
        author -> not MapSet.member?(handles, author)
      end
    end)
  end

  @doc "The `TLON_AUTHOR` a pane's process was started with, read off its environment; nil when unreadable."
  @spec pane_author(map()) :: String.t() | nil
  def pane_author(%{pane_pid: pid}) when is_integer(pid) do
    case File.read("/proc/#{pid}/environ") do
      {:ok, env} ->
        env
        |> String.split(<<0>>, trim: true)
        |> Enum.find_value(fn
          "TLON_AUTHOR=" <> author -> author
          _other -> nil
        end)

      _unreadable ->
        nil
    end
  end

  def pane_author(_tab), do: nil
end
