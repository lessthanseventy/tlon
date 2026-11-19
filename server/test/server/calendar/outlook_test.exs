defmodule Server.Calendar.OutlookTest do
  # An Outlook on the web published feed, written by hand in the shape it publishes: Windows zone
  # names in TZID, VTIMEZONE blocks, busy status, cancelled meetings and all-day events.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Server.Calendar.Feed

  defp vevent(lines), do: "BEGIN:VEVENT\r\n#{Enum.join(lines, "\r\n")}\r\nEND:VEVENT\r\n"

  defp vtimezone(id, std, dst) do
    """
    BEGIN:VTIMEZONE\r
    TZID:#{id}\r
    BEGIN:STANDARD\r
    DTSTART:16010101T020000\r
    TZOFFSETFROM:#{dst}\r
    TZOFFSETTO:#{std}\r
    RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=1SU;BYMONTH=11\r
    END:STANDARD\r
    BEGIN:DAYLIGHT\r
    DTSTART:16010101T020000\r
    TZOFFSETFROM:#{std}\r
    TZOFFSETTO:#{dst}\r
    RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=2SU;BYMONTH=3\r
    END:DAYLIGHT\r
    END:VTIMEZONE\r
    """
  end

  defp feed(events, zones \\ "") do
    "BEGIN:VCALENDAR\r\nPRODID:Microsoft Exchange Server 2010\r\nVERSION:2.0\r\nMETHOD:PUBLISH\r\n" <>
      "X-WR-CALNAME:Calendar\r\n#{zones}#{events}END:VCALENDAR\r\n"
  end

  defp all(ics), do: Feed.occurrences(ics, ~U[2026-01-01 00:00:00Z], ~U[2027-01-01 00:00:00Z])

  defp meeting(tzid, local) do
    vevent([
      "UID:#{tzid}#{local}",
      "DTSTART;TZID=#{tzid}:#{local}",
      "DTEND;TZID=#{tzid}:#{local}",
      "SUMMARY:M"
    ])
  end

  test "Windows zone names land at the right UTC instant" do
    cases = [
      {"Eastern Standard Time", "20261119T090000", ~U[2026-11-19 14:00:00Z]},
      {"Mountain Standard Time", "20261119T090000", ~U[2026-11-19 16:00:00Z]},
      {"UTC", "20261119T090000", ~U[2026-11-19 09:00:00Z]},
      {"Pacific Standard Time", "20261119T090000", ~U[2026-11-19 17:00:00Z]},
      {"Central Standard Time", "20261119T090000", ~U[2026-11-19 15:00:00Z]},
      {"GMT Standard Time", "20260617T090000", ~U[2026-06-17 08:00:00Z]},
      {"W. Europe Standard Time", "20260617T090000", ~U[2026-06-17 07:00:00Z]},
      {"India Standard Time", "20261119T090000", ~U[2026-11-19 03:30:00Z]},
      {"Eastern Standard Time", "20260617T090000", ~U[2026-06-17 13:00:00Z]}
    ]

    for {tzid, local, utc} <- cases do
      assert [%{start: ^utc}] = all(feed(meeting(tzid, local))), "#{tzid} #{local}"
    end
  end

  test "a quoted TZID is read without its quotes" do
    ics = feed(meeting(~s("Eastern Standard Time"), "20261119T090000"))
    assert [%{start: ~U[2026-11-19 14:00:00Z]}] = all(ics)
    assert [%{start: ~U[2026-11-19 09:00:00Z]}] = all(feed(meeting(~s("UTC"), "20261119T090000")))
  end

  describe "a display-name TZID with a colon, as Outlook can write it" do
    @display "(UTC-05:00) Eastern Time (US & Canada)"

    defp display_meeting(local) do
      vevent([
        "UID:d#{local}",
        ~s[DTSTART;TZID="#{@display}":#{local}],
        ~s[DTEND;TZID="#{@display}":#{local}],
        "SUMMARY:M"
      ])
    end

    test "the feed's own VTIMEZONE with a US rule gives Eastern time, daylight time right" do
      zones = vtimezone(@display, "-0500", "-0400")
      assert [%{start: ~U[2026-11-19 14:00:00Z]}] = all(feed(display_meeting("20261119T090000"), zones))
      assert [%{start: ~U[2026-06-17 13:00:00Z]}] = all(feed(display_meeting("20260617T090000"), zones))
    end

    test "with no VTIMEZONE the (UTC-05:00) prefix is a fixed offset, so summer is an hour off" do
      assert [%{start: ~U[2026-11-19 14:00:00Z]}] = all(feed(display_meeting("20261119T090000")))
      assert [%{start: ~U[2026-06-17 14:00:00Z]}] = all(feed(display_meeting("20260617T090000")))
    end

    test "a half-hour prefix with no VTIMEZONE is UTC" do
      ics = feed(vevent(["UID:h", ~s[DTSTART;TZID="(UTC+05:30) Chennai":20261119T090000], "SUMMARY:M"]))
      assert [%{start: ~U[2026-11-19 09:00:00Z]}] = all(ics)
    end
  end

  test "an all-day event with no end lasts one day" do
    ics = feed(vevent(["UID:a", "DTSTART;VALUE=DATE:20261119", "SUMMARY:Out"]))
    assert [%{all_day: true, stop: ~U[2026-11-20 00:00:00Z]}] = all(ics)
  end

  test "an unknown zone name takes its offset from the feed's VTIMEZONE" do
    zones = vtimezone("Fictional Standard Time", "-0300", "-0300")

    assert [%{start: ~U[2026-11-19 12:00:00Z]}] =
             all(feed(meeting("Fictional Standard Time", "20261119T090000"), zones))
  end

  test "an unknown zone name without a VTIMEZONE is UTC, and logged once" do
    ics = feed(meeting("Nowhere Standard Time", "20261119T090000"))

    log =
      capture_log(fn ->
        assert [%{start: ~U[2026-11-19 09:00:00Z]}] = all(ics)
        assert [%{start: ~U[2026-11-19 09:00:00Z]}] = all(ics)
      end)

    assert length(String.split(log, "Nowhere Standard Time")) == 2
  end

  test "a series with an EXDATE and a moved instance, in a Windows zone" do
    z = "Eastern Standard Time"

    ics =
      feed(
        vevent([
          "UID:s",
          "DTSTART;TZID=#{z}:20261116T090000",
          "DTEND;TZID=#{z}:20261116T093000",
          "RRULE:FREQ=DAILY;COUNT=5",
          "EXDATE;TZID=#{z}:20261117T090000",
          "SUMMARY:Standup"
        ]) <>
          vevent([
            "UID:s",
            "RECURRENCE-ID;TZID=#{z}:20261118T090000",
            "DTSTART;TZID=#{z}:20261118T110000",
            "DTEND;TZID=#{z}:20261118T113000",
            "SUMMARY:Standup (moved)"
          ])
      )

    assert Enum.map(all(ics), &{&1.start, &1.title}) == [
             {~U[2026-11-16 14:00:00Z], "Standup"},
             {~U[2026-11-18 16:00:00Z], "Standup (moved)"},
             {~U[2026-11-19 14:00:00Z], "Standup"},
             {~U[2026-11-20 14:00:00Z], "Standup"}
           ]
  end

  test "cancelled by status or by a Canceled: / Cancelled: summary" do
    ics =
      feed(
        vevent(["UID:a", "DTSTART:20261119T150000Z", "DTEND:20261119T153000Z", "SUMMARY:Live", "STATUS:CONFIRMED"]) <>
          vevent(["UID:b", "DTSTART:20261119T160000Z", "DTEND:20261119T163000Z", "SUMMARY:Gone", "STATUS:CANCELLED"]) <>
          vevent(["UID:c", "DTSTART:20261119T170000Z", "DTEND:20261119T173000Z", "SUMMARY:Canceled: Sync"]) <>
          vevent(["UID:d", "DTSTART:20261119T180000Z", "DTEND:20261119T183000Z", "SUMMARY:Cancelled: Review"])
      )

    assert Enum.map(all(ics), &{&1.title, &1.cancelled}) ==
             [{"Live", false}, {"Gone", true}, {"Canceled: Sync", true}, {"Cancelled: Review", true}]
  end

  test "busy: the Microsoft status, else TRANSP, else the event's status" do
    base = fn uid, extra ->
      vevent(["UID:#{uid}", "DTSTART:20261119T150000Z", "DTEND:20261119T153000Z", "SUMMARY:#{uid}" | extra])
    end

    ics =
      feed(
        base.("free", ["TRANSP:OPAQUE", "X-MICROSOFT-CDO-BUSYSTATUS:FREE"]) <>
          base.("tent", ["X-MICROSOFT-CDO-BUSYSTATUS:TENTATIVE"]) <>
          base.("busy", ["X-MICROSOFT-CDO-BUSYSTATUS:BUSY", "TRANSP:OPAQUE"]) <>
          base.("oof", ["X-MICROSOFT-CDO-BUSYSTATUS:OOF"]) <>
          base.("transp", ["TRANSP:TRANSPARENT"]) <>
          base.("status", ["STATUS:TENTATIVE"]) <>
          base.("plain", [])
      )

    assert Map.new(all(ics), &{&1.title, &1.busy}) == %{
             "free" => :free,
             "tent" => :tentative,
             "busy" => :busy,
             "oof" => :away,
             "transp" => :free,
             "status" => :tentative,
             "plain" => :busy
           }
  end

  test "all-day events, a multi-day one included, are marked and run midnight to midnight UTC" do
    ics =
      feed(
        vevent([
          "UID:h",
          "DTSTART;VALUE=DATE:20261119",
          "DTEND;VALUE=DATE:20261120",
          "SUMMARY:Holiday",
          "X-MICROSOFT-CDO-BUSYSTATUS:FREE",
          "X-MICROSOFT-CDO-ALLDAYEVENT:TRUE"
        ]) <>
          vevent([
            "UID:o",
            "DTSTART;VALUE=DATE:20261120",
            "DTEND;VALUE=DATE:20261123",
            "SUMMARY:Offsite",
            "X-MICROSOFT-CDO-BUSYSTATUS:BUSY"
          ]) <>
          vevent(["UID:t", "DTSTART:20261119T150000Z", "DTEND:20261119T153000Z", "SUMMARY:Timed"])
      )

    found = Map.new(all(ics), &{&1.title, &1})

    assert %{all_day: true, busy: :free, start: ~U[2026-11-19 00:00:00Z], stop: ~U[2026-11-20 00:00:00Z]} =
             found["Holiday"]

    assert %{all_day: true, busy: :busy, start: ~U[2026-11-20 00:00:00Z], stop: ~U[2026-11-23 00:00:00Z]} =
             found["Offsite"]

    assert %{all_day: false} = found["Timed"]
  end
end
