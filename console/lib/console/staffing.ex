defmodule Console.Staffing do
  @moduledoc """
  Who runs where: the find-or-spawn steps of the render preamble. A Workspace's cast is its roster
  (`Server.Workspaces`), not constants — head = the CENTER (the roster lead as window 0 of the
  workspace's private tmux session, embedded as a `Console.Terminal`), tail = one tmux window per
  entry, each launched by its archetype's harness driver; a staffed machine thread gets its own
  leaf window (tagged `@funes_thread <id>`) with a two-phase opening turn. Server handle
  `<name>-machine`, tmux window `<name>` (`Console.Profiles.roster_entry/1`).

  Every tmux call rides `Console.Tmux` (`:tlon_cmd`); identity minting rides `:tlon_join` — the
  two seams the suite drives the real dispatch through. Spawns back off on failure rather than
  retrying per frame (a spawn storm whenever a coworker can't start).
  """

  alias Console.Harness
  alias Console.LeafWindow
  alias Console.Profile
  alias Console.Profiles
  alias Console.Reads
  alias Console.Safe
  alias Console.Sessions
  alias Console.Space
  alias Console.Tmux
  alias Server.Channel
  alias Server.MCP.Spawn

  require Space

  # A failed machine-coworker spawn must not retry on every render (materialise + tmux
  # new-session per frame = a spawn storm whenever the coworker can't start). Back off.
  @machine_spawn_backoff_ms 5_000

  # Same backoff, per-thread: a staffed machine thread whose `tmux new-window`/`Spawn.join`
  # keeps failing (server hiccup, a stale agent) must not retry on every render either — see
  # `ensure_thread_sessions`.
  @thread_spawn_backoff_ms 5_000

  # How long to let a freshly-spawned per-thread window settle between typing its opening turn and
  # sending Enter (the two-phase inject). A just-booted Claude Code TUI takes the text but
  # swallows an Enter that arrives in the same burst; a beat later it submits cleanly. Tunable —
  # bump it if the first turn still lands typed-but-unsent.
  @opening_submit_delay_ms 1_200

  # The server identity the Tlön pi needs to wire its MCP client (`${TLON_MCP_URL}` in the profile's
  # mcp.json + the bearer minted for TLON_THREAD/TLON_AUTHOR). Carried into the tmux SESSION env so
  # it survives a respawn — see funes_identity_flags/0.
  @funes_identity_env ~w(TLON_MCP_URL TLON_THREAD TLON_AUTHOR TLON_DB)

  @doc """
  Spawn a harness as an embedded `Console.Terminal` on this thread (one native PTY, sized
  `{cols, rows}`): mint identity IN-PROCESS (console is the serving node) and run the launcher with
  the TLON_* env sourced. Returns the flash text; a raise/exit is a flash, never a crash.
  """
  def spawn_onto(thread_id, {cols, rows}) do
    agent = Application.get_env(:console, :spawn_agent, "pi")

    spawn =
      Safe.call(fn ->
        with {:ok, %{exports: exports}} <- Spawn.join(thread_id, agent),
             do: safe_spawn_harness(thread_id, exports, cols: cols, rows: rows)
      end)

    case spawn do
      {:ok, {:ok, _pid}} -> "session live — type to use it, Ctrl+Space for console"
      {:ok, {:error, reason}} -> "spawn failed: #{inspect(reason)}"
      {:error, reason} -> "spawn crashed: #{Safe.describe(reason)}"
    end
  end

  @doc """
  Find-or-spawn the Workspace's cast from its roster: head = the CENTER (embedded terminal,
  `new-session`), tail = tmux windows (`new-window`), each launcher chosen by its archetype's
  harness. An empty roster / server-down space is a no-op. `spaces` defaults to the live cache but
  is injectable (mirrors `Space.fetch/2`) so a test drives a roster without a live workspace.
  """
  def ensure_workspace_roster(state, spaces \\ Space.all())

  def ensure_workspace_roster(%{active_key: key} = state, spaces) when Space.workspace?(key) do
    case Space.fetch(key, spaces) do
      %Space{roster: [lead | rest]} -> state |> ensure_center(key, lead) |> ensure_windows(key, rest)
      _ -> state
    end
  end

  def ensure_workspace_roster(state, _spaces), do: state

  # The roster LEAD: a pi session working ON the box on a persistent "machine" thread (so its work
  # is triageable) — pi by design, claude stays the deliberate escalation (AGENTS.md routing).
  # Find-or-spawned here (render's stateful preamble), with a backoff: a failed spawn must not retry
  # the whole materialise+tmux pipeline on EVERY render — that would be a spawn storm whenever the
  # coworker can't start.
  defp ensure_center(state, workspace_id, lead) do
    now = System.monotonic_time(:millisecond)

    cond do
      is_pid(Reads.terminal(:machine)) ->
        state

      not spawn_due?(state.machine_retry_at, now) ->
        state

      true ->
        case spawn_center(workspace_id, lead) do
          pid when is_pid(pid) ->
            # Harnesses inside the center can emit kitty graphics themselves — tmux must pass the
            # APC through instead of eating it (design 2026-08-23 §Images rider).
            _ = Tmux.run(workspace_id, ["set-option", "-g", "allow-passthrough", "on"])
            capture_standing_thread_id(state)

          _ ->
            %{state | machine_retry_at: now + @machine_spawn_backoff_ms}
        end
    end
  end

  # Stash the standing coworker's machine thread id, once, at its first successful spawn —
  # the id `ensure_thread_sessions` excludes from its own spawn pass (the standing center
  # coworker is not "a staffed machine thread it should spawn a session for", it already has one).
  defp capture_standing_thread_id(%{standing_thread_id: nil} = state),
    do: %{state | standing_thread_id: Reads.machine_thread_id(Space.active_workspace_id(state))}

  defp capture_standing_thread_id(state), do: state

  # The roster TAIL: one tmux window per entry, each a second window in the SAME session as the
  # center, joined to the SAME root thread, so the cast coordinates over server messages like any
  # two agents. Gated on the center up (its spawn opens/finds the root thread these join) and on
  # the window not already being there (tmux `new-window` isn't idempotent like `new-session -A` —
  # a naive re-run every render would spawn a fresh coworker every tick).
  defp ensure_windows(state, workspace_id, entries) do
    if is_pid(Reads.terminal(:machine)) do
      existing = workspace_id |> Tmux.list_windows() |> MapSet.new(& &1.name)

      entries
      |> Enum.map(&Profiles.roster_entry/1)
      |> Enum.reject(&MapSet.member?(existing, &1.name))
      |> Enum.each(fn %{archetype: arch, name: name} ->
        spawn_window(workspace_id, Profiles.instantiate(%{archetype: arch, name: name}))
      end)
    end

    state
  end

  # A tail window's launcher comes from its profile's HARNESS DRIVER — real Claude or a windowed
  # pi; the spawn plumbing is shared. Materialised first: both drivers read the profile's config
  # dir (pi: the whole dir; claude: system_prompt.md as the role).
  defp spawn_window(workspace_id, %Profile{name: name} = profile) do
    _ = materialise_profile(profile)
    command = Harness.driver(profile.harness).launch_command(profile)
    spawn_harness_window(workspace_id, "#{name}-machine", name, Reads.machine_thread_id(workspace_id), command)
  end

  @doc """
  Every staffed-but-session-less machine thread gets its own leaf window, so a thread opened
  outside the standing coworkers has a live coworker working IT — not just accumulating unread
  messages. Every worker roster lead (claude or pi harness) qualifies, dispatched by its profile;
  a meta (surveyor) or roster-unknown lead gets none. Two-phase: `new-window` this pass, the
  opening turn only on a LATER render once the window shows up live in `Tmux.list_windows/1` —
  send-keys the instant `new-window` returns races the harness's own boot and the first turn lands
  on the floor. Then a convergent sweep of orphan leaves. `spaces` is injectable, as in
  `ensure_workspace_roster/2`.
  """
  def ensure_thread_sessions(state, spaces \\ Space.all())

  def ensure_thread_sessions(%{active_key: key} = state, spaces) when Space.workspace?(key) do
    tabs = Tmux.list_windows(key)
    now = System.monotonic_time(:millisecond)
    roster = Space.roster(key, spaces)
    threads = Server.staffed_machine_threads()
    # Window names spawned THIS pass join the taken set, so two new leaves with the same title in
    # one render can't collide on a name (the tag targets by name once, right after new-window).
    taken = MapSet.new(tabs, & &1.name)
    # The leaf-cap budget (Config.max_leaves): seats left after the already-live leaves. A thread
    # past the cap stays open/staffed and just waits — a later pass staffs it once a seat frees.
    budget = Console.Config.max_leaves() - Enum.count(tabs, &Tmux.leaf_window?/1)

    {state, _taken, _budget} =
      Enum.reduce(threads, {state, taken, budget}, fn thread, {st, tk, bg} ->
        ensure_thread_session(key, roster, thread, tabs, now, st, tk, bg)
      end)

    sweep_orphan_leaves(key, tabs, MapSet.new(threads, & &1.id))
    state
  end

  def ensure_thread_sessions(state, _spaces), do: state

  # Convergent teardown: a leaf window whose thread is no longer open+staffed — closed while
  # console was down, or wholesale-cleared — dies here, not only on the `:thread_closed` Bus event
  # the cockpit may never have seen. Matches ONLY leaf windows (the `@funes_thread` tag, or the
  # legacy `t<id>` name); the center/tail/console windows are never candidates. Runs off the same
  # tabs snapshot as the spawn pass, so a leaf spawned this pass (absent from the snapshot) can't
  # be swept.
  defp sweep_orphan_leaves(workspace_id, tabs, live_ids) do
    for tab <- tabs, orphan_leaf?(tab, live_ids), do: Tmux.kill_window(workspace_id, tab.index)

    :ok
  end

  def orphan_leaf?(%{thread_id: tid}, live_ids) when is_integer(tid), do: not MapSet.member?(live_ids, tid)

  def orphan_leaf?(%{name: name}, live_ids) do
    case Regex.run(~r/\At(\d+)\z/, name) do
      [_, id] -> not MapSet.member?(live_ids, String.to_integer(id))
      nil -> false
    end
  end

  defp ensure_thread_session(workspace_id, roster, %{id: id, lead: lead, title: title}, tabs, now, state, taken, budget) do
    cond do
      # The standing coworker's own thread — it already has a session (the center window),
      # just not a leaf one. Never spawn a duplicate for it.
      id == state.standing_thread_id ->
        {state, taken, budget}

      Tmux.leaf_tab(tabs, id) ->
        {maybe_inject_opening_turn(workspace_id, id, tabs, now, state), taken, budget}

      not spawn_due?(state.thread_spawn_retry[id], now) ->
        {state, taken, budget}

      budget <= 0 ->
        {note_parked(state, id), taken, budget}

      true ->
        spawn_leaf(workspace_id, roster, lead, title, id, now, state, taken, budget)
    end
  end

  # Tell the thread ONCE why nobody is working it yet — a silently parked leaf reads exactly like
  # the old silence bug. Best-effort; the note is informational, the parking is the budget check.
  defp note_parked(state, id) do
    if MapSet.member?(state.parked_noted, id) do
      state
    else
      _ =
        Safe.value(
          fn ->
            Channel.post(%{
              thread_id: id,
              author: "console",
              body:
                "⏸ parked — the leaf cap (#{Console.Config.max_leaves()}) is reached. This thread keeps its lead " <>
                  "and starts automatically when a seat frees (close an idle leaf, or raise \"max_leaves\")."
            })
          end,
          :ok
        )

      %{state | parked_noted: MapSet.put(state.parked_noted, id)}
    end
  end

  # Spawn a leaf via the lead's roster profile: the harness DRIVER supplies the exec (Slice D),
  # the shared plumbing joins the leaf's OWN thread id so `TLON_THREAD` binds the harness to the
  # thread it works. nil profile (meta/unknown lead) spawns nothing. The window gets a HUMAN name
  # (`<archetype>-<title-slug>`, Slice C); the routing key is the `@funes_thread` option
  # `tag_leaf/4` stamps right after the spawn.
  defp spawn_leaf(workspace_id, roster, lead, title, id, now, state, taken, budget) do
    case Profiles.leaf_profile(lead, roster) do
      nil ->
        {state, taken, budget}

      %Profile{} = profile ->
        _ = materialise_profile(profile)
        window = LeafWindow.name(profile.archetype, title, taken)
        command = Harness.driver(profile.harness).launch_command(profile)
        result = spawn_harness_window(workspace_id, lead, window, id, command)
        state = record_thread_spawn(tag_leaf(result, workspace_id, window, id), state, id, now)
        # A parked thread that finally got its seat may park again later; let it re-note then.
        state = %{state | parked_noted: MapSet.delete(state.parked_noted, id)}

        {state, MapSet.put(taken, window), budget - 1}
    end
  end

  # Stamp the routing key on a just-spawned leaf window: `@funes_thread <id>`. From here on the
  # window name is cosmetic — delivery/attach resolve thread → window via this option (`leaf_tab`).
  # Name-targeted exact-match (`=`); safe because the name was minted collision-free against this
  # pass's taken set. Only a successful spawn tags; a failed one just backs off.
  defp tag_leaf({_out, 0} = ok, workspace_id, window, id) do
    Tmux.set_window_option(workspace_id, "=" <> window, "@funes_thread", "#{id}")
    ok
  end

  defp tag_leaf(other, _workspace_id, _window, _id), do: other

  defp record_thread_spawn({_out, 0}, state, id, _now),
    do: %{state | thread_spawn_retry: Map.delete(state.thread_spawn_retry, id)}

  defp record_thread_spawn(_result, state, id, now),
    do: %{state | thread_spawn_retry: Map.put(state.thread_spawn_retry, id, now + @thread_spawn_backoff_ms)}

  # Does the cockpit staff a per-thread leaf window for this lead? Any WORKER roster handle
  # (claude or pi harness) qualifies — the predicate `delivery_target` and the spawn pass share,
  # so routing and spawning can never disagree about who owns a thread's turns.
  def leaf_staffed?(lead, workspace_id), do: lead in Profiles.leaf_handles(Space.roster(workspace_id))

  # Two-phase, so a just-booted leaf window submits its opening turn instead of leaving it typed
  # but unsent: stage 1 types the text; stage 2, once the text has settled for
  # @opening_submit_delay_ms, sends Enter. The PHASE lives in tmux itself (`@funes_opening`
  # "typed"/"done" on the window) so a cockpit restart mid-phase can't re-type the opening into a
  # live session or (done-tagged) re-send it — process state only carries the settle timestamp; a
  # "typed" tag with no timestamp (restart) means the text settled long ago, submit now.
  defp maybe_inject_opening_turn(workspace_id, id, tabs, now, state) do
    tab = Tmux.leaf_tab(tabs, id)

    cond do
      is_nil(tab) ->
        state

      tab.opening == "done" or MapSet.member?(state.opening_injected, id) ->
        mark_opening_done(state, id)

      tab.opening == "typed" or Map.has_key?(state.opening_text_at, id) ->
        submit_opening(workspace_id, id, tab, now, state)

      true ->
        inject_opening_text(workspace_id, id, tab)
        tag_opening(workspace_id, tab.index, "typed")
        %{state | opening_text_at: Map.put(state.opening_text_at, id, now)}
    end
  end

  defp submit_opening(workspace_id, id, tab, now, state) do
    typed_at = state.opening_text_at[id]

    if is_nil(typed_at) or now - typed_at >= @opening_submit_delay_ms do
      Tmux.submit(workspace_id, tab.index)
      tag_opening(workspace_id, tab.index, "done")
      mark_opening_done(state, id)
    else
      state
    end
  end

  defp mark_opening_done(state, id) do
    %{
      state
      | opening_injected: MapSet.put(state.opening_injected, id),
        opening_text_at: Map.delete(state.opening_text_at, id)
    }
  end

  # Stamp the opening phase on the window itself — index-targeted, best-effort.
  defp tag_opening(workspace_id, index, phase), do: Tmux.set_window_option(workspace_id, index, "@funes_opening", phase)

  # Type the thread's latest operator message into its just-appeared leaf window (no Enter yet —
  # stage 2 submits). Best-effort: a thread with no operator message yet is silently skipped —
  # never a render crash.
  defp inject_opening_text(workspace_id, id, %{index: index}) do
    message = Server.latest_operator_message(id)

    if message do
      operator = Console.Config.operator()
      Tmux.send_text(workspace_id, index, "[server thread ##{id}] #{operator}: #{one_line(message.body)}")
    end

    :ok
  end

  defp one_line(body), do: String.replace(body || "", "\n", " ")

  # Open a harness window named `window` on `thread_id` as server handle `handle`, running
  # `command` (the profile's `Console.Harness.Driver.launch_command/1`) in workspace `workspace_id`.
  # `tmux new-window`, not Sessions.spawn_harness: the window rides the ALREADY-embedded workspace
  # session (the center is window 0), not a separate PTY of its own. The roster tail windows AND
  # the per-thread leaf windows all ride this ONE spawn: identity join + tmux plumbing are
  # harness-agnostic, only the exec differs. `TLON_THREAD` binds the harness to the thread it works.
  # Fire-and-forget: a failed spawn leaves the window absent and the next render retries.
  defp spawn_harness_window(workspace_id, handle, window, thread_id, command) do
    with id when is_integer(id) <- thread_id,
         {:ok, %{exports: exports}} <- joiner().(id, handle, mandate: "machine") do
      script = boot_script(exports, command)
      # `-d`: spawn the window in the background — a coworker starting must NOT yank the operator
      # off whatever window they're on.
      Tmux.run(workspace_id, ["new-window", "-d", "-t", Tmux.session(workspace_id), "-n", window, script])
    end
  end

  @doc """
  A harness window's boot script: set TERM (so the harness produces colour), source the server
  `exports` block (so `${TLON_MCP_URL}` etc. reach its env), then `exec` the bare launcher.
  `Console.Crew` rides the same builder — a window on the shared workspace server must exec the
  bare command, never `profile_launcher/3`'s `tmux new-session` wrapper (that would nest a server).
  """
  @spec boot_script(String.t(), String.t()) :: String.t()
  def boot_script(exports, command), do: "export TERM=xterm-256color\n" <> exports <> "\nexec " <> command

  # The identity minter for a tail-window spawn — defaults to the live server join (mints in-node
  # against the Repo/tokens), overridable via `:console, :tlon_join` so a test drives `ensure_windows`
  # against the SAME injected `:tlon_cmd` tmux runner without a live DB (mirrors `Console.Crew`'s
  # `:crew_join`/`:crew_cmd` pair).
  defp joiner, do: Application.get_env(:console, :tlon_join, &Spawn.join/3)

  @doc false
  # Is a spawn attempt due (the center's `machine_retry_at`, a leaf's `thread_spawn_retry` entry)?
  # nil until an attempt FAILS — the "no backoff pending" sentinel — then a future monotonic
  # timestamp. It MUST be nil, not 0: BEAM monotonic time starts large-NEGATIVE, so `now < 0`
  # reads as "still backing off" forever and the coworker never spawns.
  def spawn_due?(nil = _retry_at, _now), do: true
  def spawn_due?(retry_at, now), do: now >= retry_at

  # Materialise the Workspace's LEAD roster entry into a profile, find-or-create the machine identity,
  # then spawn the center: an embedded tmux client attached to the standing session (pi as window 0
  # if absent) — an console restart re-attaches to the running pi instead of spawning another.
  defp spawn_center(workspace_id, lead) do
    %{archetype: arch, name: name} = Profiles.roster_entry(lead)

    with %Profile{} = profile <- Profiles.instantiate(%{archetype: arch, name: name}),
         {:ok, _dir} <- materialise_profile(profile),
         {:ok, exports} <- machine_exports(workspace_id, "#{name}-machine"),
         # kitty: false — tmux wants its Ctrl+B prefix as legacy \x02, not CSI-u (see Terminal.init).
         {:ok, pid} <-
           safe_spawn_harness(:machine, exports, launcher: profile_launcher(workspace_id, name, profile), kitty: false) do
      pid
    else
      _error -> nil
    end
  end

  # Wrap the raising materialiser so a filesystem hiccup degrades to "no coworker", never a cockpit crash.
  defp materialise_profile(profile), do: Safe.call(fn -> Profiles.materialise!(profile) end)

  @doc "The bare `pi` invocation for a profile (`Console.Harness.Pi`) — the center's window-0 command."
  def pi_command(%Profile{} = profile), do: Harness.Pi.launch_command(profile)

  # The center coworker's launcher: pi on its OWN tmux server (`-L console-workspace-<id>`, id-derived —
  # not name-derived, so a workspace rename can't orphan it — + the profile's persistence-free
  # tmux.conf), window 0 named `lead_name` (the roster lead's name — the tab-strip label).
  # ADAPTERS_RELOAD_CMD lets adapters/reload respawn in place with --continue, keeping the thread across
  # the restart.
  def profile_launcher(workspace_id, lead_name, %Profile{} = profile) do
    pi = pi_command(profile)
    dir = Profiles.config_dir(profile.name)
    reload_cmd = {"ADAPTERS_RELOAD_CMD", pi <> " --continue"}
    env_flags = Enum.map_join([reload_cmd], " ", fn {k, v} -> "-e #{sh_single_quote(k <> "=" <> v)}" end)

    "tmux -L #{Tmux.socket(workspace_id)} -f #{Path.join(dir, "tmux.conf")}" <>
      " new-session -A -s #{Tmux.session(workspace_id)} -n #{lead_name} #{funes_identity_flags()} #{env_flags} '#{pi}'"
  end

  @doc false
  # `-e TLON_X="$TLON_X"` for each identity var. The Tlön pi's MCP wiring reads `${TLON_MCP_URL}`
  # (profile mcp.json) and mints a bearer for TLON_THREAD/TLON_AUTHOR — but spawn_harness only
  # `export`s those in pi's ONE-SHOT launch shell, so they live in pi's PROCESS env alone. A
  # continuum/`--continue` restore, a `respawn-pane`, or a reload in a clean shell then boots with
  # `${TLON_MCP_URL}` empty → the server server never registers ("Tool not found", never the 404 the
  # adapter self-heals). Putting them in the tmux SESSION env via `-e` makes the identity durable
  # across respawns; `-e` also refreshes on `new-session -A`, so an console restart re-freshes a stale
  # identity instead of stranding it. bash sourced the exports first, so it expands the values here
  # into the current literal ones.
  def funes_identity_flags do
    Enum.map_join(@funes_identity_env, " ", fn var -> ~s(-e #{var}="$#{var}") end)
  end

  # POSIX single-quote: escape embedded quotes as '\'' so the value survives the shell verbatim.
  defp sh_single_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  # Resolve a machine pane's TLON_* exports by find-or-create: reuse the latest open machine
  # thread (joining it as `agent`) if one exists, else open a fresh `scope: "machine"` thread.
  defp machine_exports(workspace_id, agent) do
    case Reads.machine_thread(workspace_id) do
      %{id: id} ->
        with {:ok, %{exports: e}} <- Spawn.join(id, agent), do: {:ok, e}

      nil ->
        with {:ok, %{exports: e}} <- Spawn.env("general", agent, mandate: "machine", scope: "machine"), do: {:ok, e}
    end
  end

  defp safe_spawn_harness(key, exports, opts),
    do: Safe.value(fn -> Sessions.spawn_harness(key, exports, opts) end, {:error, :sessions_down})
end
