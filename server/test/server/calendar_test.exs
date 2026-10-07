defmodule Server.CalendarTest do
  # The configured feeds, fetched in the background and kept: what's coming up is answered from
  # the last good copy of each, tagged with the calendar it came from.
  use ExUnit.Case, async: false

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
end
