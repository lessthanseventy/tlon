defmodule Console.Backend.Remote do
  @moduledoc """
  The server is another node: the always-up `tlon.service` release (`funes@127.0.0.1`). Every
  call is an `:erpc.call/5` with a timeout; the node link itself (distribution start, cookie,
  connect + reconnect, up/down state) is `Console.Backend.Link`'s job. A call while the link is
  down raises `Console.Backend.ServerDown`, which the cockpit's `Console.Safe` wrappers already
  degrade into a fallback — so a server restart shows as stale panels, not a dead frame.
  """
  @behaviour Console.Backend

  @timeout 5_000

  @impl true
  def call(mod, fun, args) do
    :erlang.apply(:erpc, :call, [node_name(), mod, fun, args, @timeout])
  rescue
    e in ErlangError ->
      case e.original do
        # the link: not connected, or the server took longer than the timeout
        {:erpc, reason} when reason in [:noconnection, :timeout, :notsup] ->
          raise Console.Backend.ServerDown, node: node_name(), reason: reason, mfa: {mod, fun, length(args)}

        # a raise on the server comes back wrapped; re-raise it as itself so a call site's
        # `rescue` / Console.Safe sees the class it always saw
        {:exception, reason, stack} ->
          :erlang.raise(:error, reason, stack)

        {:throw, value} ->
          throw(value)

        {:exit, reason} ->
          exit(reason)

        _ ->
          reraise e, __STACKTRACE__
      end
  end

  @doc "The server node, `TLON_NODE` / `:console, :server_node`; the release's `RELEASE_NODE`."
  @spec node_name() :: node()
  def node_name, do: Application.get_env(:console, :server_node, :"funes@127.0.0.1")
end

defmodule Console.Backend.ServerDown do
  @moduledoc "The server node did not answer: not connected, or the call timed out."
  defexception [:node, :reason, :mfa]

  @impl true
  def message(%{node: n, reason: r, mfa: {m, f, a}}), do: "server #{n} #{r} on #{inspect(m)}.#{f}/#{a}"
end
