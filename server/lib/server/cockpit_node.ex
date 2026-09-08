defmodule Server.CockpitNode do
  @moduledoc """
  Where the cockpit is, when the server is its own node (docs/plans/2026-09-08-one-brain-client-server-plan.md
  phase 3). The cockpit connects as `console@<host>` (`Console.Backend.Link`); the arbiter and
  crew backends that need a terminal find it here and `:erpc` into the console's own
  implementations. No cockpit connected is the always-up service's normal state: `{:error,
  :no_cockpit}`, the same honest degrade as no backend at all.
  """

  @timeout 15_000

  @doc "The connected cockpit node, or nil."
  @spec find() :: node() | nil
  def find do
    Enum.find(Node.list(), fn n -> n |> Atom.to_string() |> String.starts_with?("console@") end)
  end

  @doc "Call `mod.fun(args)` on the cockpit; `{:error, :no_cockpit}` when none is connected or it drops mid-call."
  @spec call(module(), atom(), [term()]) :: term() | {:error, :no_cockpit}
  def call(mod, fun, args) do
    case find() do
      nil -> {:error, :no_cockpit}
      node -> :erpc.call(node, mod, fun, args, @timeout)
    end
  rescue
    e in ErlangError ->
      case e.original do
        {:erpc, _} -> {:error, :no_cockpit}
        {:exception, reason, stack} -> :erlang.raise(:error, reason, stack)
        _ -> reraise e, __STACKTRACE__
      end
  end
end

defmodule Server.Arbiter.Remote do
  @moduledoc "The arbiter is the connected cockpit's `Console.Arbiter`, reached over distribution."
  @behaviour Server.Arbiter

  @impl true
  def wake(session, prompt), do: Server.CockpitNode.call(Console.Arbiter, :wake, [session, prompt])

  @impl true
  def spawn(exports), do: Server.CockpitNode.call(Console.Arbiter, :spawn, [exports])
end

defmodule Server.Crew.Remote do
  @moduledoc "The crew backend is the connected cockpit's `Console.Crew`, reached over distribution."
  @behaviour Server.Crew

  @impl true
  def spawn_role(role, thread_id, task), do: Server.CockpitNode.call(Console.Crew, :spawn_role, [role, thread_id, task])

  @impl true
  def kill_role(role, thread_id), do: Server.CockpitNode.call(Console.Crew, :kill_role, [role, thread_id])
end
