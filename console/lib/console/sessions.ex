defmodule Console.Sessions do
  @moduledoc """
  The live session terminals — one `Console.Terminal` per thread. A registry over a
  `DynamicSupervisor`: `ensure/2` starts a terminal for a thread (or returns the existing one),
  `terminal/1` looks it up, `all/0` lists them (for the roster). A
  terminal that exits (the child process ended) is dropped, so the map is never stale — the
  §3 "ask, don't mirror" rule applied to sessions: a dead pane leaves no ghost row.

  Terminals run under a DynamicSupervisor (not linked to this registry), so one crashing never
  takes the registry or the cockpit down; this GenServer only monitors them to keep the map honest.
  """
  use GenServer

  alias Console.Terminal

  @sup Console.TerminalSup

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Register the process (the cockpit) that watches all session terminals — every terminal is started
  with it as `:notify`, so both the `s` verb and the arbiter's autonomous spawn wake the same eye.
  """
  def observe(pid), do: GenServer.cast(__MODULE__, {:observe, pid})

  @doc """
  Spawn a harness as a session terminal on `thread_id` from its `exports` block — the one seam the
  cockpit's `s` and the arbiter both use. Builds a login-shell command that sources the TLON_* env
  (and `TERM`, so the harness produces colour) then execs the configured launcher.
  """
  def spawn_harness(thread_id, exports, opts \\ []) do
    # `:launcher` overrides the configured default — the Tlön center launches pi via a custom tmux
    # launcher (`Console.Staffing.profile_launcher/3`) through this same seam.
    {launcher, opts} = Keyword.pop(opts, :launcher, Application.get_env(:server, :spawn_launcher_pi, "pi"))
    # `env --default-signal` resets the child's signal dispositions to default before exec. The BEAM
    # runs SIGCHLD in a non-default state (it reaps its own children), and Ghostty.PTY's forkpty child
    # execs WITHOUT resetting signals (pty_nif.zig) — so a harness inherits it and every subprocess it
    # spawns (pi/bun's `bash` tool) fails `waitpid` with ECHILD, breaking its shell. Resetting here
    # gives the harness a clean TTY signal state. (Upstream ghostty_ex gap; this is the launcher-side fix.)
    script = Console.Staffing.boot_script(exports, "env --default-signal " <> launcher)

    ensure(thread_id, Keyword.merge([cmd: "/bin/bash", args: ["-lc", script]], opts))
  end

  @doc "Ensure a terminal for `thread_id`, starting one with `opts` if absent. `{:ok, pid}`."
  def ensure(thread_id, opts), do: GenServer.call(__MODULE__, {:ensure, thread_id, opts})

  @doc "The terminal pid for a thread, or nil."
  def terminal(thread_id), do: GenServer.call(__MODULE__, {:terminal, thread_id})

  @doc "All live session terminals as `%{thread_id => pid}`."
  def all, do: GenServer.call(__MODULE__, :all)

  @doc """
  End the terminal for `thread_id` (a no-op when there is none). The owner of a terminal is the
  surface showing it — the session pane's PTY dies when the centre moves off its thread — so the
  registry needs a teardown as well as the exit-driven drop.
  """
  def close(thread_id), do: GenServer.call(__MODULE__, {:close, thread_id})

  @impl true
  def init(:ok), do: {:ok, %{by_thread: %{}, by_ref: %{}, observer: nil}}

  @impl true
  def handle_cast({:observe, pid}, state), do: {:noreply, %{state | observer: pid}}

  @impl true
  def handle_call({:ensure, thread_id, opts}, _from, state) do
    case Map.get(state.by_thread, thread_id) do
      pid when is_pid(pid) ->
        {:reply, {:ok, pid}, state}

      nil ->
        # Every terminal notifies the registered observer (the cockpit), whoever asked to start it.
        opts = Keyword.put_new(opts, :notify, state.observer)

        case DynamicSupervisor.start_child(@sup, {Terminal, opts}) do
          {:ok, pid} ->
            ref = Process.monitor(pid)

            state = %{
              state
              | by_thread: Map.put(state.by_thread, thread_id, pid),
                by_ref: Map.put(state.by_ref, ref, thread_id)
            }

            {:reply, {:ok, pid}, state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:close, thread_id}, _from, state) do
    case Map.get(state.by_thread, thread_id) do
      nil ->
        {:reply, :ok, state}

      pid ->
        _ = DynamicSupervisor.terminate_child(@sup, pid)
        # Drop it here rather than waiting on our own DOWN: the caller's next `terminal/1` must not
        # hand back a dead pid.
        {refs, by_ref} = Enum.split_with(state.by_ref, fn {_ref, tid} -> tid == thread_id end)
        for {ref, _tid} <- refs, do: Process.demonitor(ref, [:flush])

        {:reply, :ok, %{state | by_thread: Map.delete(state.by_thread, thread_id), by_ref: Map.new(by_ref)}}
    end
  end

  def handle_call({:terminal, thread_id}, _from, state), do: {:reply, Map.get(state.by_thread, thread_id), state}

  def handle_call(:all, _from, state), do: {:reply, state.by_thread, state}

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.by_ref, ref) do
      {nil, _by_ref} -> {:noreply, state}
      {thread_id, by_ref} -> {:noreply, %{state | by_thread: Map.delete(state.by_thread, thread_id), by_ref: by_ref}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
