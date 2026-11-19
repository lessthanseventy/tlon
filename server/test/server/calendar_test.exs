defmodule Server.CalendarTest do
  # The configured feeds, fetched in the background and kept: what's coming up is answered from
  # the last good copy of each, tagged with the calendar it came from.
  use ExUnit.Case, async: true

  alias Server.Calendar

  @ics """
  BEGIN:VCALENDAR\r
  VERSION:2.0\r
  BEGIN:VEVENT\r
  UID:m@x\r
  DTSTART:20261008T160000Z\r
  DTEND:20261008T163000Z\r
  SUMMARY:Standup\r
  END:VEVENT\r
  END:VCALENDAR\r
  """

  defp start(fetch, sources) do
    start_supervised!({Calendar, name: :cal_test, fetch: fetch, sources: fn -> sources end, every_ms: :manual})
  end

  test "a source's meetings come back tagged with its name, from its last good fetch" do
    {:ok, agent} = Agent.start_link(fn -> {:ok, @ics} end)
    pid = start(fn _source -> Agent.get(agent, & &1) end, [%{"name" => "work", "ics" => "https://example.test/a.ics"}])
    :ok = Calendar.refresh(pid)

    window = {~U[2026-10-08 00:00:00Z], ~U[2026-10-09 00:00:00Z]}
    assert [%{title: "Standup", calendar: "work"}] = Calendar.upcoming(pid, window)

    # a failed fetch leaves the last copy standing
    Agent.update(agent, fn _ -> {:error, :timeout} end)
    :ok = Calendar.refresh(pid)
    assert [%{title: "Standup"}] = Calendar.upcoming(pid, window)
  end

  test "no calendars configured is no meetings" do
    pid = start(fn _ -> flunk("nothing to fetch") end, [])
    :ok = Calendar.refresh(pid)
    assert Calendar.upcoming(pid, {~U[2026-10-08 00:00:00Z], ~U[2026-10-09 00:00:00Z]}) == []
  end

  test "a source's url comes from the machine's secret when it names one" do
    dir = Path.join(System.tmp_dir!(), "cal-secret-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "agenix"))
    File.write!(Path.join([dir, "agenix", "calendar-work"]), "https://example.test/private.ics\n")
    on_exit(fn -> File.rm_rf!(dir) end)

    assert Calendar.url(%{"ics_secret" => "calendar-work"}, dir) == {:ok, "https://example.test/private.ics"}
    assert Calendar.url(%{"ics" => "https://example.test/a.ics"}, dir) == {:ok, "https://example.test/a.ics"}
    assert {:error, _} = Calendar.url(%{"ics_secret" => "nope"}, dir)
  end

  test "a day's birthdays and anniversaries across the sources, from their last good copy" do
    ics =
      "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:b@x\r\nDTSTART;VALUE=DATE:20261008\r\nDTEND;VALUE=DATE:20261009\r\nSUMMARY:Ana's birthday\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

    pid = start(fn _ -> {:ok, ics} end, [%{"name" => "family", "ics" => "https://example.test/b.ics"}])
    :ok = Calendar.refresh(pid)

    assert Calendar.celebrations(pid, ~D[2026-10-08]) == [%{title: "Ana's birthday", kind: "birthday"}]
    assert Calendar.celebrations(pid, ~D[2026-10-09]) == []
    assert Calendar.celebrations(:no_such_calendar, ~D[2026-10-08]) == []
  end

  test "a day's celebrations are computed once per fetch, not per read" do
    me = self()
    source = [%{"name" => "family", "ics" => "https://example.test/b.ics"}]

    {:ok, pid} =
      Calendar.start_link(
        name: :cal_cache_test,
        every_ms: :manual,
        fetch: fn _ -> {:ok, "ics"} end,
        sources: fn -> source end,
        celebrations: fn "ics", day ->
          send(me, {:parsed, day})
          []
        end
      )

    :ok = Calendar.refresh(pid)
    Calendar.celebrations(pid, ~D[2026-10-08])
    Calendar.celebrations(pid, ~D[2026-10-08])
    assert_received {:parsed, ~D[2026-10-08]}
    refute_received {:parsed, _}

    :ok = Calendar.refresh(pid)
    Calendar.celebrations(pid, ~D[2026-10-08])
    assert_received {:parsed, ~D[2026-10-08]}
  end

  describe "clean/1 and alarmable/1" do
    defp m(title, opts \\ []) do
      Map.merge(
        %{title: title, start: ~U[2026-10-08 16:00:00Z], cancelled: false, busy: :busy, all_day: false},
        Map.new(opts)
      )
    end

    test "cancelled meetings are dropped" do
      assert [m("A", cancelled: true), m("B")] |> Calendar.clean() |> Enum.map(& &1.title) == ["B"]
      assert Calendar.alarmable([m("A", cancelled: true)]) == []
    end

    test "all-day events shown as free are dropped; a busy all-day stays in the day but never alarms" do
      all = [m("Holiday", all_day: true, busy: :free), m("Offsite", all_day: true), m("Sync")]
      assert all |> Calendar.clean() |> Enum.map(& &1.title) == ["Offsite", "Sync"]
      assert all |> Calendar.alarmable() |> Enum.map(& &1.title) == ["Sync"]
    end

    test "a meeting shown as free does not alarm, a tentative one does" do
      all = [m("Free", busy: :free), m("Maybe", busy: :tentative)]
      assert all |> Calendar.clean() |> Enum.map(& &1.title) == ["Free", "Maybe"]
      assert all |> Calendar.alarmable() |> Enum.map(& &1.title) == ["Maybe"]
    end

    test "doubles by stripped title and start are one, shown with the stripped title" do
      all = [
        m("Synced invitation: [EXT] Standup @ Thu Oct 8, 2026 (a@b.com)"),
        m("Standup"),
        m("Standup", start: ~U[2026-10-08 17:00:00Z])
      ]

      assert Enum.map(Calendar.clean(all), &{&1.title, &1.start}) ==
               [{"Standup", ~U[2026-10-08 16:00:00Z]}, {"Standup", ~U[2026-10-08 17:00:00Z]}]
    end

    test "title/1 strips the prefixes and the recurrence blurb only" do
      assert Calendar.title("[EXT] Design review") == "Design review"
      assert Calendar.title("Synced invitation: 1:1 @ Weekly (me@x.org)") == "1:1"
      assert Calendar.title("Lunch @ the park") == "Lunch @ the park"
    end
  end
end
