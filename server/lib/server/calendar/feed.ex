defmodule Server.Calendar.Feed do
  @moduledoc """
  One calendar feed's meetings in a time window: an `.ics` body parsed by `ICal`, each event's
  recurrences expanded (`ICal.Recurrence.stream/1`: RRULE, RDATE, EXDATE), a moved instance (an
  event carrying a RECURRENCE-ID) standing in for the occurrence it replaces, every time in UTC.
  All-day events are left out — there is nothing to be on time for. Each meeting is
  `%{uid, title, start, stop, link}`, `link` the way to join it (a Meet, Zoom, Teams or Webex URL
  from its URL, location or description), or nil.
  """

  @join ~r{https://(?:[\w-]+\.)*(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com)/[^\s"<>\\]+}

  @type meeting :: %{
          uid: String.t(),
          title: String.t(),
          start: DateTime.t(),
          stop: DateTime.t(),
          link: String.t() | nil
        }

  @doc "The feed's meetings that overlap `[from, to)`, by start time."
  @spec occurrences(String.t(), DateTime.t(), DateTime.t()) :: [meeting()]
  def occurrences(ics, from, to) do
    events = ics |> parse() |> Enum.filter(&timed?/1)
    {moved, series} = Enum.split_with(events, & &1.recurrence_id)
    replaced = MapSet.new(moved, &{&1.uid, utc(&1.recurrence_id)})

    series
    |> Enum.flat_map(fn e ->
      e |> starts(to) |> Enum.reject(&MapSet.member?(replaced, {e.uid, &1})) |> Enum.map(&meeting(e, &1))
    end)
    |> Enum.concat(Enum.map(moved, &meeting(&1, utc(&1.dtstart))))
    |> Enum.filter(&(DateTime.compare(&1.stop, from) == :gt and DateTime.compare(&1.start, to) == :lt))
    |> Enum.sort_by(& &1.start, DateTime)
  end

  @celebration ~r/birthday|anniversary/i

  @doc """
  The all-day birthdays and anniversaries on `day`, as `%{title, kind}` (`kind` "birthday" or
  "anniversary", by the title). A yearly series (`RRULE:FREQ=YEARLY`, how Google keeps a birthday)
  falls on its month and day every year from its start year on (`UNTIL` and `COUNT` are not
  read); any other all-day event only on its own date.
  """
  @spec celebrations(String.t(), Date.t()) :: [%{title: String.t(), kind: String.t()}]
  def celebrations(ics, day) do
    for %{dtstart: %Date{} = d, summary: title} = e when is_binary(title) <- parse(ics),
        kind = celebration_kind(title),
        on_day?(e, d, day),
        do: %{title: title, kind: kind}
  end

  defp celebration_kind(title) do
    case Regex.run(@celebration, title) do
      [word] -> String.downcase(word)
      _ -> nil
    end
  end

  defp on_day?(%{rrule: %{frequency: :yearly}}, d, day),
    do: {d.month, d.day} == {day.month, day.day} and Date.compare(day, d) != :lt

  defp on_day?(_e, d, day), do: d == day

  defp parse(ics) do
    case ICal.from_ics(ics) do
      %ICal{events: events} -> events
      _ -> []
    end
  rescue
    _ -> []
  end

  defp timed?(%{dtstart: %DateTime{}}), do: true
  defp timed?(%{dtstart: %NaiveDateTime{}}), do: true
  defp timed?(_all_day_or_none), do: false

  # every start up to `to`, in UTC; a series without a rule is its one start
  defp starts(%{rrule: nil} = e, _to), do: [utc(e.dtstart)]

  defp starts(e, to) do
    e
    |> ICal.Recurrence.stream()
    |> Stream.map(&utc/1)
    |> Enum.take_while(&(DateTime.compare(&1, to) == :lt))
  end

  defp meeting(e, start) do
    %{
      uid: e.uid,
      title: e.summary || "(no title)",
      start: start,
      stop: DateTime.add(start, length_s(e), :second),
      link: link(e)
    }
  end

  defp length_s(%{dtend: stop, dtstart: start}) when not is_nil(stop), do: DateTime.diff(utc(stop), utc(start))

  defp length_s(%{duration: %ICal.Duration{time: {h, m, s}, days: d, weeks: w}}),
    do: ((w * 7 + d) * 24 + h) * 3600 + m * 60 + s

  defp length_s(_), do: 0

  defp link(e) do
    Enum.find_value([e.url, e.location, e.description], fn
      text when is_binary(text) ->
        case Regex.run(@join, text) do
          [url] -> url
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  # a floating time (no zone) is read as UTC, the only reading that needs no guess about the machine
  defp utc(%DateTime{} = dt), do: DateTime.shift_zone!(dt, "Etc/UTC")
  defp utc(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")
end
