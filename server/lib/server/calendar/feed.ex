defmodule Server.Calendar.Feed do
  @moduledoc """
  One calendar feed's meetings in a time window: an `.ics` body parsed by `ICal`, each event's
  recurrences expanded (`ICal.Recurrence.stream/1`: RRULE, RDATE, EXDATE), a moved instance (an
  event carrying a RECURRENCE-ID) standing in for the occurrence it replaces, every time in UTC.
  An all-day event runs from its date's midnight to its end date's, UTC. Each meeting is
  `%{uid, title, start, stop, link, cancelled, busy, all_day}`: `link` the way to join it (a Meet,
  Zoom, Teams or Webex URL from its URL, location or description), or nil; `cancelled` by STATUS or
  a "Canceled:" / "Cancelled:" title; `busy` one of `:free | :tentative | :busy | :away`, from
  Outlook's X-MICROSOFT-CDO-BUSYSTATUS, else TRANSP, else STATUS.

  A TZID that is a Windows zone name is read by `ICal`, except UTC's spellings, which are made
  `Etc/UTC` here. One the parser cannot read is logged once and takes, in this order: the region's
  zone when the feed's own VTIMEZONE of that name carries a US or EU daylight rule at a known
  standard offset (daylight time right); that VTIMEZONE's standard offset otherwise; the
  `(UTC±hh:mm)` prefix of the name as a fixed offset; UTC. Fixed offsets are whole hours only
  (`Etc/GMT-14` to `Etc/GMT+12`), so a fixed one is an hour off in summer for a zone with daylight
  time, and a half-hour one is UTC. The body is unfolded (a CRLF and a space or tab joins a line to
  the one before) before any of this.
  """

  require Logger

  @join ~r{https://(?:[\w-]+\.)*(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com)/[^\s"<>\\]+}

  @type meeting :: %{
          uid: String.t(),
          title: String.t(),
          start: DateTime.t(),
          stop: DateTime.t(),
          link: String.t() | nil,
          cancelled: boolean(),
          busy: :free | :tentative | :busy | :away,
          all_day: boolean()
        }

  @tzid ~r/TZID=(?|"([^"]+)"|([^:;"\r\n]+))/
  @iana ~r{^[A-Za-z_]+/[A-Za-z0-9_+\-/]+$}
  @us_std %{
    -300 => "America/New_York",
    -360 => "America/Chicago",
    -420 => "America/Denver",
    -480 => "America/Los_Angeles",
    -540 => "America/Anchorage"
  }
  @eu_std %{0 => "Europe/London", 60 => "Europe/Berlin", 120 => "Europe/Helsinki"}

  @opaque parsed :: %{events: [ICal.Event.t()]}

  @doc "A feed body read once: its time-zone names made readable and its events parsed, for `occurrences/3` to ask often."
  @spec read(String.t()) :: parsed()
  def read(ics), do: %{events: ics |> parse() |> Enum.filter(&meeting?/1)}

  @doc "The feed's (a body, or its `read/1`) meetings that overlap `[from, to)`, by start time."
  @spec occurrences(String.t() | parsed(), DateTime.t(), DateTime.t()) :: [meeting()]
  def occurrences(ics, from, to) when is_binary(ics), do: occurrences(read(ics), from, to)

  def occurrences(%{events: events}, from, to) do
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
    ics
    |> String.replace(~r/\r?\n[ \t]/, "")
    |> zones()
    |> ICal.from_ics()
    |> case do
      %ICal{events: events} -> events
      _ -> []
    end
  rescue
    _ -> []
  end

  defp meeting?(%{dtstart: %struct{}}) when struct in [DateTime, NaiveDateTime, Date], do: true
  defp meeting?(_none), do: false

  defp zones(ics) do
    fixes =
      for [name] <- Regex.scan(@tzid, ics, capture: :all_but_first),
          not Regex.match?(@iana, name),
          fix = zone(name, ics),
          into: %{},
          do: {name, fix}

    Regex.replace(@tzid, ics, fn _whole, name -> "TZID=" <> Map.get(fixes, name, name) end)
  end

  defp zone(name, ics) do
    cond do
      String.downcase(name) in ["utc", "tzone://microsoft/utc"] -> "Etc/UTC"
      ICal.Deserialize.Timezone.windows_to_olson(name) -> nil
      true -> from_vtimezone(name, ics)
    end
  end

  defp from_vtimezone(name, ics) do
    key = {__MODULE__, :unknown_zone, name}

    if !:persistent_term.get(key, false) do
      :persistent_term.put(key, true)
      Logger.warning("calendar feed: unknown time zone #{inspect(name)}, using the feed's own offset or UTC")
    end

    from_block(name, ics) || from_prefix(name) || "Etc/UTC"
  end

  # the feed's own VTIMEZONE of that name: a US or EU daylight rule at a known standard offset is
  # that region's zone (daylight time right); any other rule is read at its standard offset only
  defp from_block(name, ics) do
    with [_, block] <- Regex.run(~r/BEGIN:VTIMEZONE\r?\nTZID:#{Regex.escape(name)}\r?\n(.*?)END:VTIMEZONE/s, ics),
         [_, sign, h, m] <- Regex.run(~r/BEGIN:STANDARD.*?TZOFFSETTO:([+-])(\d\d)(\d\d)/s, block) do
      minutes = offset(sign, h, m)

      case Regex.run(~r/BEGIN:DAYLIGHT.*?RRULE:([^\r\n]*)/s, block) do
        [_, rule] -> region(rule, minutes) || fixed(minutes)
        _ -> fixed(minutes)
      end
    else
      _ -> nil
    end
  end

  defp region(rule, minutes) do
    cond do
      String.contains?(rule, "-1SU") -> @eu_std[minutes]
      String.contains?(rule, "2SU") -> @us_std[minutes]
      true -> nil
    end
  end

  # "(UTC-05:00) Eastern Time (US & Canada)": the offset in front, fixed
  defp from_prefix(name) do
    case Regex.run(~r/^\(UTC([+-])(\d\d):(\d\d)\)/, name) do
      [_, sign, h, m] -> fixed(offset(sign, h, m))
      _ -> nil
    end
  end

  defp offset(sign, h, m), do: if(sign == "-", do: -1, else: 1) * (String.to_integer(h) * 60 + String.to_integer(m))

  defp fixed(0), do: "Etc/UTC"
  defp fixed(minutes) when rem(minutes, 60) == 0 and minutes in -720..840, do: etc(div(minutes, 60))
  defp fixed(_half_hour), do: "Etc/UTC"

  defp etc(hours) when hours < 0, do: "Etc/GMT+#{-hours}"
  defp etc(hours), do: "Etc/GMT-#{hours}"

  # every start up to `to`, in UTC; a series without a rule is its one start
  defp starts(%{rrule: nil} = e, _to), do: [utc(e.dtstart)]

  defp starts(e, to) do
    skipped = MapSet.new(e.exdates, &utc/1)

    %{e | exdates: []}
    |> ICal.Recurrence.stream()
    |> Stream.map(&utc/1)
    |> Stream.reject(&MapSet.member?(skipped, &1))
    |> Enum.take_while(&(DateTime.compare(&1, to) == :lt))
  end

  defp meeting(e, start) do
    %{
      uid: e.uid,
      title: e.summary || "(no title)",
      start: start,
      stop: DateTime.add(start, length_s(e), :second),
      link: link(e),
      cancelled: cancelled?(e),
      busy: busy(e),
      all_day: match?(%Date{}, e.dtstart)
    }
  end

  defp cancelled?(%{status: :cancelled}), do: true
  defp cancelled?(%{summary: summary}) when is_binary(summary), do: summary =~ ~r/^\s*cancell?ed:/i
  defp cancelled?(_e), do: false

  defp busy(%{custom_properties: %{"X-MICROSOFT-CDO-BUSYSTATUS" => %{value: value}}} = e) when is_binary(value),
    do: ms_busy(String.upcase(value), e)

  defp busy(e), do: by_transparency(e)

  defp ms_busy("FREE", _e), do: :free
  defp ms_busy("TENTATIVE", _e), do: :tentative
  defp ms_busy("OOF", _e), do: :away
  defp ms_busy(_busy, e), do: by_transparency(e)

  defp by_transparency(%{transparency: :transparent}), do: :free
  defp by_transparency(%{status: :tentative}), do: :tentative
  defp by_transparency(_e), do: :busy

  defp length_s(%{dtend: stop, dtstart: start}) when not is_nil(stop), do: DateTime.diff(utc(stop), utc(start))

  defp length_s(%{duration: %ICal.Duration{time: {h, m, s}, days: d, weeks: w}}),
    do: ((w * 7 + d) * 24 + h) * 3600 + m * 60 + s

  defp length_s(%{dtstart: %Date{}}), do: 86_400
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
  defp utc(%Date{} = d), do: DateTime.new!(d, ~T[00:00:00], "Etc/UTC")
end
