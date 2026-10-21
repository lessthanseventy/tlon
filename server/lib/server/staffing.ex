defmodule Server.Staffing do
  @moduledoc """
  Keeping the workspace's tmux in step with who is actually working. Nobody is spawned ahead of
  need: a coworker's window is opened when a message is addressed to them (`Server.Switchboard`
  through `Server.Arbiter.Tmux`), and this pass takes away what is no longer needed —

    * a window whose coworker has gone COLD (no live session warm within the cache window, none
      mid-turn) and is past its boot grace is closed: the lounge is no window at all, and the next
      message spawns a fresh, brief-seeded session;
    * a window kept warm so long it never goes cold (the lobby's manager, pinged every few minutes)
      is closed the same way once it is older than `max_session_hours`, at an idle moment — no turn
      running, nothing said in the last minute: one cache miss buys a short context again;
    * an orphan leaf (its thread closed or unstaffed while nobody looked) is swept;
    * a stale coworker (a live process minting under a handle the bench no longer has) is torn down;
    * at the leaf cap with a thread parked, the leaf idle the longest gives its seat up (only a
      work leaf holds a seat — a standing duty's, `seated_leaves/1`, never counts) — never one
      mid-turn, never one nearer to done than what waits (`priority/1`; `seat_for?/2` reserves the
      freed seat for the parked thread nearest to done).

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
  alias Server.Crew
  alias Server.Message
  alias Server.OperatorConfig
  alias Server.Presence
  alias Server.Presence.Thinking
  alias Server.Repo
  alias Server.Schedule
  alias Server.ScheduleRun
  alias Server.Session
  alias Server.Staff
  alias Server.Thread
  alias Server.Tmux
  alias Server.Workspaces

  require Logger

  # a window this young is still booting — its coworker may not have registered a session yet
  @boot_grace_s 600

  @doc "The pass over every workspace."
  def pass do
    for %{id: id} <- Workspaces.all(), do: pass(id)
    :ok
  end

  @doc "The pass over one workspace: reap stale, sweep orphans and the cold, pick up cut-off turns."
  def pass(workspace_id) do
    # housekeeping over everyone hired: a pane whose coworker went off shift finishes its turn and is
    # swept cold like any other, never reaped as a stranger mid-turn
    with [_ | _] = bench <- Workspaces.bench_all(workspace_id),
         tabs when is_list(tabs) <- Tmux.list_windows(workspace_id) do
      pass(workspace_id, bench, tabs)
    else
      [] ->
        :ok

      # every step reads an absent window as gone: a tmux that is down or can't be asked skips the
      # pass, so a restart ends no session and posts no notice until tmux answers again
      {:error, :not_up} ->
        :ok

      {:error, why} ->
        Logger.warning("staffing pass #{workspace_id} skipped: tmux #{why}")
        :ok
    end
  end

  defp pass(workspace_id, bench, tabs) do
    standing = with %Thread{id: id} <- Channel.machine_thread(workspace_id), do: id

    tabs =
      workspace_id
      |> reap_stale(bench, tabs)
      |> sweep_orphans(workspace_id, standing)
      |> sweep_cold(workspace_id, standing, bench)
      |> sweep_long(workspace_id, standing, bench)
      |> yield_seat(workspace_id, standing, bench)
      |> retire_stale_launch(workspace_id, standing)
      |> dismiss_aleph(workspace_id)

    resume_interrupted(workspace_id, tabs, standing)
    end_predating_tmux(workspace_id)
    end_windowless(workspace_id, tabs, standing, bench)
    :ok
  end

  # A session whose window is gone (swept cold, a stop or restart killed it) is over, but only its
  # successor would ever end it, so the room and roster went on counting it. Mid-turn ones are
  # resume_interrupted's; a session idle under the boot grace may still be booting.
  defp end_windowless(workspace_id, tabs, standing, bench) do
    names = MapSet.new(bench, & &1.name)
    idle_since = DateTime.add(DateTime.utc_now(), -@boot_grace_s, :second)

    from(s in Session,
      join: a in Agent,
      on: a.id == s.agent_id,
      join: t in Thread,
      on: t.id == s.thread_id,
      where:
        is_nil(s.ended_at) and is_nil(s.thinking_since) and t.workspace_id == ^workspace_id and
          s.last_active_at < ^idle_since,
      select: {s, a.name}
    )
    |> Repo.all()
    |> Enum.filter(fn {s, name} -> MapSet.member?(names, name) and not windowed?(tabs, s.thread_id, name, standing) end)
    |> Enum.each(fn {s, _} -> Staff.end_session(s) end)
  end

  defp windowed?(tabs, thread_id, name, standing) do
    Enum.any?(tabs, fn tab ->
      leaf? = (tab.thread_id == thread_id or tab.name == "t#{thread_id}") and tab.agent in [nil, name]
      own? = thread_id == standing and tab.thread_id == nil and (tab.agent || tab.name) == name
      leaf? or own?
    end)
  end

  @doc """
  How near a thread is to done, for a seat under the leaf cap: 0 for review and verify (next to
  shipping) and a plain thread (someone asked something), 1 for spec, plan and build, 2 for intent.
  Lower goes first.
  """
  def priority(%Thread{stage: stage}) when stage in [nil, "review", "verify"], do: 0
  def priority(%Thread{stage: "intent"}), do: 2
  def priority(%Thread{}), do: 1

  @doc """
  The leaves that hold a seat under the leaf cap: every leaf window but a standing duty's. A duty
  (`duty_thread?/1`) runs on its own clock, so it neither takes a seat nor waits for one.
  """
  @spec seated_leaves([Tmux.tab()]) :: [Tmux.tab()]
  def seated_leaves(tabs) do
    leaves = Enum.filter(tabs, &Tmux.leaf_window?/1)
    duties = duty_threads(Enum.flat_map(leaves, &List.wrap(leaf_thread(&1))))
    Enum.reject(leaves, &MapSet.member?(duties, leaf_thread(&1)))
  end

  @doc """
  Whether a thread is a standing duty, not work: a schedule's (its standing thread, or an agent
  run's firing), the sheriff's beat, or an outside citizen's own thread (`Server.Outside.study/1`).
  """
  def duty_thread?(thread_id), do: MapSet.member?(duty_threads([thread_id]), thread_id)

  @doc "Which of `ids` are standing duties (`duty_thread?/1`), in one round of queries."
  @spec duty_threads([integer()]) :: MapSet.t(integer())
  def duty_threads([]), do: MapSet.new()

  def duty_threads(ids) do
    standing = from(s in Schedule, where: s.thread_id in ^ids, select: s.thread_id)

    runs =
      from(r in ScheduleRun,
        join: s in assoc(r, :schedule),
        where: r.thread_id in ^ids and s.kind == "agent",
        select: r.thread_id
      )

    beats = from(t in Thread, where: t.id in ^ids and t.title == ^Server.Sheriff.beat_title(), select: t.id)

    studies =
      from(t in Thread,
        join: a in Agent,
        on: a.id == t.agent_id,
        where: t.id in ^ids and a.name in ^Server.Outside.names(),
        select: t.id
      )

    MapSet.new(Repo.all(standing) ++ Repo.all(runs) ++ Repo.all(beats) ++ Repo.all(studies))
  end

  defp leaf_thread(%{thread_id: tid}) when is_integer(tid), do: tid

  defp leaf_thread(%{name: name}) do
    case Regex.run(~r/\At(\d+)\z/, name) do
      [_, id] -> String.to_integer(id)
      nil -> nil
    end
  end

  @doc """
  The threads in `workspace_id` waiting for a seat: open, staffed, with no window in `tabs`, and
  the leaf cap's parked note their latest message.
  """
  def parked(workspace_id, tabs) do
    from(t in Thread, where: t.workspace_id == ^workspace_id and t.state == "open" and not is_nil(t.agent_id))
    |> Repo.all()
    |> Enum.filter(&(is_nil(Tmux.leaf_tab(tabs, &1.id)) and parked_note?(&1.id)))
  end

  @doc """
  Whether a seat that comes free may go to `thread`: no thread nearer to done is parked waiting
  for it. The arbiter asks before it spawns under the cap.
  """
  def seat_for?(%Thread{workspace_id: ws} = thread, tabs \\ nil) do
    tabs = tabs || Tmux.list_windows(ws)
    mine = priority(thread)
    not Enum.any?(parked(ws, tabs), &(&1.id != thread.id and priority(&1) < mine))
  end

  # Tear down a coworker whose identity no longer matches the bench (an outside citizen's window is
  # its own: `Server.Outside`); the next message to whoever holds that seat now spawns them.
  defp reap_stale(workspace_id, bench, tabs) do
    stale = stale_coworkers(tabs, Enum.map(bench, & &1.name) ++ Server.Outside.names())
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
    do: {thread || called_to(agent) || standing, agent}

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
    |> Enum.any?(fn {at, thinking} -> live_turn?(thinking) or Presence.warm_for?(at, agent, workspace_id) end)
  end

  # A session still mid-turn with no window to run it: the machine went down under it. End it (so
  # the switchboard does not try to wake a pane that is gone) and tell its coworker on the thread
  # to carry on — the message spawns them fresh, brief-seeded, like any other. Not told when the
  # thread has moved on to another lead (a stage handover; a leadless thread has not): a session
  # that no longer leads cannot answer there, and the turn it had was landed by the one that does.
  # The standing thread has no single lead and a crew role is never one, so those are always told.
  defp resume_interrupted(workspace_id, tabs, standing) do
    for %{session_id: sid, thread_id: tid, agent: agent} <- Staff.interrupted(workspace_id),
        not has_window?(tabs, tid, agent, standing) do
      # one row gone or one post refused doesn't stop the rest of the pass
      with %Session{} = session <- Repo.get(Session, sid), do: Staff.end_session(session)

      if still_theirs?(tid, agent, standing) do
        _ =
          Channel.post(%{
            thread_id: tid,
            author: "tlon",
            body: "@#{agent} the machine restarted while you were mid-turn here — pick it up from the brief."
          })
      end
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
  Hand a running thread to another coworker: restaff it, post the handoff as `author` (who handed
  it over: the operator from the office, a coworker through `assign_lead`) — which wakes the new
  lead, spawning them — and close the old worker's leaf. `{:ok, thread}`, or
  `Channel.assign_lead/2`'s error with nothing changed.
  """
  def hand_off(thread_id, handle, author \\ Server.OperatorConfig.operator()) do
    with {:ok, thread} <- Channel.assign_lead(thread_id, handle) do
      with %{index: index} <- thread.workspace_id |> Tmux.list_windows() |> Tmux.leaf_tab(thread.id),
           do: Tmux.kill_window(thread.workspace_id, index)

      body = "Handing this to @#{handle}: pick it up from the brief."
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: author, body: body})
      {:ok, thread}
    end
  end

  @doc """
  Roll a thread's lead: end the live sessions on the thread and close its leaf window, so the next
  wake spawns a fresh, brief-seeded session there. The lead's other threads are untouched. `:ok`.
  """
  def roll_leaf(%Thread{} = thread) do
    Staff.end_thread_sessions(thread.id)

    with %{index: index} = tab <- thread.workspace_id |> Tmux.list_windows() |> Tmux.leaf_tab(thread.id) do
      Tmux.kill_window(thread.workspace_id, index)
      if tab.agent, do: record_retired(thread.id, tab.agent, "two turns ended without the stage's artifact")
    end

    :ok
  end

  @doc """
  The opening note for `agent`'s first wake on `thread_id` after its pane there was retired
  (`pane_retired`): when and why it closed, its last post, and that its worktree and branch are as
  it left them. `""` when its pane was not retired, or a session has registered there since: a
  Claude Code session registers on its first prompt, so the opening wake is written before it does.
  """
  def left_off(thread_id, agent) do
    with %Server.Event{} = e <-
           Repo.one(
             from e in Server.Event,
               where: e.thread_id == ^thread_id and e.kind == "pane_retired" and e.correlation == ^"pane:#{agent}",
               order_by: [desc: e.id],
               limit: 1
           ),
         %{} = d <- e.detail,
         0 <-
           Repo.aggregate(
             from(s in Session,
               join: a in Agent,
               on: a.id == s.agent_id,
               where: a.name == ^agent and s.thread_id == ^thread_id and s.id > ^(d["sessions_before"] || 0)
             ),
             :count
           ) do
      ago = div(DateTime.diff(DateTime.utc_now(), e.created_at), 60)

      last =
        if d["last_post_id"], do: " Your last post here was ##{d["last_post_id"]}: \"#{d["last_post"]}\".", else: ""

      "Where you left off: your pane on this thread was closed #{ago} min ago (#{d["why"]}).#{last} " <>
        "Your worktree and branch are as you left them; this is a fresh session, so read the thread from there.\n\n"
    else
      _ -> ""
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

    tabs = with {:error, _} <- Tmux.list_windows(workspace_id), do: []

    for tab <- tabs,
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
              "and starts automatically when a seat frees (the idlest leaf gives its seat up, nearest-to-done " <>
              "work first, or raise \"max_leaves\")."
        })
    end

    :ok
  end

  @doc """
  Say that a thread parked on the leaf cap got its seat: a `notice` (it wakes nobody) from `tlon`,
  payload `seated: agent`, which ends the parked note's run as the latest message — so one per
  seating. The office's in-tray shows it; `Server.Alerts` raises it as info. `:ok`.
  """
  def note_seated(%Thread{} = thread, agent) do
    _ =
      Channel.post(%{
        thread_id: thread.id,
        author: "tlon",
        kind: "notice",
        body: "#{agent} sat down on ##{thread.id} — #{thread.title}",
        payload: %{"seated" => agent}
      })

    :ok
  end

  @doc "The seatings (`note_seated/2`) posted at or after `since`, newest first."
  def seated_since(%DateTime{} = since) do
    Repo.all(
      from m in Message,
        where: m.kind == "notice" and m.created_at >= ^since and fragment("? \\? 'seated'", m.payload),
        order_by: [desc: m.id]
    )
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

  defp live_turn?(nil), do: false
  defp live_turn?(since), do: DateTime.diff(DateTime.utc_now(), since) < Thinking.stale_turn_seconds()

  @doc "Whether the thread's latest message is the leaf cap's parked note: it waits for a seat."
  def parked_note?(thread_id) do
    last = Repo.one(from m in Message, where: m.thread_id == ^thread_id, order_by: [desc: m.id], limit: 1)
    last != nil and last.author == "tlon" and String.starts_with?(last.body, "⏸ parked")
  end

  # At the cap with someone parked: the leaf idle the longest gives its seat up, so finished work
  # isn't held behind a window nobody is using. Never a leaf mid-turn or still booting, never one
  # nearer to done than what waits, and one per pass.
  defp yield_seat(tabs, workspace_id, standing, bench) do
    leaves = seated_leaves(tabs)

    with true <- length(leaves) >= OperatorConfig.max_leaves(),
         [_ | _] = waiting <- parked(workspace_id, tabs),
         %{} = tab <- idlest(leaves, standing, bench, waiting |> Enum.map(&priority/1) |> Enum.min()) do
      Tmux.kill_window(workspace_id, tab.index)
      tabs -- [tab]
    else
      _ -> tabs
    end
  end

  defp idlest(leaves, standing, bench, wanted) do
    seats = MapSet.new(bench, & &1.name)
    now = System.os_time(:second)

    leaves
    |> Enum.flat_map(fn tab ->
      with {thread_id, agent} when is_integer(thread_id) <- owner(tab, standing, seats),
           true <- now - (tab.born || 0) > @boot_grace_s,
           %Thread{} = thread <- Repo.get(Thread, thread_id),
           true <- priority(thread) >= wanted,
           {:idle, since} <- turn(thread_id, agent) do
        [{since, tab}]
      else
        _ -> []
      end
    end)
    |> Enum.min_by(&elem(&1, 0), DateTime, fn -> nil end)
    |> then(&(&1 && elem(&1, 1)))
  end

  # whether the coworker's session on the thread is mid-turn, else when it was last active
  defp turn(thread_id, agent) do
    sessions =
      Repo.all(
        from s in Session,
          join: a in Agent,
          on: a.id == s.agent_id,
          where: s.thread_id == ^thread_id and a.name == ^agent and is_nil(s.ended_at),
          select: {s.last_active_at, s.thinking_since}
      )

    if Enum.any?(sessions, fn {_, thinking} -> live_turn?(thinking) end),
      do: :busy,
      else:
        {:idle,
         sessions
         |> Enum.map(&elem(&1, 0))
         |> Enum.reject(&is_nil/1)
         |> Enum.min(DateTime, fn -> ~U[1970-01-01 00:00:00Z] end)}
  end

  defp sweep_long(tabs, workspace_id, standing, bench) do
    case OperatorConfig.setting("max_session_hours") do
      nil ->
        tabs

      hours ->
        seats = MapSet.new(bench, & &1.name)
        oldest = System.os_time(:second) - hours * 3600

        {long, kept} = Enum.split_with(tabs, &long_and_idle?(&1, oldest, standing, seats))

        for tab <- long do
          {thread, agent} = owner(tab, standing, seats)
          Tmux.kill_window(workspace_id, tab.index)
          Enum.each(idle_sessions(thread, agent) || [], &Staff.end_session/1)
        end

        kept
    end
  end

  defp long_and_idle?(tab, oldest, standing, seats) do
    with {thread, agent} when is_integer(thread) and is_binary(agent) <- owner(tab, standing, seats),
         true <- (tab.born || oldest) < oldest do
      idle_sessions(thread, agent) != nil
    else
      _ -> false
    end
  end

  # the live sessions of `agent` on `thread_id` when every one is idle — no turn running, nothing in
  # the last minute — else nil; none at all is nil too (a window without a session is the cold sweep's)
  defp idle_sessions(thread_id, agent) do
    quiet = DateTime.add(DateTime.utc_now(), -60, :second)

    sessions =
      Repo.all(
        from s in Session,
          join: a in Agent,
          on: a.id == s.agent_id,
          where: s.thread_id == ^thread_id and a.name == ^agent and is_nil(s.ended_at)
      )

    if sessions != [] and
         Enum.all?(
           sessions,
           &(not live_turn?(&1.thinking_since) and DateTime.before?(&1.last_active_at || quiet, quiet))
         ),
       do: sessions
  end

  defp still_theirs?(tid, _agent, standing) when tid == standing, do: true

  defp still_theirs?(tid, agent, _standing) do
    Crew.handle_role(agent) != nil or Channel.thread_lead(tid) in [nil, agent]
  end

  # A pane launched with what its profile no longer gives (a release, a profile edit; no stamp at
  # all is a pane from before stamps) is retired between turns: one per pass, never one whose
  # coworker is mid-turn, its sessions ended. Nothing respawns it until a message needs it.
  defp retire_stale_launch(tabs, workspace_id, standing) do
    if Application.get_env(:server, :retire_stale_launch, true) do
      busy = mid_turn_agents(workspace_id)

      stale =
        Enum.find(tabs, fn tab ->
          tab.agent && not MapSet.member?(busy, tab.agent) &&
            tab.launch != Server.Arbiter.Tmux.launch_stamp(workspace_id, tab.agent)
        end)

      if stale, do: retire_pane(workspace_id, stale, stale.thread_id || standing, tabs), else: tabs
    else
      tabs
    end
  end

  defp retire_pane(workspace_id, tab, thread_id, tabs, why \\ "its launch changed: a release or a profile edit") do
    from(s in Session,
      join: a in Agent,
      on: a.id == s.agent_id,
      where: a.name == ^tab.agent and s.thread_id == ^thread_id and is_nil(s.ended_at)
    )
    |> Repo.all()
    |> Enum.each(&Staff.end_session/1)

    Tmux.kill_window(workspace_id, tab.index)
    record_retired(thread_id, tab.agent, why)
    Logger.info("staffing: retired #{tab.agent}'s pane on ##{thread_id} (#{why})")
    List.delete(tabs, tab)
  end

  # the Aleph's window carries no thread tag (it would read as the thread's leaf): its thread is
  # the one its live session was called to
  defp called_to(agent) do
    if agent == Server.Aleph.name(),
      do:
        Repo.one(
          from s in Session,
            join: a in Agent,
            on: a.id == s.agent_id,
            where: a.name == ^agent and is_nil(s.ended_at),
            order_by: [desc: s.id],
            limit: 1,
            select: s.thread_id
        )
  end

  # The Aleph is called in for one job (`Server.Aleph`): once it has posted on the thread it was
  # called to and its turn is over, its pane is retired, so it never idles warm on the bench's quota.
  defp dismiss_aleph(tabs, workspace_id) do
    name = Server.Aleph.name()

    with %{} = tab <- Enum.find(tabs, &(&1.agent == name)),
         false <- MapSet.member?(mid_turn_agents(workspace_id), name),
         %Session{thread_id: tid, started_at: since} <-
           Repo.one(
             from s in Session,
               join: a in Agent,
               on: a.id == s.agent_id,
               where: a.name == ^name and is_nil(s.ended_at),
               order_by: [desc: s.id],
               limit: 1
           ),
         true <-
           Repo.exists?(from m in Message, where: m.thread_id == ^tid and m.author == ^name and m.created_at >= ^since) do
      retire_pane(workspace_id, tab, tid, tabs, "answered: the Aleph leaves once it has posted")
    else
      _ -> tabs
    end
  end

  defp mid_turn_agents(workspace_id) do
    from(s in Session,
      join: a in Agent,
      on: a.id == s.agent_id,
      join: t in Thread,
      on: t.id == s.thread_id,
      where: is_nil(s.ended_at) and not is_nil(s.thinking_since) and t.workspace_id == ^workspace_id,
      select: {a.name, s.thinking_since}
    )
    |> Repo.all()
    |> Enum.filter(fn {_name, since} -> live_turn?(since) end)
    |> MapSet.new(&elem(&1, 0))
  end

  defp record_retired(thread_id, agent, why) do
    last =
      Repo.one(
        from m in Message,
          where: m.thread_id == ^thread_id and m.author == ^agent,
          order_by: [desc: m.id],
          limit: 1
      )

    Server.Dossier.record_event(%{
      thread_id: thread_id,
      kind: "pane_retired",
      correlation: "pane:#{agent}",
      detail: %{
        "why" => why,
        "last_post_id" => last && last.id,
        "last_post" => last && String.slice(last.body, 0, 200),
        "sessions_before" => Repo.aggregate(Session, :max, :id) || 0
      }
    })
  end

  # tmux numbers panes from %0 on every start, so a session that began before this tmux server did
  # ran in one that is gone: its pane_ref now names whoever reused the id, and a wake routed by it
  # would land in the wrong seat. Runs after resume_interrupted, which owns the mid-turn carry-on
  # notice; what is left here is the idle and reused-pane sessions.
  defp end_predating_tmux(workspace_id) do
    case Tmux.server_started(workspace_id) do
      nil ->
        Logger.warning("staffing: workspace #{workspace_id}'s tmux start time could not be read; sessions not checked")

      started ->
        before = DateTime.from_unix!(started)

        from(s in Session,
          join: t in Thread,
          on: t.id == s.thread_id,
          where:
            is_nil(s.ended_at) and not is_nil(s.pane_ref) and t.workspace_id == ^workspace_id and
              s.started_at < ^before
        )
        |> Repo.all()
        |> Enum.each(&Staff.end_session/1)
    end
  end
end
