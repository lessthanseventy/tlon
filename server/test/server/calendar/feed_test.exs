defmodule Server.Calendar.FeedTest do
  # A feed's meetings in a window, in UTC: recurrences expanded, exceptions skipped, a moved
  # instance at its new time, all-day events left out (nothing to be on time for), and the link
  # to join by.
  use ExUnit.Case, async: true

  alias Server.Calendar.Feed

  defp ics(events), do: "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//t//EN\r\n#{events}END:VCALENDAR\r\n"

  defp vevent(lines), do: "BEGIN:VEVENT\r\n#{Enum.join(lines, "\r\n")}\r\nEND:VEVENT\r\n"

  defp window(from, to), do: {from |> DateTime.from_iso8601() |> elem(1), to |> DateTime.from_iso8601() |> elem(1)}

  test "a one-off meeting in UTC, with its Meet link out of the description" do
    feed =
      ics(
        vevent([
          "UID:a@x",
          "DTSTART:20261008T160000Z",
          "DTEND:20261008T163000Z",
          "SUMMARY:Standup\\, daily",
          "DESCRIPTION:Join: https://meet.google.com/abc-defg-hij\\nor dial in"
        ])
      )

    {from, to} = window("2026-10-08T00:00:00Z", "2026-10-09T00:00:00Z")

    assert [
             %{
               uid: "a@x",
               title: "Standup, daily",
               start: start,
               stop: stop,
               link: "https://meet.google.com/abc-defg-hij"
             }
           ] =
             Feed.occurrences(feed, from, to)

    assert start == ~U[2026-10-08 16:00:00Z] and stop == ~U[2026-10-08 16:30:00Z]
  end

  test "a meeting in a named time zone lands at the right UTC instant" do
    feed =
      ics(
        vevent([
          "UID:tz@x",
          "DTSTART;TZID=America/Denver:20261008T090000",
          "DTEND;TZID=America/Denver:20261008T093000",
          "SUMMARY:Planning",
          "LOCATION:https://us02web.zoom.us/j/123456789"
        ])
      )

    {from, to} = window("2026-10-08T00:00:00Z", "2026-10-09T00:00:00Z")
    # Denver is UTC-6 in October (MDT)
    assert [%{start: ~U[2026-10-08 15:00:00Z], link: "https://us02web.zoom.us/j/123456789"}] =
             Feed.occurrences(feed, from, to)
  end

  test "a weekly meeting repeats, skips its exception, and a moved instance is at its new time" do
    feed =
      ics(
        vevent([
          "UID:w@x",
          "DTSTART:20260907T150000Z",
          "DTEND:20260907T153000Z",
          "RRULE:FREQ=WEEKLY;BYDAY=MO,WE",
          "EXDATE:20261012T150000Z",
          "SUMMARY:Sync"
        ]) <>
          vevent([
            "UID:w@x",
            "RECURRENCE-ID:20261014T150000Z",
            "DTSTART:20261014T180000Z",
            "DTEND:20261014T183000Z",
            "SUMMARY:Sync (moved)"
          ])
      )

    {from, to} = window("2026-10-12T00:00:00Z", "2026-10-20T00:00:00Z")

    assert Enum.map(Feed.occurrences(feed, from, to), &{&1.start, &1.title}) == [
             # Mon 12th is the exception; Wed 14th moved to 18:00; Mon 19th as usual
             {~U[2026-10-14 18:00:00Z], "Sync (moved)"},
             {~U[2026-10-19 15:00:00Z], "Sync"}
           ]
  end

  test "a recurrence that ended stays ended, and all-day events are left out" do
    feed =
      ics(
        vevent([
          "UID:c@x",
          "DTSTART:20261001T120000Z",
          "DTEND:20261001T130000Z",
          "RRULE:FREQ=DAILY;COUNT=3",
          "SUMMARY:Short run"
        ]) <>
          vevent(["UID:d@x", "DTSTART;VALUE=DATE:20261008", "DTEND;VALUE=DATE:20261009", "SUMMARY:Holiday"])
      )

    {from, to} = window("2026-10-02T00:00:00Z", "2026-10-10T00:00:00Z")

    assert Enum.map(Feed.occurrences(feed, from, to), & &1.start) == [
             ~U[2026-10-02 12:00:00Z],
             ~U[2026-10-03 12:00:00Z]
           ]
  end

  test "a meeting given a DURATION instead of an end lasts that long" do
    feed = ics(vevent(["UID:dur@x", "DTSTART:20261008T160000Z", "DURATION:PT1H15M", "SUMMARY:Review"]))
    {from, to} = window("2026-10-08T00:00:00Z", "2026-10-09T00:00:00Z")
    assert [%{stop: ~U[2026-10-08 17:15:00Z]}] = Feed.occurrences(feed, from, to)
  end

  test "a feed that isn't one is no meetings, not a crash" do
    {from, to} = window("2026-10-08T00:00:00Z", "2026-10-09T00:00:00Z")
    assert Feed.occurrences("<html>not a calendar</html>", from, to) == []
  end
end
