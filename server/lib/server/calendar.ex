defmodule Server.Calendar do
  @moduledoc """
  The operator's calendars, read by the alerts a meeting earns (`Server.Alerts`), by the home's day
  (`Server.Home.Day`: `GET /api/home`, the reader's answers) and by the office's celebrations
  (`Server.Office`). Each source is a `.ics` feed named in the settings file (`Server.OperatorConfig`):

      "calendars": [
        {"name": "work", "ics_secret": "calendar-work"},
        {"name": "team", "ics": "https://calendar.zoho.com/ical/…/basic.ics"}
      ]

  `ics` is the feed's address; `ics_secret` names a machine secret holding it
  (`$XDG_RUNTIME_DIR/agenix/<name>`) — Google's and Zoho's private addresses are credentials, and
  tlon never stores one. Feeds are fetched in a task every `@every_ms`, parsed once when fetched
  (`Server.Calendar.Feed.read/1`) and kept; `upcoming/2` answers from the last good parse of each, so
  a read never parses a feed, never waits on the network or on a fetch in flight (`refresh/1`
  included), and a failed fetch leaves the last copy standing. On unless `TLON_CALENDAR=0`
  (`:start_calendar`).
  """
  use GenServer

  alias Server.Calendar.Feed

  @every_ms 10 * 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "Meetings overlapping `{from, to}` across the calendars, each tagged `calendar: name`; [] when off."
  @spec upcoming(GenServer.server(), {DateTime.t(), DateTime.t()}) :: [map()]
  def upcoming(server \\ __MODULE__, {from, to}) do
    if GenServer.whereis(server) do
      for {name, parsed} <- GenServer.call(server, :parsed),
          m <- occurrences(parsed, from, to),
          do: Map.put(m, :calendar, name)
    else
      []
    end
  end

  @doc """
  Meetings as a person would list them: cancelled ones dropped, all-day events shown as free (other
  people's out-of-office, holidays) dropped, and exact doubles dropped (the same title and start once
  `title/1` has stripped what an outside calendar adds: the "Synced invitation: " copies). The title
  of each is the stripped one. Order is kept; the first of a double stays.
  """
  @spec clean([map()]) :: [map()]
  def clean(meetings) do
    meetings
    |> Enum.reject(&(&1.cancelled or (&1.all_day and &1.busy == :free)))
    |> Enum.map(&Map.update!(&1, :title, fn t -> title(t) end))
    |> Enum.uniq_by(&{String.downcase(&1.title), &1.start})
  end

  @doc """
  The meetings worth an alarm: `clean/1`, without all-day events and without ones shown as free (not
  accepted as busy time). A tentative one stays.
  """
  @spec alarmable([map()]) :: [map()]
  def alarmable(meetings), do: meetings |> clean() |> Enum.reject(&(&1.all_day or &1.busy == :free))

  @doc """
  A meeting title without a leading "[EXT] " or "Synced invitation: " and without the trailing
  " @ Wed Nov 4 … (name@example.com)" an outside calendar puts on a recurring copy.
  """
  @spec title(String.t()) :: String.t()
  def title(title) do
    title
    |> String.trim()
    |> String.replace(~r/^(?:\[EXT\]\s*|Synced invitation:\s*)+/i, "")
    |> String.replace(~r/\s+@\s.*\([^()]*\)\s*$/, "")
    |> String.trim()
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
      parsed: %{},
      fetching: false,
      waiters: [],
      cache: %{},
      celebrate: Keyword.get(opts, :celebrations, &Feed.celebrations/2),
      fetch: Keyword.get(opts, :fetch, &get_feed/1),
      sources: Keyword.get(opts, :sources, fn -> List.wrap(Server.OperatorConfig.read()["calendars"]) end),
      every: Keyword.get(opts, :every_ms, @every_ms)
    }

    if state.every != :manual, do: send(self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_call(:parsed, _from, state), do: {:reply, state.parsed, state}
  def handle_call(:refresh, from, state), do: {:noreply, fetch(state, [from])}

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
    Process.send_after(self(), :tick, state.every)
    {:noreply, fetch(state, [])}
  end

  @impl true
  def handle_cast({:fetched, got}, state) do
    Enum.each(state.waiters, &GenServer.reply(&1, :ok))

    {:noreply,
     %{
       state
       | feeds: Map.merge(state.feeds, Map.new(got, fn {name, {ics, _}} -> {name, ics} end)),
         parsed: Map.merge(state.parsed, Map.new(got, fn {name, {_, parsed}} -> {name, parsed} end)),
         cache: %{},
         fetching: false,
         waiters: []
     }}
  end

  # a fetch in a task, its result swapped in when done; one already in flight is waited for, not doubled
  defp fetch(%{fetching: true} = state, waiters), do: %{state | waiters: state.waiters ++ waiters}

  defp fetch(state, waiters) do
    me = self()

    Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
      got =
        try do
          fetch_all(state)
        rescue
          _ -> %{}
        end

      GenServer.cast(me, {:fetched, got})
    end)

    %{state | fetching: true, waiters: waiters}
  end

  # the sources fetched this round, by name, with their parse; a failed one is absent, so a merge keeps its last copy
  defp fetch_all(state) do
    for %{"name" => name} = source <- state.sources.(),
        {:ok, ics} <- [state.fetch.(source)],
        into: %{},
        do: {name, {ics, Feed.read(ics)}}
  end

  defp get_feed(source) do
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
  defp occurrences(parsed, from, to) do
    Feed.occurrences(parsed, from, to)
  rescue
    _ -> []
  end
end
