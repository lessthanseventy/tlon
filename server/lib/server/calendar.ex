defmodule Server.Calendar do
  @moduledoc """
  The operator's calendars, for the alerts a meeting earns (`Server.Alerts`). Each source is a
  `.ics` feed named in the settings file (`Server.OperatorConfig`):

      "calendars": [
        {"name": "work", "ics_secret": "calendar-work"},
        {"name": "team", "ics": "https://calendar.zoho.com/ical/…/basic.ics"}
      ]

  `ics` is the feed's address; `ics_secret` names a machine secret holding it
  (`$XDG_RUNTIME_DIR/agenix/<name>`) — Google's and Zoho's private addresses are credentials, and
  tlon never stores one. Feeds are fetched in the background every `@every_ms` and kept;
  `upcoming/2` answers from the last good copy of each (`Server.Calendar.Feed` reads them), so a
  read never waits on the network and a failed fetch leaves the last copy standing. On unless
  `TLON_CALENDAR=0` (`:start_calendar`).
  """
  use GenServer

  alias Server.Calendar.Feed

  @every_ms 10 * 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "Meetings overlapping `{from, to}` across the calendars, each tagged `calendar: name`; [] when off."
  @spec upcoming(GenServer.server(), {DateTime.t(), DateTime.t()}) :: [map()]
  def upcoming(server \\ __MODULE__, {from, to}) do
    if GenServer.whereis(server) do
      for {name, ics} <- GenServer.call(server, :feeds),
          m <- occurrences(ics, from, to),
          do: Map.put(m, :calendar, name)
    else
      []
    end
  end

  @doc """
  The day's birthdays and anniversaries across the calendars (`Feed.celebrations/2`); [] when off.
  Computed once per day per fetch and kept, since `Server.Office.status/0` asks on every poll.
  """
  @spec celebrations(GenServer.server(), Date.t()) :: [map()]
  def celebrations(server \\ __MODULE__, day) do
    if GenServer.whereis(server) do
      GenServer.call(server, {:celebrations, day})
    else
      []
    end
  end

  @doc "Fetch every source now (and wait for it) — the timer's work, for a test or an operator."
  def refresh(server \\ __MODULE__), do: GenServer.call(server, :refresh, 60_000)

  @doc "A source's feed address: its `ics`, or the machine secret its `ics_secret` names."
  @spec url(map(), String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def url(source, runtime_dir \\ System.get_env("XDG_RUNTIME_DIR"))
  def url(%{"ics" => url}, _dir) when is_binary(url), do: {:ok, url}

  def url(%{"ics_secret" => name}, dir) when is_binary(name) and is_binary(dir) do
    case File.read(Path.join([dir, "agenix", name])) do
      {:ok, body} -> {:ok, String.trim(body)}
      _ -> {:error, "no secret #{name}"}
    end
  end

  def url(_source, _dir), do: {:error, "a calendar needs an ics or an ics_secret"}

  @impl true
  def init(opts) do
    state = %{
      feeds: %{},
      cache: %{},
      celebrate: Keyword.get(opts, :celebrations, &Feed.celebrations/2),
      fetch: Keyword.get(opts, :fetch, &fetch/1),
      sources: Keyword.get(opts, :sources, fn -> List.wrap(Server.OperatorConfig.read()["calendars"]) end),
      every: Keyword.get(opts, :every_ms, @every_ms)
    }

    if state.every != :manual, do: send(self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_call(:feeds, _from, state), do: {:reply, state.feeds, state}
  def handle_call(:refresh, _from, state), do: {:reply, :ok, %{state | feeds: fetch_all(state), cache: %{}}}

  def handle_call({:celebrations, day}, _from, state) do
    case state.cache do
      %{^day => found} ->
        {:reply, found, state}

      cache ->
        found = for {_name, ics} <- state.feeds, c <- state.celebrate.(ics, day), do: c
        {:reply, found, %{state | cache: Map.put(cache, day, found)}}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    me = self()
    Task.Supervisor.start_child(Server.TaskSupervisor, fn -> GenServer.cast(me, {:fetched, fetch_all(state)}) end)
    Process.send_after(self(), :tick, state.every)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:fetched, feeds}, state), do: {:noreply, %{state | feeds: Map.merge(state.feeds, feeds), cache: %{}}}

  # the sources fetched this round, by name; a failed one is absent, so a merge keeps its last copy
  defp fetch_all(state) do
    for %{"name" => name} = source <- state.sources.(),
        {:ok, ics} <- [state.fetch.(source)],
        into: state.feeds,
        do: {name, ics}
  end

  defp fetch(source) do
    with {:ok, url} <- url(source), do: get(String.replace_prefix(url, "webcal://", "https://"))
  end

  defp get(url) do
    _ = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, {String.to_charlist(url), []}, [timeout: 20_000, connect_timeout: 5_000, ssl: ssl],
           body_format: :binary
         ) do
      {:ok, {{_v, 200, _r}, _headers, body}} -> {:ok, body}
      other -> {:error, other}
    end
  rescue
    e -> {:error, e}
  end

  # one feed whose recurrences can't be expanded drops out, rather than failing every caller's read
  defp occurrences(ics, from, to) do
    Feed.occurrences(ics, from, to)
  rescue
    _ -> []
  end
end
