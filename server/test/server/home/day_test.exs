defmodule Server.Home.DayTest do
  # The home's meetings for today and tomorrow, cleaned. Times are built from local wall-clock
  # readings so the test holds in any machine zone.
  use ExUnit.Case, async: true

  alias Server.Home.Clock
  alias Server.Home.Day

  defp at(date, time), do: Clock.utc(NaiveDateTime.new!(date, Time.from_iso8601!(time <> ":00")))

  defp m(title, date, from, to, opts \\ []) do
    Map.merge(
      %{
        title: title,
        start: at(date, from),
        stop: at(date, to),
        cancelled: false,
        busy: :busy,
        all_day: false
      },
      Map.new(opts)
    )
  end

  @today ~D[2026-11-19]
  @tomorrow ~D[2026-11-20]
  defp now, do: at(@today, "10:00")

  test "today's remaining and tomorrow's, soonest first, with the day named" do
    found = [
      m("Review", @tomorrow, "09:00", "10:00"),
      m("Late", @today, "15:00", "15:30"),
      m("Over", @today, "08:00", "09:00"),
      m("Running", @today, "09:30", "10:30"),
      m("Next week", ~D[2026-11-25], "09:00", "10:00")
    ]

    assert [
             %{title: "Running", day: "today"},
             %{title: "Late", day: "today"},
             %{title: "Review", day: "tomorrow"}
           ] = Day.build(found, now())
  end

  test "each is title, UTC starts_at and ends_at, tentative" do
    found = [m("Sync", @today, "11:00", "11:30", busy: :tentative)]

    assert [%{title: "Sync", starts_at: s, ends_at: e, tentative: true, all_day: false}] = Day.build(found, now())
    assert s == at(@today, "11:00") and e == at(@today, "11:30")
    assert [%{tentative: false}] = Day.build([m("Sync", @today, "11:00", "11:30")], now())
  end

  test "cancelled meetings and free all-day events are dropped" do
    found = [
      m("Gone", @today, "11:00", "11:30", cancelled: true),
      m("Holiday", @today, "00:00", "00:00",
        all_day: true,
        busy: :free,
        start: ~U[2026-11-19 00:00:00Z],
        stop: ~U[2026-11-20 00:00:00Z]
      ),
      m("Kept", @today, "12:00", "12:30")
    ]

    assert [%{title: "Kept"}] = Day.build(found, now())
  end

  test "doubles by normalised title and start are one, under the stripped title" do
    found = [
      m("Synced invitation: Standup @ Thu Nov 19, 2026 (me@x.org)", @today, "11:00", "11:30"),
      m("[EXT] Standup", @today, "11:00", "11:30"),
      m("Standup", @tomorrow, "11:00", "11:30")
    ]

    assert [%{title: "Standup", day: "today"}, %{title: "Standup", day: "tomorrow"}] = Day.build(found, now())
  end

  test "a busy multi-day all-day event is on each date it covers, from that local midnight" do
    found = [
      m("Offsite", @today, "00:00", "00:00",
        all_day: true,
        start: ~U[2026-11-19 00:00:00Z],
        stop: ~U[2026-11-21 00:00:00Z]
      )
    ]

    assert [%{day: "today", all_day: true, starts_at: s1}, %{day: "tomorrow", all_day: true, starts_at: s2}] =
             Day.build(found, now())

    assert s1 == at(@today, "00:00") and s2 == at(@tomorrow, "00:00")
  end

  test "no calendar running is no meetings" do
    assert Day.meetings(now(), :no_such_calendar) == []
  end
end
