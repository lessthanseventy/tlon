defmodule Server.Home.Sources do
  @moduledoc """
  The poller: every 15 minutes the sources named in the `home_sources` setting (a comma list, default
  `""`, none) are asked what they suggest (`Server.Home.Source`) and what they offer is kept
  as proposals (`Server.Proposal`), nothing said to anyone. A source that fails is logged once per
  distinct reason, again when the reason changes and after it has worked, and leaves what it proposed
  before alone. Started with the home inbox (`TLON_START_HOME_INBOX=1`), never in tests unless a test
  starts it.
  """
  use GenServer

  alias Server.Proposal

  require Logger

  @every_ms 15 * 60_000
  @first_ms 20_000

  @doc "Start the poller; `opts[:first_ms]` is the wait before the first poll, `opts[:every_ms]` the one between."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Ask each source in `names` (as the `home_sources` setting reads, a list of names) at `now` for
  `via`, from `modules` (name to module). `failed` is each failing source's last reason; the new one
  is answered, and a reason not seen before is logged.
  """
  @spec poll(String.t(), [String.t()], %{String.t() => module()}, DateTime.t(), map()) :: map()
  def poll(via, names, modules, now, failed) do
    Enum.reduce(names, %{}, fn name, kept ->
      case modules do
        %{^name => module} -> Map.merge(kept, run(via, module, now, failed))
        _ -> Map.merge(kept, unknown(name, failed))
      end
    end)
  end

  @doc "The sources a `home_sources` setting `value` names."
  @spec names(String.t()) :: [String.t()]
  def names(value), do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  @impl true
  def init(opts) do
    state = %{every: Keyword.get(opts, :every_ms, @every_ms), failed: %{}}
    Process.send_after(self(), :poll, Keyword.get(opts, :first_ms, @first_ms))
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, %{every: every, failed: failed} = state) do
    messenger = Application.get_env(:server, :home_messenger, Server.Home.Telegram)
    modules = Application.get_env(:server, :home_source_modules, %{"mail" => Server.Home.Source.Mail})
    names = names(Server.OperatorConfig.setting("home_sources"))
    Process.send_after(self(), :poll, every)
    {:noreply, %{state | failed: poll(messenger.name(), names, modules, DateTime.utc_now(), failed)}}
  end

  defp run(via, module, now, failed) do
    name = module.name()

    case pull(via, module, now) do
      {:ok, refused} ->
        for key <- refused, into: %{}, do: {{name, key}, refused(failed, name, key)}

      {:error, reason} ->
        if failed[name] != reason, do: Logger.warning("home source #{name}: #{inspect(reason)}")
        %{name => reason}
    end
  end

  defp refused(failed, name, key) do
    if failed[{name, key}] != :seen, do: Logger.warning("home source #{name}: #{key} could not be filed")
    :seen
  end

  defp unknown(name, failed) do
    if failed[name] != :unknown, do: Logger.warning("home source #{name}: no such source")
    %{name => :unknown}
  end

  defp pull(via, module, now) do
    with {:ok, proposals, resolved} <- module.fetch() do
      refused = Proposal.offer(via, module.name(), proposals, now, module.auto())
      Proposal.resolve(module.name(), resolved, now)
      {:ok, refused}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end
end
