defmodule Server.Consult.Mirror do
  @moduledoc """
  The consult mirror as a supervised process: subscribes to the message bus and, for each
  posted message, runs `Server.Consult.maybe_mirror/1` — the bidirectional bridge that
  carries a consult's replies between the two sides. Always-on (it only writes DB rows, it
  never pokes a pane, so it is safe where the switchboard is deliberately opt-in).

  A mirror failure must never take down the process that posted the original message, so
  the mirror runs here, isolated from `Server.Channel.post`, and a raise is caught and
  logged rather than crash-looping the supervisor. The ask itself is already a durable row
  before this runs; a missed mirror is a lost round-trip, never a lost message.
  """
  use GenServer

  alias Server.Bus
  alias Server.Consult

  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    # Subscribe synchronously so no live message is missed.
    Bus.subscribe_messages()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:message_posted, message}, state) do
    try do
      Consult.maybe_mirror(message)
    rescue
      e -> Logger.error("consult mirror failed: #{Exception.message(e)}")
    end

    {:noreply, state}
  end

  # A long-lived subscriber must not crash on a stray message (a late monitor, a library
  # info): ignore anything we do not handle.
  def handle_info(_msg, state), do: {:noreply, state}
end
