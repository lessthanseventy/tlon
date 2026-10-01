defmodule Server.Attention.Poller do
  @moduledoc """
  Runs `Server.Attention.tick/0` and `Server.Attention.Stall.tick/2` every few seconds on the
  service (`TLON_START_ATTENTION=1`), carrying the stall pass's pane memory as its state.
  A GenServer, not an Oban job: this is a sub-minute read of pane text with nothing durable to
  lose — a missed tick is the next tick, and Oban's cron cannot go under a minute. A tick that
  raises is logged and never stops the loop.
  """

  use GenServer

  require Logger

  @default_interval_ms 5_000

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, Application.get_env(:server, :attention_poll_ms, @default_interval_ms))
    Process.send_after(self(), :tick, interval)
    {:ok, {interval, %{}}}
  end

  @impl true
  def handle_info(:tick, {interval, panes}) do
    panes =
      try do
        Server.Attention.tick()
        Server.Attention.Stall.tick(panes)
      rescue
        e ->
          Logger.warning("attention: tick failed — #{Exception.message(e)}")
          panes
      end

    Process.send_after(self(), :tick, interval)
    {:noreply, {interval, panes}}
  end
end
