defmodule Server.Arbiter.Tmux do
  @moduledoc """
  The server's OWN terminal backend (one-brain piece B, slice 1): spawn a coworker and wake it
  with no cockpit open. Before slice 1 the switchboard reached the connected console's arbiter
  over distribution and gave up with no cockpit — so a cold lead could not be rotated unless
  the TUI was up. This backend puts the coworker where the console would have: a window in the
  workspace's private tmux session (`Server.Tmux` naming), tagged `@funes_thread <id>`, so a
  console that opens later adopts it as the thread's leaf instead of spawning a second one, and
  asterion attaches to it. Since B/2 it is the ONE arbiter, in the service and in the console
  alike (the console's embedded centre is an attach to the same window).

  What it does NOT do (this slice): the roster centre, the per-archetype profile drivers, the
  leaf-cap budget and the opening-turn inject — those are the staffing pass (B/3). This spawns
  the thread's LEAD with the harness its agent engine names and wakes by tag.
  """
  @behaviour Server.Arbiter

  alias Server.Agent
  alias Server.Repo
  alias Server.Thread
  alias Server.Tmux

  @impl true
  def wake(%{thread_id: thread_id} = session, prompt) do
    with %Thread{} = thread <- Repo.get(Thread, thread_id) || {:error, :no_thread},
         ws when not is_nil(ws) <- workspace_id(thread),
         %{index: index} <- window_for(ws, thread, session[:agent]) || {:error, :no_window} do
      _ = Tmux.send_text(ws, index, sanitize(prompt))
      # a second burst: a TUI that takes the text swallows an Enter in the same write
      Process.sleep(Application.get_env(:server, :tmux_submit_delay_ms, 300))

      case Tmux.submit(ws, index) do
        {_, 0} -> :ok
        {out, _} -> {:error, {:tmux, out}}
      end
    else
      {:error, _} = e -> e
      nil -> {:error, :no_workspace}
    end
  end

  @impl true
  def spawn(exports) do
    with {:ok, thread_id, author} <- identity(exports),
         %Thread{} = thread <- Repo.get(Thread, thread_id) || {:error, :no_thread},
         ws when not is_nil(ws) <- workspace_id(thread),
         :absent <- leaf_state(ws, thread_id) do
      window = "t#{thread_id}"
      script = Tmux.boot_script(exports, launcher(author))
      cmd = "/bin/sh -c " <> Tmux.sh_single_quote(script)

      args =
        if Tmux.session_up?(ws),
          do: ["new-window", "-d", "-t", Tmux.session(ws), "-n", window, cmd],
          else: ["new-session", "-d", "-s", Tmux.session(ws), "-n", window, cmd]

      case Tmux.run(ws, args) do
        {_out, 0} ->
          Tmux.set_window_option(ws, "=" <> window, "@funes_thread", Integer.to_string(thread_id))
          {:ok, target(ws, window)}

        {out, _} ->
          {:error, {:tmux, String.slice(out, 0, 200)}}
      end
    else
      {:error, _} = e -> e
      nil -> {:error, :no_workspace}
    end
  end

  # `nil || {:error, _}` would read as the error — so an explicit atom for "no leaf yet"
  defp leaf_state(ws, thread_id) do
    if Tmux.leaf_tab(Tmux.list_windows(ws), thread_id), do: {:error, :already_running}, else: :absent
  end

  @doc """
  Where a thread's coworker runs, for any client that wants to attach — `%{socket, session,
  window}` or nil. The leaf window by tag or `t<id>` name, else the lead's own window (a
  standing thread's coworker runs in the centre, named after the lead).
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

  defp lead_name(%Thread{agent_id: nil}), do: nil
  defp lead_name(%Thread{agent_id: id}), do: with(%Agent{name: n} <- Repo.get(Agent, id), do: n)

  @doc "The workspace whose tmux server a thread's coworkers run on (the default one for an unplaced thread)."
  def workspace_id(%Thread{workspace_id: nil}), do: Server.Bootstrap.default_workspace_id()
  def workspace_id(%Thread{workspace_id: ws}), do: ws

  # The exports block names the pane's identity — the same regex the console used.
  defp identity(exports) do
    with [_, id] <- Regex.run(~r/TLON_THREAD="(\d+)"/, exports),
         [_, author] <- Regex.run(~r/TLON_AUTHOR="([^"]+)"/, exports) do
      {:ok, String.to_integer(id), author}
    else
      _ -> {:error, :no_identity_in_exports}
    end
  end

  # Which harness: the agent's engine (or name) carrying "claude" gets Claude Code's launcher, which
  # reads TLON_* from the env and joins the thread; everyone else gets bare `pi`, whose adapters
  # extension registers from the same env. Both overridable — vendor is never design.
  defp launcher(author) do
    engine =
      case Repo.get_by(Agent, name: author) do
        %Agent{engine: e} when is_binary(e) -> String.downcase(e <> " " <> author)
        _ -> String.downcase(author)
      end

    if String.contains?(engine, "claude"),
      do: Application.get_env(:server, :spawn_launcher_claude, Path.join(adapters_dir(), "claude-code/launch.sh")),
      else: Application.get_env(:server, :spawn_launcher_pi, "pi")
  end

  defp adapters_dir do
    Application.get_env(:server, :adapters_dir) || System.get_env("TLON_ADAPTERS_DIR") ||
      Path.join(System.user_home!(), "projects/ficciones/modules/adapters")
  end

  @doc "Collapse a prompt to one clean line (the console's rule: poking an agent is not a production write)."
  def sanitize(prompt),
    do: prompt |> String.replace(~r/[[:cntrl:]]/, " ") |> String.replace(~r/\s+/, " ") |> String.trim()
end
