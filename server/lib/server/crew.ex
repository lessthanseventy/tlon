defmodule Server.Crew do
  @moduledoc """
  The crew backend — a **capability, not a product**, the same seam as `Server.Arbiter`. Staffing a
  reviewer (or any role) onto a thread means minting its server identity and standing up a terminal
  for it to run in; *how* that terminal is created is a local backend the design never names. server
  decides a role belongs on a thread; the backend *actuates*.

  The backend is chosen by config — `config :server, :crew, SomeModule` (a `Server.Crew` behaviour).
  Since one-brain B/2 that is `Server.Crew.Tmux` everywhere: a window beside the lead on the
  workspace's tmux server, spawned by the service or by an embedded console alike.

  **No backend configured is a valid state**: `spawn_role`/`kill_role` return `{:error, :no_crew}` —
  degrade honestly, no crash. `spawn_crew`/`kill_crew` (the MCP tools) surface that as an
  unavailable-tool error.

  A **role** is a seat, not an identity: `%{handle, window_prefix, profile}` names the server author
  the seat posts as, the tmux window it runs in, and the profile that materialises its config. The
  per-thread window name (`crew_window/2`) is a PURE function of (role, thread id), so the spawner
  and the mention router agree on `r<tid>` deterministically.
  """
  @callback spawn_role(role :: String.t(), thread_id :: integer(), task :: String.t()) ::
              {:ok, term()} | {:error, term()}
  @callback kill_role(role :: String.t(), thread_id :: integer()) :: :ok | {:error, term()}

  @roles %{
    "reviewer" => %{handle: "reviewer", window_prefix: "r", profile: "reviewer"}
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
