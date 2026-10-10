defmodule Server.Arbiter.Tmux do
  @moduledoc """
  The server's terminal backend, and the ONE arbiter: spawn a coworker when a message needs them
  and wake it, with no UI open. The coworker is a window in the workspace's private tmux session
  (`Server.Tmux` naming) — one per coworker on the standing thread, one leaf per other thread under
  the leaf cap (a standing duty's leaf takes no seat, `Server.Staffing.seated_leaves/1`) — tagged with whose it is and when it was born, which the staffing pass reads to
  close it once it goes cold. The harness is the coworker's profile's (`Server.Harness`).
  """
  @behaviour Server.Arbiter

  alias Server.Agent
  alias Server.Harness
  alias Server.Profile
  alias Server.Profiles
  alias Server.Repo
  alias Server.Thread
  alias Server.Tmux
  alias Server.Workspaces

  require Logger

  # A wake is queued for the coworker's own session to take (`Server.Wake`, drained by the
  # tlon-citizen mod and submitted when the session is idle), never typed: a pane mid-boot swallows
  # an Enter, and a pane mid-draft would take our text as its own. The window is still looked up — a
  # pane that has closed is `:no_window`, which ends its session and spawns a fresh one, and the
  # fresh one takes what its predecessor never did.
  @impl true
  def wake(%{thread_id: thread_id} = session, prompt) do
    with %Thread{} = thread <- Repo.get(Thread, thread_id) || {:error, :no_thread},
         ws when not is_nil(ws) <- workspace_id(thread),
         agent = agent_name(session),
         %{index: _} <- window_for(ws, thread, agent) || {:error, :no_window},
         {:ok, _wake} <- Server.Wake.queue(thread_id, agent, sanitize(prompt)) do
      :ok
    else
      {:error, _} = e -> e
      nil -> {:error, :no_workspace}
    end
  end

  # A coworker's window: on the workspace's standing thread one per coworker, named after them;
  # on any other thread the thread's one leaf, `t<id>`, under the leaf cap — a duty neither takes
  # a seat nor waits for one (a thread past it is told so once, and its message waits for the
  # drain). Tagged with its coworker and its birth (a leaf with its thread too), which is how the
  # staffing pass knows whose it is and when it goes cold.
  @impl true
  def spawn(exports) do
    with {:ok, thread_id, author} <- identity(exports),
         %Thread{} = thread <- Repo.get(Thread, thread_id) || {:error, :no_thread},
         ws when not is_nil(ws) <- workspace_id(thread),
         standing? = standing?(ws, thread),
         tabs = Tmux.list_windows(ws),
         :absent <- running(tabs, thread, author, standing?),
         parked? = Server.Staffing.parked_note?(thread_id),
         :ok <- under_cap(tabs, thread, standing?) do
      leaf_thread = if(!standing?, do: thread_id)
      window = if standing?, do: author, else: "t#{thread_id}"
      script = Tmux.boot_script(exports, launcher(ws, author))
      cmd = "/bin/sh -c " <> Tmux.sh_single_quote(script)

      args =
        if Tmux.session_up?(ws),
          do: ["new-window", "-d", "-t", Tmux.session(ws), "-n", window, cmd],
          else: ["new-session", "-d", "-s", Tmux.session(ws), "-n", window, cmd]

      case Tmux.run(ws, args) do
        {_out, 0} ->
          tag(ws, window, leaf_thread, author)
          _ = parked? and Server.Staffing.note_seated(thread, author)
          {:ok, target(ws, window)}

        {out, _} ->
          {:error, {:tmux, String.slice(out, 0, 200)}}
      end
    else
      {:error, _} = e -> e
      nil -> {:error, :no_workspace}
    end
  end

  defp tag(ws, window, leaf_thread, author) do
    set = &Tmux.set_window_option(ws, "=" <> window, &1, &2)
    if leaf_thread, do: set.("@funes_thread", Integer.to_string(leaf_thread))
    set.("@funes_agent", author)
    set.("@funes_born", Integer.to_string(System.os_time(:second)))
  end

  defp standing?(ws, %Thread{id: id}), do: match?(%Thread{id: ^id}, Server.Channel.machine_thread(ws))

  # `nil || {:error, _}` would read as the error — so an explicit atom for "not running yet"
  defp running(tabs, %Thread{id: id}, author, standing?) do
    mine =
      if standing?,
        do: Enum.find(tabs, &(&1.agent == author or (is_nil(&1.agent) and &1.name == author))),
        else: Tmux.leaf_tab(tabs, id)

    if mine, do: {:error, :already_running}, else: :absent
  end

  defp under_cap(_tabs, _thread, true), do: :ok

  defp under_cap(tabs, %Thread{id: id} = thread, false) do
    cond do
      Server.Staffing.duty_thread?(id) ->
        :ok

      length(Server.Staffing.seated_leaves(tabs)) < Server.OperatorConfig.max_leaves() and
          Server.Staffing.seat_for?(thread, tabs) ->
        :ok

      true ->
        Server.Staffing.note_parked(id)
        {:error, :at_cap}
    end
  end

  @doc """
  Where a thread's coworker runs, for any client that wants to attach — `%{socket, session,
  window}` or nil. The leaf window by tag or `t<id>` name, else the lead's own window (a
  standing thread's coworker runs in a window named after them).
  """
  def terminal_target(%Thread{} = thread) do
    with ws when not is_nil(ws) <- workspace_id(thread),
         %{name: name} <- window_for(ws, thread, lead_name(thread)) do
      target(ws, name)
    else
      _ -> nil
    end
  end

  defp target(ws, window), do: %{socket: Tmux.socket(ws), session: Tmux.session(ws), window: window}

  defp window_for(ws, %Thread{id: id}, agent) do
    tabs = Tmux.list_windows(ws)
    Tmux.leaf_tab(tabs, id) || (agent && Tmux.named(tabs, agent))
  end

  # The recipient's handle: a plain map carries `agent`; a `%Server.Session{}` (the drain's rows)
  # carries `agent_id` — `session[:agent]` on the struct raised and discarded every drain (2026-09-18).
  defp agent_name(%{agent: name}) when is_binary(name), do: name
  defp agent_name(%{agent_id: id}) when is_integer(id), do: with(%Agent{name: n} <- Repo.get(Agent, id), do: n)
  defp agent_name(_session), do: nil

  defp lead_name(%Thread{agent_id: nil}), do: nil
  defp lead_name(%Thread{agent_id: id}), do: with(%Agent{name: n} <- Repo.get(Agent, id), do: n)

  @doc "The workspace whose tmux server a thread's coworkers run on (the default one for an unplaced thread)."
  def workspace_id(%Thread{workspace_id: nil}), do: Server.Bootstrap.default_workspace_id()
  def workspace_id(%Thread{workspace_id: ws}), do: ws

  # The exports block names the pane's identity.
  defp identity(exports) do
    with [_, id] <- Regex.run(~r/TLON_THREAD="(\d+)"/, exports),
         [_, author] <- Regex.run(~r/TLON_AUTHOR="([^"]+)"/, exports) do
      {:ok, String.to_integer(id), author}
    else
      _ -> {:error, :no_identity_in_exports}
    end
  end

  defp adapters_dir do
    Application.get_env(:server, :adapters_dir) || System.get_env("TLON_ADAPTERS_DIR") ||
      Path.join(Profiles.tlon_root(), "adapters")
  end

  @doc """
  Collapse a prompt to one clean line (poking an agent is not a production write).

      iex> Server.Arbiter.Tmux.sanitize("  run the\\n\\tgate  ")
      "run the gate"
  """
  def sanitize(prompt),
    do: prompt |> String.replace(~r/[[:cntrl:]]/, " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # Which harness: the coworker's PROFILE decides (Claude Code first, 2026-09-25) — the same
  # `Harness.driver(profile.harness).launch_command/1` the staffing pass spawns its leaves with, so a
  # spawn-on-post and a staffing spawn can never disagree about a seat. Only an author with no seat
  # on the workspace's bench falls back to `launcher_by_engine/1`.
  defp launcher(ws, author) do
    # everyone hired, not only the crew on shift: an off-shift seat's duty (the sheriff's beat, a
    # nightly schedule) still runs as that seat, never as the engine fallback
    bench = Workspaces.bench_all(ws)

    case Profiles.seat_profile(author, bench, ws) do
      %Profile{} = profile ->
        _ = Profiles.materialise!(profile)
        Harness.driver(profile.harness).launch_command(profile)

      nil ->
        launcher_by_engine(author)
    end
  rescue
    e ->
      Logger.warning(
        "arbiter: profile launcher for #{author} failed (#{Exception.message(e)}); falling back to the engine"
      )

      launcher_by_engine(author)
  end

  # A hand-registered agent with no seat on the bench runs Claude Code's launcher on its own default
  # model. Overridable — vendor is never design.
  defp launcher_by_engine(_author),
    do: Application.get_env(:server, :spawn_launcher_claude, Path.join(adapters_dir(), "claude-code/launch.sh"))

  @doc """
  The pane shows its harness's input line `❯`: the coworker is up, so the opening turn queued for it
  is taken by a session that is there to take it.
  """
  @impl true
  def ready?(%{session: "w" <> id, window: window}) do
    ws = String.to_integer(id)

    case Tmux.run(ws, ["capture-pane", "-p", "-t", Tmux.target(ws, window)]) do
      {out, 0} when is_binary(out) -> String.contains?(out, "❯")
      _ -> false
    end
  end

  def ready?(_handle), do: true
end
