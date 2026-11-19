defmodule Server.Home.Day do
  @moduledoc """
  The home's meetings: what `Server.Calendar` holds for today and tomorrow, cleaned
  (`Server.Calendar.clean/1`: cancelled, free all-day and doubled ones are gone), as
  `%{title, starts_at, ends_at, tentative, all_day, day}` in UTC, `day` `"today"` or `"tomorrow"`,
  soonest first. Today and tomorrow are the machine's wall-clock days (`Server.Home.Clock`); today's
  are the ones not over yet. An all-day event is on each date it covers, from that local midnight.
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

  @doc "The meetings in `found` (`Server.Calendar.upcoming/2` rows) that fall on today or tomorrow at `now`."
  @spec build([map()], DateTime.t()) :: [meeting()]
  def build(found, %DateTime{} = now) do
    today = today(now)
    cleaned = Server.Calendar.clean(found)

    rows =
      for {name, date} <- [{"today", today}, {"tomorrow", Date.add(today, 1)}],
          m <- cleaned,
          {starts_at, ends_at} <- span(m, date),
          name == "tomorrow" or DateTime.compare(ends_at, now) != :lt do
        %{
          title: m.title,
          starts_at: starts_at,
          ends_at: ends_at,
          tentative: m.busy == :tentative,
          all_day: m.all_day,
          day: name
        }
      end

    Enum.sort_by(rows, & &1.starts_at, DateTime)
  end

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
