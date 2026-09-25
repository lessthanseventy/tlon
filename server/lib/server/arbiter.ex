defmodule Server.Arbiter do
  @moduledoc """
  The terminal arbiter — a **capability, not a product** (§8, console §6). Waking an external agent
  session means poking its terminal so a turn happens; how that poke is delivered is a local
  backend the design never names. Elixir decides *who* to wake; the arbiter *actuates*.

  The backend is chosen by config — `config :server, :arbiter, SomeModule` (a `Server.Arbiter`
  behaviour). Since one-brain B that is `Server.Arbiter.Tmux` everywhere — send-keys into the
  thread's window on the workspace's tmux server; the server's tests use `Server.Arbiter.Test`. **No backend configured is
  a valid state** (the always-up service runs the durable channel without a display): `wake`/`spawn`
  return `{:error, :no_arbiter}` and the switchboard leaves the message a pending durable row —
  degrade honestly, no ceremony backend, no crash.

  `wake/2` takes the recipient SESSION (it carries `thread_id`, `pane_ref`, `agent`), so a backend
  can address the terminal however it keys them — by thread for console, by pane for a tmux backend.
  """
  @callback wake(session :: map(), prompt :: String.t()) :: :ok | {:error, term()}

  @doc """
  Spawn a FRESH terminal for a thread whose identity block is `exports` (the `export TLON_*` from
  `Server.MCP.Spawn`) — the cold-thread strand (§4c.3). Both console's `s` verb and the switchboard's
  autonomous wake spawn through the same seam. `{:ok, handle}` or `{:error, term}`.
  """
  @callback spawn(exports :: String.t()) :: {:ok, term()} | {:error, term()}
  @doc "Optional: is the spawned pane ready for its first prompt (an input line is up)? Absent = always."
  @callback ready?(handle :: term()) :: boolean()

  @doc "The configured backend, or nil (the switchboard runs but does not poke when none is set)."
  def impl, do: Application.get_env(:server, :arbiter)

  @doc "Wake a session's terminal with `prompt`, via the configured backend."
  def wake(session, prompt), do: dispatch(:wake, [session, prompt])

  @doc "Spawn a fresh terminal for an `exports` block, via the configured backend."
  def spawn(exports), do: dispatch(:spawn, [exports])

  defp dispatch(fun, args) do
    case impl() do
      nil -> {:error, :no_arbiter}
      module -> apply(module, fun, args)
    end
  end

  @doc """
  Is a spawned handle's pane ready for its first prompt? Backends that can look (tmux) say so; one that
  cannot — or none — is `true`, so a caller never waits on what it cannot observe.
  """
  def ready?(handle) do
    case impl() do
      nil ->
        true

      module ->
        if Code.ensure_loaded?(module) and function_exported?(module, :ready?, 1), do: module.ready?(handle), else: true
    end
  end
end

defmodule Server.Arbiter.Test do
  @moduledoc """
  A capturing arbiter for tests: sends `{:woke, pane_ref, prompt}` / `{:spawned, exports}` to the
  pid in `config :server, :test_pid`, so a test asserts exactly what the switchboard decided —
  without a real terminal.
  """
  @behaviour Server.Arbiter

  @impl true
  def wake(session, prompt) do
    if pid = Application.get_env(:server, :test_pid), do: send(pid, {:woke, session.pane_ref, prompt})
    :ok
  end

  @impl true
  def spawn(exports) do
    if pid = Application.get_env(:server, :test_pid), do: send(pid, {:spawned, exports})
    {:ok, :test}
  end

  @impl true
  def ready?(_handle), do: true
end
