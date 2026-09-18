defmodule Console.Staffing do
  @moduledoc """
  The cockpit's side of who-runs-where, after one-brain B/3: the SERVER's staffing pass
  (`Server.Staffing`, on Oban's cron) spawns the workspace's centre, tail and leaf windows; the
  cockpit ATTACHES. What stays here is the display concern — the centre embed (a
  `Console.Terminal` running `tmux new-session -A`, which attaches to the session the server made
  or opens it when the cockpit gets there first), the `s` verb's embedded harness, and the two
  roster reads the delivery router needs (`lead_window_name/1`, `leaf_staffed?/2`).
  """

  alias Console.Reads
  alias Console.Safe
  alias Console.Server.MCP.Spawn
  alias Console.Sessions
  alias Console.Space
  alias Console.Tmux
  alias Server.Harness
  alias Server.Profile
  alias Server.Profiles

  require Space

  # A failed centre attach must not retry on every render (materialise + tmux per frame = a spawn
  # storm whenever the coworker can't start). Back off.
  @machine_spawn_backoff_ms 5_000

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
  Find-or-attach the active Workspace's CENTRE: the embedded terminal on the lead's window. The
  tail and the leaves are the server's (`Server.Staffing`). An empty roster / server-down space is
  a no-op. `spaces` defaults to the live cache but is injectable (mirrors `Space.fetch/2`).
  """
  def ensure_workspace_roster(state, spaces \\ Space.all())

  def ensure_workspace_roster(%{active_key: key} = state, spaces) when Space.workspace?(key) do
    case Space.fetch(key, spaces) do
      %Space{bench: [lead | _]} -> ensure_center(state, key, lead)
      _ -> state
    end
  end

  def ensure_workspace_roster(state, _spaces), do: state

  # The roster LEAD's window, embedded (render's stateful preamble), with a backoff: a failed
  # attach must not retry the whole materialise+tmux pipeline on EVERY render.
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

  # Stash the standing coworker's machine thread id, once, at its first successful attach — the
  # thread the delivery router routes globally (its lead runs in the centre, not a leaf).
  defp capture_standing_thread_id(%{standing_thread_id: nil} = state),
    do: %{state | standing_thread_id: Reads.machine_thread_id(Space.active_workspace_id(state))}

  defp capture_standing_thread_id(state), do: state

  @doc """
  Does the server staff a per-thread leaf window for this lead? Any WORKER roster handle (claude
  or pi harness) qualifies — the predicate `delivery_target` uses, the same one the server's pass
  spawns on, so routing and spawning can never disagree about who owns a thread's turns.
  """
  def leaf_staffed?(lead, workspace_id), do: lead in Profiles.leaf_handles(Space.bench(workspace_id))

  @doc "A harness window's boot script — `Server.Tmux.boot_script/2`, the one builder every harness window rides."
  @spec boot_script(String.t(), String.t()) :: String.t()
  defdelegate boot_script(exports, command), to: Server.Tmux

  @doc false
  # Is a spawn attempt due? nil until an attempt FAILS — the "no backoff pending" sentinel — then
  # a future monotonic timestamp. It MUST be nil, not 0: BEAM monotonic time starts large-NEGATIVE,
  # so `now < 0` reads as "still backing off" forever and the coworker never spawns.
  def spawn_due?(nil = _retry_at, _now), do: true
  def spawn_due?(retry_at, now), do: now >= retry_at

  # Materialise the Workspace's LEAD roster entry into a profile, find-or-create the machine identity,
  # then spawn the center: an embedded tmux client attached to the standing session (pi as window 0
  # if absent) — a console restart re-attaches to the running pi instead of spawning another.
  defp spawn_center(workspace_id, lead) do
    %{archetype: arch, name: name} = Profiles.roster_entry(lead)

    with %Profile{} = profile <- Profiles.instantiate(%{archetype: arch, name: name}, workspace_id),
         {:ok, _dir} <- materialise_profile(profile),
         {:ok, exports} <- machine_exports(workspace_id, name),
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

  @doc """
  The name of the workspace's CENTRE window — the roster lead's, which `profile_launcher/3` passes
  as `-n`. nil for a space with no roster (server down / not a Workspace).
  """
  @spec lead_window_name(term()) :: String.t() | nil
  def lead_window_name(workspace_id) do
    case Space.fetch(workspace_id) do
      %Space{bench: [lead | _]} -> Profiles.roster_entry(lead).name
      _ -> nil
    end
  end

  @doc "The bare `pi` invocation for a profile (`Server.Harness.Pi`) — the center's window-0 command."
  def pi_command(%Profile{} = profile), do: Harness.Pi.launch_command(profile)

  # The center coworker's launcher: pi on its OWN tmux server (`-L console-workspace-<id>`, id-derived —
  # not name-derived, so a workspace rename can't orphan it — + the profile's persistence-free
  # tmux.conf), window 0 named `lead_name` (the roster lead's name — the tab-strip label).
  # `-A` attaches when the server's pass already opened the session. ADAPTERS_RELOAD_CMD lets
  # adapters/reload respawn in place with --continue, keeping the thread across the restart.
  def profile_launcher(workspace_id, lead_name, %Profile{} = profile) do
    pi = pi_command(profile)
    dir = Profiles.config_dir(profile)
    reload_cmd = {"ADAPTERS_RELOAD_CMD", pi <> " --continue"}
    env_flags = Enum.map_join([reload_cmd], " ", fn {k, v} -> "-e #{sh_single_quote(k <> "=" <> v)}" end)

    # `-c`: the session starts in the thread's worktree — the boot script sourced the exports first,
    # so $TLON_CWD expands here; unset (no repo) → wherever the shell is.
    "tmux -L #{Tmux.socket(workspace_id)} -f #{Path.join(dir, "tmux.conf")}" <>
      ~s( new-session -A -s #{Tmux.session(workspace_id)} -n #{lead_name} -c "${TLON_CWD:-$PWD}") <>
      " #{funes_identity_flags()} #{env_flags} '#{pi}'"
  end

  @doc false
  # `-e TLON_X="$TLON_X"` for each identity var, into the tmux SESSION env — durable across a
  # respawn; bash sourced the exports first, so it expands the current literal values here.
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
