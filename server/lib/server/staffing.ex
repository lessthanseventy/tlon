defmodule Server.Staffing do
  @moduledoc """
  Who runs where — the staffing pass, on the server (one-brain piece B, slice 3; lifted from the
  console's render preamble, which ran it per frame). A workspace's cast is its bench
  (`Server.Workspaces.bench/1`), not constants: the lead is the CENTRE (window 0 of the workspace's
  private tmux session, running pi from its profile), every other seat a tail window launched by
  its archetype's harness driver, and every staffed machine thread a leaf window (tagged
  `@funes_thread <id>`) that gets the thread's latest operator message as its opening turn — under
  the leaf cap (`Server.OperatorConfig.max_leaves/1`), a thread past it parks with a note.
  Orphan leaves (thread closed while nobody looked) are swept. Stale coworkers (a live process
  minting under a handle the bench no longer has) are torn down so they respawn.

  Runs on Oban's cron every minute (`Server.Jobs.Staff`) and on demand (`pass/0`); the console
  attaches to what this made. Stateless: the tmux session IS the state (window tags carry the
  opening phase), and a minute's cadence replaces the per-frame backoffs.

  Seams: tmux rides `Server.Tmux.run/3` (`:server, :tmux_cmd`); identity minting is
  `:server, :staff_join` (default `Server.MCP.Spawn.join/3`); the opening inject's poll/settle
  budgets are app env so tests pay no wait.
  """

  import Ecto.Query

  alias Server.Channel
  alias Server.Coworker
  alias Server.Harness
  alias Server.LeafWindow
  alias Server.MCP.Spawn
  alias Server.Message
  alias Server.OperatorConfig
  alias Server.Profile
  alias Server.Profiles
  alias Server.Repo
  alias Server.Thread
  alias Server.Tmux
  alias Server.Workspaces

  require Logger

  # The opening inject waits for the harness to be input-ready (the registered footer), then types
  # the text, settles, and sends Enter as its own burst — a just-booted TUI takes the text but
  # swallows an Enter in the same write. A poll timeout still injects.
  @ready_marker "registered"
  @ready_poll_ms 500
  @ready_timeout_ms 20_000
  @opening_settle_ms 1_200

  defp joiner, do: Application.get_env(:server, :staff_join, &Spawn.join/3)
  defp ready_poll_ms, do: Application.get_env(:server, :staff_poll_ms, @ready_poll_ms)
  defp ready_timeout_ms, do: Application.get_env(:server, :staff_ready_timeout_ms, @ready_timeout_ms)
  defp opening_settle_ms, do: Application.get_env(:server, :staff_settle_ms, @opening_settle_ms)

  @doc "The pass over every workspace."
  def pass do
    for %{id: id} <- Workspaces.all(), do: pass(id)
    :ok
  end

  @doc "The pass over one workspace: reap stale, centre, tail, leaves (spawn under the cap, sweep orphans)."
  def pass(workspace_id) do
    case Workspaces.bench(workspace_id) do
      [] ->
        :ok

      bench ->
        lead = Coworker.lead(bench)
        tabs = reap_stale(workspace_id, bench, Tmux.list_windows(workspace_id))
        tabs = ensure_centre(workspace_id, lead, tabs)
        ensure_tail(workspace_id, lead, bench, tabs)
        ensure_leaves(workspace_id, bench, tabs)
        :ok
    end
  end

  # Tear down a coworker whose identity no longer matches the bench, so the passes below rebuild
  # it. A stale CENTRE drops the whole workspace server (the session's window 0 cannot be replaced
  # in place); a stale tail window is just killed.
  defp reap_stale(workspace_id, bench, tabs) do
    handles = Enum.map(bench, & &1.name)
    centre = Coworker.lead(bench).name
    stale = stale_coworkers(tabs, handles)

    cond do
      stale == [] ->
        tabs

      Enum.any?(stale, &(&1.name == centre)) ->
        _ = Tmux.run(workspace_id, ["kill-server"])
        []

      true ->
        for tab <- stale, do: Tmux.kill_window(workspace_id, tab.index)
        tabs -- stale
    end
  end

  # The CENTRE: the lead's pi on the workspace's standing machine thread (window 0, named after
  # the lead) — the session the console's embed attaches to with `new-session -A`. Pi by design,
  # whatever the lead's archetype binds elsewhere: the centre is the workspace's conversational
  # seat, and claude stays the deliberate escalation.
  defp ensure_centre(workspace_id, %Coworker{name: name} = lead, tabs) do
    if Tmux.named(tabs, name) do
      tabs
    else
      with %Profile{} = profile <- instantiate(lead, workspace_id),
           {:ok, exports} <- machine_exports(workspace_id, name),
           script = Tmux.boot_script(exports, Harness.Pi.launch_command(profile)),
           {_out, 0} <- open(workspace_id, name, script, profile, exports) do
        # Harnesses in the centre can emit kitty graphics themselves — tmux must pass the APC through.
        _ = Tmux.run(workspace_id, ["set-option", "-g", "allow-passthrough", "on"])
        Tmux.list_windows(workspace_id)
      else
        other ->
          Logger.warning("staffing: centre #{name} on workspace #{workspace_id} did not start: #{inspect(other)}")
          tabs
      end
    end
  end

  # The centre's window opens the session when there is none — with the profile's persistence-free
  # tmux.conf and the identity in the session env — else it is a window in the running session.
  defp open(workspace_id, name, script, profile, exports) do
    cmd = "/bin/sh -c " <> Tmux.sh_single_quote(script)
    env = Tmux.identity_flags(exports)

    if Tmux.session_up?(workspace_id) do
      Tmux.run(workspace_id, ["new-window", "-d", "-t", Tmux.session(workspace_id), "-n", name] ++ env ++ [cmd])
    else
      conf = Path.join(Profiles.config_dir(profile), "tmux.conf")

      Tmux.run(
        workspace_id,
        ["-f", conf, "new-session", "-d", "-s", Tmux.session(workspace_id), "-n", name] ++ env ++ [cmd]
      )
    end
  end

  # The TAIL: one window per remaining seat, each joined to the workspace's standing machine
  # thread so the cast coordinates over server messages. Gated on the centre being up (its spawn
  # opens the thread these join) and on the window not already being there.
  defp ensure_tail(workspace_id, %Coworker{name: centre}, bench, tabs) do
    if Tmux.named(tabs, centre) do
      thread_id = machine_thread_id(workspace_id)

      for %Coworker{name: name} = seat <- bench,
          name != centre,
          is_nil(Tmux.named(tabs, name)),
          %Profile{} = profile <- [instantiate(seat, workspace_id)] do
        command = Harness.driver(profile.harness).launch_command(profile)
        spawn_window(workspace_id, name, name, thread_id, command)
      end
    end

    :ok
  end

  # The LEAVES: every staffed, open machine thread in this workspace (the standing one excepted —
  # the centre already runs it) gets its own window, up to the cap; orphans are swept first off the
  # same snapshot, so a leaf spawned this pass can't be swept.
  defp ensure_leaves(workspace_id, bench, tabs) do
    standing = machine_thread_id(workspace_id)
    threads = workspace_id |> Channel.staffed_machine_threads() |> Enum.reject(&(&1.id == standing))
    live_ids = MapSet.new(threads, & &1.id)

    for tab <- tabs, orphan_leaf?(tab, live_ids), do: Tmux.kill_window(workspace_id, tab.index)

    budget = OperatorConfig.max_leaves() - Enum.count(tabs, &Tmux.leaf_window?/1)
    taken = MapSet.new(tabs, & &1.name)

    _ =
      Enum.reduce(threads, {budget, taken}, fn thread, {budget, taken} ->
        case Tmux.leaf_tab(tabs, thread.id) do
          # a leaf the console typed into before a restart: the text settled long ago, submit now
          %{opening: "typed", index: index} ->
            _ = Tmux.submit(workspace_id, index)
            _ = Tmux.set_window_option(workspace_id, index, "@funes_opening", "done")
            {budget, taken}

          %{} ->
            {budget, taken}

          nil when budget <= 0 ->
            note_parked(thread.id)
            {budget, taken}

          nil ->
            spawn_leaf(workspace_id, bench, thread, taken, budget)
        end
      end)

    :ok
  end

  @doc "Is this tab a leaf whose thread is no longer open+staffed? The centre/tail/crew windows never are."
  def orphan_leaf?(%{thread_id: tid}, live_ids) when is_integer(tid), do: not MapSet.member?(live_ids, tid)

  def orphan_leaf?(%{name: name}, live_ids) do
    case Regex.run(~r/\At(\d+)\z/, name) do
      [_, id] -> not MapSet.member?(live_ids, String.to_integer(id))
      nil -> false
    end
  end

  # A leaf via the lead's bench profile: the harness DRIVER supplies the exec, the window gets a
  # HUMAN name (`<archetype>-<title-slug>`), the routing key is the `@funes_thread` tag stamped right
  # after the spawn, and the opening turn follows once the harness is ready. A meta or
  # bench-unknown lead spawns nothing.
  defp spawn_leaf(workspace_id, bench, %{id: id, lead: lead, title: title}, taken, budget) do
    case Profiles.leaf_profile(lead, bench) do
      nil ->
        {budget, taken}

      %Profile{} = profile ->
        with :ok <- materialise(profile),
             window = LeafWindow.name(profile.archetype, title, taken),
             command = Harness.driver(profile.harness).launch_command(profile),
             {_out, 0} <- spawn_window(workspace_id, lead, window, id, command) do
          _ = Tmux.set_window_option(workspace_id, "=" <> window, "@funes_thread", Integer.to_string(id))
          inject_opening(workspace_id, window, id)
          {budget - 1, MapSet.put(taken, window)}
        else
          other ->
            Logger.warning("staffing: leaf for thread #{id} did not start: #{inspect(other)}")
            {budget, taken}
        end
    end
  end

  # The opening turn: the thread's latest operator message, typed once the pane is ready, then
  # Enter as its own burst; the window is tagged done either way, so nothing ever re-types it.
  defp inject_opening(workspace_id, window, thread_id) do
    if message = Channel.latest_operator_message(thread_id) do
      operator = Application.get_env(:server, :operator, "andrew")
      _ = await_ready(workspace_id, window)

      _ =
        Tmux.send_text(
          workspace_id,
          "=" <> window,
          "[server thread ##{thread_id}] #{operator}: #{one_line(message.body)}"
        )

      Process.sleep(opening_settle_ms())
      _ = Tmux.submit(workspace_id, "=" <> window)
    end

    _ = Tmux.set_window_option(workspace_id, "=" <> window, "@funes_opening", "done")
    :ok
  end

  defp one_line(body), do: String.replace(body || "", "\n", " ")

  defp await_ready(ws, window), do: poll_ready(ws, window, div(ready_timeout_ms(), max(ready_poll_ms(), 1)))

  defp poll_ready(_ws, _window, remaining) when remaining <= 0, do: false

  defp poll_ready(ws, window, remaining) do
    case Tmux.run(ws, ["capture-pane", "-p", "-t", Tmux.target(ws, "=" <> window)]) do
      {out, 0} when is_binary(out) ->
        if String.contains?(out, @ready_marker) do
          true
        else
          Process.sleep(ready_poll_ms())
          poll_ready(ws, window, remaining - 1)
        end

      _ ->
        false
    end
  end

  # Tell the thread ONCE why nobody is working it yet — durable: the note is skipped while it is
  # the thread's latest message, so a minute's cadence never nags.
  defp note_parked(thread_id) do
    last = Repo.one(from m in Message, where: m.thread_id == ^thread_id, order_by: [desc: m.id], limit: 1)

    if !(last && last.author == "tlon" && String.starts_with?(last.body, "⏸ parked")) do
      _ =
        Channel.post(%{
          thread_id: thread_id,
          author: "tlon",
          body:
            "⏸ parked — the leaf cap (#{OperatorConfig.max_leaves()}) is reached. This thread keeps its lead " <>
              "and starts automatically when a seat frees (close an idle leaf, or raise \"max_leaves\")."
        })
    end

    :ok
  end

  # Open a harness window named `window` on `thread_id` as server handle `handle`, running
  # `command` in workspace `workspace_id` — the tail and the leaves ride this ONE spawn: identity
  # join + tmux plumbing are harness-agnostic, only the exec differs. `-d`: a coworker starting
  # must NOT yank the operator off whatever window they're on.
  defp spawn_window(workspace_id, handle, window, thread_id, command) do
    with id when is_integer(id) <- thread_id,
         {:ok, %{exports: exports}} <- joiner().(id, handle, mandate: "machine") do
      script = Tmux.boot_script(exports, command)

      Tmux.run(workspace_id, [
        "new-window",
        "-d",
        "-t",
        Tmux.session(workspace_id),
        "-n",
        window,
        "/bin/sh -c " <> Tmux.sh_single_quote(script)
      ])
    end
  end

  defp instantiate(%Coworker{} = seat, workspace_id) do
    profile = Profiles.instantiate(Profiles.roster_entry(seat), workspace_id)
    with :ok <- materialise(profile), do: profile
  end

  # A filesystem hiccup degrades to "no coworker", never a crashed pass.
  defp materialise(profile) do
    _ = Profiles.materialise!(profile)
    :ok
  rescue
    e -> {:error, {:materialise, Exception.message(e)}}
  end

  # The workspace's standing machine thread — the centre's and the tail's root — find-or-created:
  # the oldest open machine thread in the workspace, else a fresh "general" one.
  defp standing_thread(workspace_id) do
    case Channel.machine_thread(workspace_id) do
      %Thread{} = t -> {:ok, t}
      nil -> Channel.open_thread(%{title: "general", scope: "machine", workspace_id: workspace_id})
    end
  end

  defp machine_thread_id(workspace_id) do
    case standing_thread(workspace_id) do
      {:ok, %Thread{id: id}} -> id
      _ -> nil
    end
  end

  defp machine_exports(workspace_id, agent) do
    with {:ok, %Thread{id: id}} <- standing_thread(workspace_id),
         {:ok, %{exports: e}} <- joiner().(id, agent, mandate: "machine"),
         do: {:ok, e}
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
