defmodule Server.Crew do
  @moduledoc """
  The crew backend — a **capability, not a product**, the same seam as `Server.Arbiter`. Staffing a
  reviewer (or any role) onto a thread means minting its server identity and standing up a terminal
  for it to run in; *how* that terminal is created is a local backend the design never names. server
  decides a role belongs on a thread; the backend *actuates*.

  The backend is chosen by config — `config :server, :crew, SomeModule` (a `Server.Crew` behaviour).
  On the console hub that is `Console.Crew`, which spawns the role's window on the standing tlon tmux
  server in the SAME live node — so no second BEAM boots and no port is re-bound. server never
  imports console; it calls through this behaviour and dispatches with `apply/3`.

  **No backend configured is a valid state** (the always-up service runs the durable channel with no
  terminals to spawn): `spawn_role`/`kill_role` return `{:error, :no_crew}` — degrade honestly, no
  crash. `spawn_crew`/`kill_crew` (the MCP tools) surface that as an unavailable-tool error.
  """
  @callback spawn_role(role :: String.t(), thread_id :: integer(), task :: String.t()) ::
              {:ok, term()} | {:error, term()}
  @callback kill_role(role :: String.t(), thread_id :: integer()) :: :ok | {:error, term()}

  @doc "The configured backend, or nil (crew tools report unavailable when none is set)."
  def impl, do: Application.get_env(:server, :crew)

  @doc "Spawn `role` onto `thread_id` with opening assignment `task`, via the configured backend."
  def spawn_role(role, thread_id, task), do: dispatch(:spawn_role, [role, thread_id, task])

  @doc "Tear down `role`'s terminal on `thread_id`, via the configured backend."
  def kill_role(role, thread_id), do: dispatch(:kill_role, [role, thread_id])

  defp dispatch(fun, args) do
    case impl() do
      nil -> {:error, :no_crew}
      module -> apply(module, fun, args)
    end
  end
end

defmodule Server.Crew.Test do
  @moduledoc """
  A capturing crew backend for tests: sends `{:crew_spawn, role, thread_id, task}` /
  `{:crew_kill, role, thread_id}` to the pid in `config :server, :test_pid`, so a test asserts what
  server decided to staff — without a real terminal.
  """
  @behaviour Server.Crew

  @impl true
  def spawn_role(role, thread_id, task) do
    if pid = Application.get_env(:server, :test_pid), do: send(pid, {:crew_spawn, role, thread_id, task})
    {:ok, "#{String.first(role)}#{thread_id}"}
  end

  @impl true
  def kill_role(role, thread_id) do
    if pid = Application.get_env(:server, :test_pid), do: send(pid, {:crew_kill, role, thread_id})
    :ok
  end
end
