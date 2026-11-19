defmodule Server.Home.Day do
  @moduledoc """
  The home's meetings: what `Server.Calendar` holds for today and tomorrow, cleaned
  (`Server.Calendar.clean/1`: cancelled, free all-day and doubled ones are gone), as
  `%{title, starts_at, ends_at, tentative, all_day, day}` in UTC, `day` `"today"` or `"tomorrow"`,
  soonest first. Today and tomorrow are the machine's wall-clock days (`Server.Home.Clock`); today's
  are the ones not over yet. An all-day event is on each date it covers, from that local midnight.
  `between/3` answers any run of local dates the same way, each row carrying its `date`.
  The home only reads: nothing here writes a calendar or says anything unasked.
  """

  alias Server.Home.Clock

  @type meeting :: %{
          title: String.t(),
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          tentative: boolean(),
          all_day: boolean(),
          day: String.t()
        }

  @doc "The meetings of today (the rest of it) and tomorrow at `now`, from the calendars; [] when none are set."
  @spec meetings(DateTime.t(), GenServer.server()) :: [meeting()]
  def meetings(%DateTime{} = now, server \\ Server.Calendar) do
    today = today(now)
    from = midnight(today)
    to = midnight(Date.add(today, 2))
    # an all-day event is held at UTC midnights, so the fetch is a day wider each way
    found = Server.Calendar.upcoming(server, {DateTime.add(from, -1, :day), DateTime.add(to, 1, :day)})
    build(found, now)
  end

  @doc """
  The meetings on each local date from `from` to `to` inclusive, past dates too, from what the
  calendars hold: `%{title, starts_at, ends_at, tentative, all_day, date}` (`date` ISO 8601), by
  date, all-day first, then soonest.
  """
  @spec between(Date.t(), Date.t(), GenServer.server()) :: [map()]
  def between(%Date{} = from, %Date{} = to, server \\ Server.Calendar) do
    window = {DateTime.add(midnight(from), -1, :day), DateTime.add(midnight(Date.add(to, 1)), 1, :day)}
    server |> Server.Calendar.upcoming(window) |> on_dates(Date.range(from, to))
  end

  @doc "The meetings in `found` (`Server.Calendar.upcoming/2` rows) on each of `dates`, as `between/3` gives them."
  @spec on_dates([map()], Enumerable.t()) :: [map()]
  def on_dates(found, dates) do
    cleaned = Server.Calendar.clean(found)

    rows =
      for date <- dates, {m, starts_at, ends_at} <- placed(cleaned, date) do
        m |> row(starts_at, ends_at) |> Map.put(:date, Date.to_iso8601(date))
      end

    Enum.sort_by(rows, &{&1.date, not &1.all_day, DateTime.to_unix(&1.starts_at)})
  end

  @doc "The meetings in `found` (`Server.Calendar.upcoming/2` rows) that fall on today or tomorrow at `now`."
  @spec build([map()], DateTime.t()) :: [meeting()]
  def build(found, %DateTime{} = now) do
    today = today(now)
    cleaned = Server.Calendar.clean(found)

    rows =
      for {name, date} <- [{"today", today}, {"tomorrow", Date.add(today, 1)}],
          {m, starts_at, ends_at} <- placed(cleaned, date),
          name == "tomorrow" or DateTime.compare(ends_at, now) != :lt do
        m |> row(starts_at, ends_at) |> Map.put(:day, name)
      end

    Enum.sort_by(rows, & &1.starts_at, DateTime)
  end

  defp row(m, starts_at, ends_at) do
    %{title: m.title, starts_at: starts_at, ends_at: ends_at, tentative: m.busy == :tentative, all_day: m.all_day}
  end

  defp placed(cleaned, date), do: for(m <- cleaned, {s, e} <- span(m, date), do: {m, s, e})

  defp today(now), do: now |> Clock.local() |> NaiveDateTime.to_date()

  defp midnight(date), do: Clock.utc(NaiveDateTime.new!(date, ~T[00:00:00]))

  # the meeting's start and end when it is on `date`, else none
  defp span(%{all_day: true} = m, date) do
    first = DateTime.to_date(m.start)
    last = m.stop |> DateTime.to_date() |> Date.add(-1)

    if Date.compare(date, first) != :lt and Date.compare(date, last) != :gt,
      do: [{midnight(date), midnight(Date.add(date, 1))}],
      else: []
  end

  defp span(m, date) do
    from = midnight(date)
    to = midnight(Date.add(date, 1))

    if DateTime.compare(m.start, to) == :lt and DateTime.compare(m.stop, from) == :gt,
      do: [{m.start, m.stop}],
      else: []
  end
end
