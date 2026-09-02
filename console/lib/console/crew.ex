defmodule Console.Crew do
  @moduledoc """
  The server crew — roles the leader spawns onto a task thread and tears down when done.

  This is the console-side crew backend: the server's `spawn_crew`/`kill_crew` tools dispatch through the
  `Server.Crew` behaviour (`config :server, :crew, Console.Crew`) into `spawn_role/3` / `kill_role/2`,
  which run IN the live cockpit node — the same node holding the server's Repo, tokens, and the `tlon`
  tmux server. No second BEAM boots and no port is re-bound; the leader staffs a reviewer from the
  thread it is leading and the window lands beside it.

  A **role** is a seat, not an identity: a `%{handle, window_prefix, profile}` naming the server
  author the seat posts as, the tmux window it runs in, and the `Console.Profile` that materialises
  its pi config. MVP staffs one role, `reviewer`.

  The per-thread window name (`crew_window/2`) is a PURE function of (role, thread id), so this
  spawner and the mention router agree on `r<tid>` deterministically — that is what lets a spawned
  window be the target the cockpit routes `@reviewer-machine` to.

  Pure tmux command builders (`spawn_argv/3`, `kill_argv/2`, `boot_script/2`) live below; the IO
  wrappers (`spawn/4`, `kill/2`) mint identity, materialise the profile, shell out to tmux, and
  inject the leader's opening turn. The command runner and identity minter are injected via app env
  (`:console, :crew_cmd` / `:crew_join`) so the seam tests headless, same pattern as the cockpit's
  `:spawn_launcher`.
  """

  # The crew backend server dispatches to (`config :server, :crew, Console.Crew`) — the same seam as
  # Console.Arbiter. the server's `spawn_crew`/`kill_crew` tools call through `Server.Crew` and land in
  # `spawn_role/3` / `kill_role/2` below, run IN this live node, so no second BEAM boots.
  @behaviour Server.Crew

  alias Console.Profiles
  alias Console.Space
  alias Console.Tmux

  @roles %{
    "reviewer" => %{handle: "reviewer-machine", window_prefix: "r", profile: "reviewer"}
  }

  @doc "The MVP crew: role key → %{handle, window_prefix, profile}."
  @spec roles() :: %{String.t() => map()}
  def roles, do: @roles

  @doc "A role by key, or nil."
  @spec role(String.t()) :: map() | nil
  def role(key), do: Map.get(@roles, key)

  @doc "The server handle → role key (reverse of `role/1`'s handle), or nil for a non-crew handle."
  @spec handle_role(String.t()) :: String.t() | nil
  def handle_role(handle) do
    Enum.find_value(@roles, fn {key, %{handle: h}} -> if h == handle, do: key end)
  end

  @doc """
  The tmux window a role runs in on a given thread: `<prefix><thread_id>` (e.g. `"r42"`). Pure and
  deterministic — the spawner and the router both compute it. Raises on an unknown role.
  """
  @spec crew_window(String.t(), integer() | String.t()) :: String.t()
  def crew_window(role_key, thread_id) do
    case role(role_key) do
      %{window_prefix: p} -> p <> to_string(thread_id)
      nil -> raise ArgumentError, "unknown crew role: #{inspect(role_key)}"
    end
  end

  # The crew rides the FIRST workspace's tmux server (`Console.Tmux` naming). `first_workspace/0`
  # is nil with no workspace at all — spawn/kill guard before reaching this, so a raise here is a
  # bug sentinel, not a reachable path.
  defp workspace_id, do: Space.first_workspace().id

  @doc "The `tmux` argv to spawn a role's per-thread window (detached) running `script`."
  @spec spawn_argv(String.t(), integer() | String.t(), String.t()) :: [String.t()]
  def spawn_argv(role_key, thread_id, script) do
    ws = workspace_id()
    Tmux.argv(ws, ["new-window", "-d", "-t", Tmux.session(ws), "-n", crew_window(role_key, thread_id), script])
  end

  @doc "The `tmux` argv to tear down a role's per-thread window."
  @spec kill_argv(String.t(), integer() | String.t()) :: [String.t()]
  def kill_argv(role_key, thread_id) do
    ws = workspace_id()
    Tmux.argv(ws, ["kill-window", "-t", Tmux.target(ws, crew_window(role_key, thread_id))])
  end

  @doc """
  The window's boot script: set TERM, source the server `exports` block (so `${TLON_MCP_URL}` etc.
  reach pi's env), then `exec` the bare pi launcher. Mirrors `Cockpit.spawn_agent_window/3` — a
  role's window rides the ALREADY-created `r<tid>` window on the shared tlon server, so it must
  exec the bare `Cockpit.pi_command/1`, never `profile_launcher/1` (a `tmux new-session` wrapper
  meant for a coworker's own dedicated server — execing it here would nest a second server).
  """
  @spec boot_script(String.t(), String.t()) :: String.t()
  def boot_script(exports, launcher) do
    "export TERM=xterm-256color\n" <> exports <> "\nexec " <> launcher
  end

  # The reviewer runs on the SAME server the cockpit uses — the injected minter defaults to
  # Server.MCP.Spawn.join, which mints in-node against the live Repo/tokens (this backend runs inside
  # the cockpit BEAM), so the identity is valid the instant the reviewer's pi connects to :4041.
  defp cmd_runner, do: Application.get_env(:console, :crew_cmd, &System.cmd/3)
  defp joiner, do: Application.get_env(:console, :crew_join, &Server.MCP.Spawn.join/3)

  # Wait between window boot and injecting the opening turn — the profile pi's TUI must settle before
  # send-keys, same reason as Cockpit's @opening_submit_delay_ms two-phase inject. Overridable via app
  # env (`:console, :crew_settle_ms`) so tests don't pay the real delay.
  @opening_settle_ms 1_500
  defp opening_settle_ms, do: Application.get_env(:console, :crew_settle_ms, @opening_settle_ms)

  # Readiness gate for the opening inject: a fresh-profile pi boots for several seconds (npm
  # bootstrap of its extensions, MCP refresh, server register) — far longer than a fixed settle — so
  # we POLL the pane for pi's server-registered footer before sending Enter, or a booting TUI swallows
  # it and the turn sits unsubmitted. `@ready_marker` is the console footer's own text (our UI). Poll
  # cadence + budget are app-env overridable so tests don't pay the real wait, same as crew_settle_ms.
  @ready_marker "registered"
  @ready_poll_ms 500
  @ready_timeout_ms 20_000
  defp ready_poll_ms, do: Application.get_env(:console, :crew_poll_ms, @ready_poll_ms)
  defp ready_timeout_ms, do: Application.get_env(:console, :crew_ready_timeout_ms, @ready_timeout_ms)

  @doc """
  Spawn `role_key` onto task `thread_id` as a server citizen, then inject the leader's `task` as its
  opening turn. Returns `{:ok, window}`. `opts[:inject]` (default true) can be set false in tests to
  skip the timed send-keys.
  """
  @spec spawn(String.t(), integer() | String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def spawn(role_key, thread_id, task, opts \\ []) do
    with {:workspace, %{}} <- {:workspace, Space.first_workspace()},
         %{handle: handle, profile: profile_name} <- role(role_key) || :unknown_role,
         %Console.Profile{} = profile <- Profiles.fetch(profile_name) || {:missing_profile, profile_name},
         _dir = Profiles.materialise!(profile),
         {:ok, %{exports: exports}} <- joiner().(thread_id, handle, mandate: "machine", assign: false),
         # Slice D: the profile's harness DRIVER supplies the exec — a claude_code-bound reviewer
         # (anthropic model at home) rides the official launcher, never sonnet-through-pi.
         script = boot_script(exports, Console.Harness.driver(profile.harness).launch_command(profile)),
         {:ok, window} <- run_spawn(role_key, thread_id, script) do
      if Keyword.get(opts, :inject, true), do: inject_opening(window, opening_turn(thread_id, task))
      {:ok, window}
    else
      # No workspace at all (server down — the fallback Workspace is gone, reshape slice A):
      # there is no tmux server to target, refuse rather than nil-crash.
      {:workspace, nil} -> {:error, :no_workspace}
      :unknown_role -> {:error, {:unknown_role, role_key}}
      {:missing_profile, _} = err -> {:error, err}
      {:error, _} = err -> err
      other -> {:error, other}
    end
  end

  # Shells out to tmux and folds its exit status into a tagged result — `spawn/4`'s @spec promises
  # `{:error, term()}`, never a crash, so a duplicate window (very plausible re-spawning onto the
  # same thread) or any other nonzero exit must not raise a MatchError.
  defp run_spawn(role_key, thread_id, script) do
    case cmd_runner().("tmux", spawn_argv(role_key, thread_id, script), stderr_to_stdout: true) do
      {_out, 0} -> {:ok, crew_window(role_key, thread_id)}
      {out, _status} -> {:error, {:tmux_failed, out}}
    end
  end

  @doc "Tear down a role's window on a thread. Best-effort; a missing window (or no
  workspace at all) is not an error."
  @spec kill(String.t(), integer() | String.t()) :: :ok
  def kill(role_key, thread_id) do
    if Space.first_workspace() do
      _ = cmd_runner().("tmux", kill_argv(role_key, thread_id), stderr_to_stdout: true)
    end

    :ok
  end

  # `Server.Crew` behaviour — the doors the server's spawn_crew/kill_crew tools land in. Thin delegates to
  # the IO wrappers above; the leader's handle in `opening_turn/2` is claude-machine (MVP lead).
  # spawn/4 (not spawn/3) — a local spawn/3 call is ambiguous with Kernel.spawn/3.
  @impl Server.Crew
  def spawn_role(role_key, thread_id, task), do: spawn(role_key, thread_id, task, [])

  @impl Server.Crew
  def kill_role(role_key, thread_id), do: kill(role_key, thread_id)

  # The opening assignment the leader hands the reviewer. Names the leader handle so the reviewer's
  # @<leader> ESCALATE resolves — MVP leader is claude-machine (the task thread's staffed lead).
  defp opening_turn(thread_id, task) do
    "You are reviewing on server thread ##{thread_id}. Leader handle: claude-machine. " <>
      "Task: #{task}. Read the diff (git diff/show), post findings, and escalate any fix per your protocol."
  end

  # Two-phase send-keys into the window, but only once pi is input-ready: await the registered
  # footer (`await_ready`), type the literal text, settle, then Enter as a SEPARATE burst. Waiting
  # for ready is what stops a booting TUI from swallowing the Enter and leaving the turn unsubmitted.
  # Best-effort throughout — a poll timeout still injects (the deadline outlasts a normal boot).
  defp inject_opening(window, text) do
    ws = workspace_id()
    runner = [runner: cmd_runner()]
    _ = await_ready(ws, window, runner)
    Tmux.send_text(ws, window, text, runner)
    Process.sleep(opening_settle_ms())
    Tmux.submit(ws, window, runner)
  end

  # Poll the pane until it shows pi's registered footer (or the budget elapses). Returns whether it
  # became ready — the caller injects either way, so a never-ready pane degrades to the old behaviour
  # rather than dropping the turn.
  defp await_ready(ws, window, runner),
    do: poll_ready(ws, window, runner, div(ready_timeout_ms(), max(ready_poll_ms(), 1)))

  defp poll_ready(_ws, _window, _runner, remaining) when remaining <= 0, do: false

  defp poll_ready(ws, window, runner, remaining) do
    case Tmux.run(ws, ["capture-pane", "-p", "-t", Tmux.target(ws, window)], runner) do
      {out, 0} when is_binary(out) ->
        if String.contains?(out, @ready_marker) do
          true
        else
          Process.sleep(ready_poll_ms())
          poll_ready(ws, window, runner, remaining - 1)
        end

      _ ->
        false
    end
  end
end
