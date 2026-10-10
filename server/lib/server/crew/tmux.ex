defmodule Server.Crew.Tmux do
  @moduledoc """
  The crew backend on the workspace's tmux server. `spawn_role/3` mints the role's identity on the
  thread, materialises its profile (`Server.Profiles`), opens the `r<tid>` window in the thread's
  workspace session running the profile's harness driver, and — once the pane shows the
  registered footer — types the leader's opening turn and submits it as a second burst.
  `kill_role/2` drops the window.

  Seams: tmux rides `Server.Tmux.run/3` (`:server, :tmux_cmd`); identity minting is
  `:server, :crew_join` (default `Server.MCP.Spawn.join/3`); the settle/poll budgets are app env
  so tests pay no real wait.
  """
  @behaviour Server.Crew

  alias Server.Arbiter
  alias Server.Crew
  alias Server.Harness
  alias Server.MCP.Spawn
  alias Server.Profile
  alias Server.Profiles
  alias Server.Repo
  alias Server.Thread
  alias Server.Tmux

  defp joiner, do: Application.get_env(:server, :crew_join, &Spawn.join/3)

  @impl Crew
  def spawn_role(role_key, thread_id, task), do: spawn(role_key, thread_id, task, [])

  @impl Crew
  def kill_role(role_key, thread_id), do: kill(role_key, thread_id)

  @doc """
  Spawn `role_key` onto task `thread_id` as a server citizen, the leader's `task` queued as its
  opening turn (`Server.Wake`: its session takes it once it is up, nothing typed into a booting
  pane). `{:ok, window}` or a typed error. `opts[:inject]` (default true) false queues nothing.
  """
  @spec spawn(String.t(), integer() | String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def spawn(role_key, thread_id, task, opts \\ []) do
    thread_id = to_int(thread_id)

    with %{handle: handle, profile: profile_name} <- Crew.role(role_key) || {:error, {:unknown_role, role_key}},
         %Thread{} = thread <- Repo.get(Thread, thread_id) || {:error, :no_thread},
         ws when is_integer(ws) <- Arbiter.Tmux.workspace_id(thread) || {:error, :no_workspace},
         %Profile{} = profile <- Profiles.fetch(profile_name, ws) || {:error, {:missing_profile, profile_name}},
         :ok <- materialise(profile),
         {:ok, %{exports: exports}} <- joiner().(thread_id, handle, mandate: "machine", assign: false),
         window = Crew.crew_window(role_key, thread_id),
         script = Tmux.boot_script(exports, Harness.driver(profile.harness).launch_command(profile)),
         :ok <- open_window(ws, window, script) do
      if Keyword.get(opts, :inject, true), do: Server.Wake.queue(thread_id, handle, opening_turn(thread_id, task))
      {:ok, window}
    else
      {:error, _} = err -> err
      other -> {:error, other}
    end
  end

  @doc "Tear down a role's window on a thread. Best-effort; a missing window or thread is not an error."
  @spec kill(String.t(), integer() | String.t()) :: :ok
  def kill(role_key, thread_id) do
    thread_id = to_int(thread_id)

    with %Thread{} = thread <- Repo.get(Thread, thread_id),
         ws when is_integer(ws) <- Arbiter.Tmux.workspace_id(thread) do
      _ = Tmux.kill_window(ws, Crew.crew_window(role_key, thread_id))
    end

    :ok
  end

  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)

  # A filesystem hiccup degrades to "no coworker", never a crash in the tool that asked.
  defp materialise(profile) do
    _ = Profiles.materialise!(profile)
    :ok
  rescue
    e -> {:error, {:materialise, Exception.message(e)}}
  end

  # The window rides the workspace's tmux session; with no session yet (nobody spawned), the role
  # opens it — the same rule as Arbiter.Tmux.spawn.
  defp open_window(ws, window, script) do
    cmd = "/bin/sh -c " <> Tmux.sh_single_quote(script)

    args =
      if Tmux.session_up?(ws),
        do: ["new-window", "-d", "-t", Tmux.session(ws), "-n", window, cmd],
        else: ["new-session", "-d", "-s", Tmux.session(ws), "-n", window, cmd]

    case Tmux.run(ws, args) do
      {_out, 0} -> :ok
      {out, _status} -> {:error, {:tmux_failed, out}}
    end
  end

  # The opening assignment the leader hands the reviewer. Names the leader handle so the reviewer's
  # @<leader> ESCALATE resolves — MVP leader is claude (the task thread's staffed lead).
  defp opening_turn(thread_id, task) do
    "You are reviewing on server thread ##{thread_id}. Leader handle: claude. " <>
      "Task: #{task}. Read the diff (git diff/show), post findings, and escalate any fix per your protocol."
  end
end
