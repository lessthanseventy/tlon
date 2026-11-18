defmodule Server.Home.ClockTest do
  use ExUnit.Case, async: true

  alias Server.Home.Clock

  defp expected(:wait), do: :wait
  defp expected({:say, day}), do: {:say, Date.from_iso8601!(day)}

  defp at(date, time), do: Clock.utc(NaiveDateTime.new!(Date.from_iso8601!(date), Time.from_iso8601!(time)))

  describe "due/4: the slot last said, the slot's time, now: say it (and record that slot) or wait" do
    @cases [
      # {last said, list time, weekday, now, answer}
      {"2026-11-19", "17:30", nil, "2026-11-20 17:29:00", :wait},
      {"2026-11-19", "17:30", nil, "2026-11-20 17:35:00", {:say, "2026-11-20"}},
      {"2026-11-20", "17:30", nil, "2026-11-21 08:00:00", :wait},
      {"2026-11-20", "17:30", nil, "2026-11-21 17:35:00", {:say, "2026-11-21"}},
      {"2026-11-21", "17:30", nil, "2026-11-22 17:35:00", {:say, "2026-11-22"}},
      {"2026-11-19", "22:30", nil, "2026-11-20 22:35:00", :wait},
      {"2026-11-19", "22:30", nil, "2026-11-21 08:05:00", {:say, "2026-11-20"}},
      {"2026-11-20", "22:30", nil, "2026-11-21 22:35:00", :wait},
      {"2026-11-20", "22:30", nil, "2026-11-22 08:05:00", {:say, "2026-11-21"}},
      {"2026-11-21", "22:30", nil, "2026-11-23 08:05:00", {:say, "2026-11-22"}},
      {"2026-11-22", "22:30", nil, "2026-11-24 08:05:00", {:say, "2026-11-23"}},
      {"2026-11-20", "22:30", nil, "2026-11-21 09:05:00", :wait},
      {"2026-11-20", "03:00", nil, "2026-11-21 03:05:00", :wait},
      {"2026-11-20", "03:00", nil, "2026-11-21 08:05:00", {:say, "2026-11-21"}},
      {"2026-11-21", "03:00", nil, "2026-11-21 09:00:00", :wait},
      {"2026-11-21", "03:00", nil, "2026-11-22 08:05:00", {:say, "2026-11-22"}},
      {"2026-11-19", "17:30", nil, "2026-11-20 23:00:00", :wait},
      {"2026-11-19", "17:30", nil, "2026-11-21 08:00:00", {:say, "2026-11-20"}},
      {"2026-11-20", "17:30", nil, "2026-11-21 17:30:00", {:say, "2026-11-21"}},
      {"2026-11-19", "", nil, "2026-11-20 17:35:00", :wait},
      {"2026-11-08", "17:30", "sun", "2026-11-15 17:29:00", :wait},
      {"2026-11-08", "17:30", "sun", "2026-11-15 17:35:00", {:say, "2026-11-15"}},
      {"2026-11-15", "17:30", "sun", "2026-11-16 08:00:00", :wait},
      {"2026-11-08", "17:30", "sun", "2026-11-16 08:00:00", {:say, "2026-11-15"}},
      {"2026-11-08", "17:30", "sun", "2026-11-17 10:00:00", {:say, "2026-11-15"}},
      {"2026-11-08", "17:30", "sun", "2026-11-15 22:30:00", :wait},
      {"2026-11-08", "17:30", "", "2026-11-15 17:35:00", :wait}
    ]

    for {last, time, on, now, answer} <- @cases do
      test "last #{last}, #{time} #{on || "daily"}, now #{now}" do
        [date, clock] = String.split(unquote(now), " ")
        got = Clock.due(Date.from_iso8601!(unquote(last)), at(date, clock), unquote(time), unquote(on))

        assert got == expected(unquote(Macro.escape(answer)))
      end
    end
  end

  test "slot/3 is the date of the newest slot not after now" do
    assert Clock.slot(at("2026-11-20", "17:35:00"), "17:30") == ~D[2026-11-20]
    assert Clock.slot(at("2026-11-20", "17:20:00"), "17:30") == ~D[2026-11-19]
    assert Clock.slot(at("2026-11-20", "17:35:00"), "17:30", "sun") == ~D[2026-11-15]
    assert Clock.slot(at("2026-11-20", "17:35:00"), "") == nil
  end
end
