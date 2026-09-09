defmodule Console.Backend.Link do
  @moduledoc """
  Keeps this node connected to the server node for `Console.Backend.Remote`.

  On start it makes the node distributed if it is not (`console-<pid>@127.0.0.1`, long names — the
  release uses `RELEASE_DISTRIBUTION=name`), sets the cookie from the shared cookie file
  (`TLON_COOKIE_FILE`, default `~/.local/share/tlon/cookie`; the same file `tlon.service` feeds
  `RELEASE_COOKIE` from), connects, and re-tries every 2 s while the server is away.
  `:net_kernel.monitor_nodes/1` reports the drop; `up?/0` is what the cockpit's banner and
  Doctor read; `subscribe/0` gets `{:server_link, :up | :down}` messages.

  `Server.PubSub` (pg adapter) spans connected nodes on its own: once this link is up, a Bus
  broadcast on the server reaches subscribers here with no further plumbing.
  """
  use GenServer

  alias Console.Backend.Remote

  require Logger

  @retry_ms 2_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Is the server node connected right now?"
  @spec up?() :: boolean()
  def up?, do: Remote.node_name() in Node.list()

  @doc "Block until the server node is connected, up to `ms`; `:ok` or `{:error, :server_down}`."
  @spec await(non_neg_integer()) :: :ok | {:error, :server_down}
  def await(ms) when ms <= 0, do: if(up?(), do: :ok, else: {:error, :server_down})

  def await(ms) do
    if up?() do
      :ok
    else
      Process.sleep(100)
      await(ms - 100)
    end
  end

  @doc "Receive `{:server_link, :up | :down}` in the caller's mailbox on every change."
  def subscribe, do: Registry.register(Console.Backend.Link.Registry, :link, nil)

  @impl true
  def init(opts) do
    ensure_distribution(opts)
    :net_kernel.monitor_nodes(true)
    send(self(), :connect)
    {:ok, %{up: false}}
  end

  @impl true
  def handle_info(:connect, state) do
    node = Remote.node_name()
    if !Node.alive?(), do: ensure_distribution([])

    if Node.connect(node) do
      {:noreply, flip(state, true)}
    else
      Process.send_after(self(), :connect, @retry_ms)
      {:noreply, flip(state, false)}
    end
  end

  def handle_info({:nodeup, node}, state) do
    if node == Remote.node_name(), do: {:noreply, flip(state, true)}, else: {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    if node == Remote.node_name() do
      Process.send_after(self(), :connect, @retry_ms)
      {:noreply, flip(state, false)}
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp flip(%{up: up} = state, up), do: state

  defp flip(state, up) do
    Logger.info("server link #{if up, do: "up", else: "down"} (#{Remote.node_name()})")

    Registry.dispatch(Console.Backend.Link.Registry, :link, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:server_link, if(up, do: :up, else: :down)})
    end)

    %{state | up: up}
  end

  # ── distribution ─────────────────────────────────────────────────────────────────────────
  # The node name carries the OS pid (console-12345@127.0.0.1): two cockpits — a stale one and
  # a fresh `console:run` — must never fight over one name (they did, 2026-09-08, and the loser
  # crashed the app). Server.CockpitNode finds any `console*@` node. A failure to start
  # distribution is logged and retried with the connect loop, never a crash: the cockpit still
  # renders, with the server-down state, and comes up the moment the node does.
  defp ensure_distribution(opts) do
    if Node.alive?() do
      set_cookie()
    else
      name = Keyword.get(opts, :name, default_node_name())

      case Node.start(name, :longnames) do
        {:ok, _} -> set_cookie()
        {:error, reason} -> Logger.warning("console node could not start distribution as #{name}: #{inspect(reason)}")
      end
    end
  rescue
    # The moduledoc promises this never crashes, and it has to be true of anything that runs here:
    # a raise fails this child, fails Console.Application, and the operator gets a blank screen.
    error -> Logger.warning("console node could not set up distribution: #{Exception.message(error)}")
  end

  defp default_node_name do
    case Application.get_env(:console, :node_name) do
      nil -> :"console-#{System.pid()}@127.0.0.1"
      name -> name
    end
  end

  @doc false
  def set_cookie do
    case {node(), cookie()} do
      # `Node.set_cookie/1` is `:erlang.set_cookie(node(), c)`, and on :nonode@nohost that raises
      # badarg — which took the whole application down and left the cockpit painting NOTHING, with
      # the reason buried in a redirected stderr log. Distribution not being up yet is a state the
      # connect loop already handles; it is not a reason to fail to boot.
      {:nonode@nohost, _cookie} ->
        Logger.warning("console node is not distributed yet — cookie unset; the connect loop will retry")

      {_node, nil} ->
        Logger.warning("no server cookie at #{cookie_file()} — the link will not authenticate")

      {_node, c} ->
        Node.set_cookie(c)
    end
  end

  @doc false
  def cookie_file, do: System.get_env("TLON_COOKIE_FILE") || Path.expand("~/.local/share/tlon/cookie")

  @doc false
  def cookie do
    case File.read(cookie_file()) do
      {:ok, s} when byte_size(s) > 0 -> s |> String.trim() |> String.to_atom()
      _ -> nil
    end
  end
end
