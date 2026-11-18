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

  describe "every" do
    test "every/1 reads a repeat, the three old words stay as they are" do
      assert Clock.every("day") == "day"
      assert Clock.every("week") == "week"
      assert Clock.every("month") == "month"
      assert Clock.every("6 week") == "6 week"
      assert Clock.every("3 months") == "3 month"
      assert Clock.every("1 week") == "week"
      assert Clock.every("0 week") == nil
      assert Clock.every("100 week") == nil
      assert Clock.every("2 years") == nil
      assert Clock.every("fortnight") == nil
      assert Clock.every(nil) == nil
      assert Clock.every(6) == nil
    end

    test "say_every/1 says it" do
      assert Clock.say_every("week") == "week"
      assert Clock.say_every("6 week") == "6 weeks"
      assert Clock.say_every("3 month") == "3 months"
    end

    @steps [
      # {from (local), every, anchor day, now (local), next (local)}
      {"2026-11-20 09:00:00", "day", nil, "2026-11-20 09:00:00", "2026-11-21 09:00:00"},
      {"2026-11-20 09:00:00", "week", nil, "2026-11-20 09:00:00", "2026-11-27 09:00:00"},
      {"2026-11-20 09:00:00", "6 week", nil, "2026-11-20 09:00:00", "2027-01-01 09:00:00"},
      {"2026-11-20 09:00:00", "2 week", nil, "2026-11-20 09:00:00", "2026-12-04 09:00:00"},
      {"2026-11-20 09:00:00", "3 day", nil, "2026-11-20 09:00:00", "2026-11-23 09:00:00"},
      {"2026-11-20 09:00:00", "3 month", nil, "2026-11-20 09:00:00", "2027-02-20 09:00:00"},
      {"2026-11-20 09:00:00", "month", nil, "2026-11-20 09:00:00", "2026-12-20 09:00:00"},
      {"2027-01-31 09:00:00", "month", 31, "2027-01-31 09:00:00", "2027-02-28 09:00:00"},
      {"2027-02-28 09:00:00", "month", 31, "2027-02-28 09:00:00", "2027-03-31 09:00:00"},
      {"2027-03-31 09:00:00", "month", 31, "2027-03-31 09:00:00", "2027-04-30 09:00:00"},
      {"2027-04-30 09:00:00", "month", 31, "2027-04-30 09:00:00", "2027-05-31 09:00:00"},
      {"2028-01-31 09:00:00", "month", 31, "2028-01-31 09:00:00", "2028-02-29 09:00:00"},
      {"2027-01-31 09:00:00", "2 month", 31, "2027-01-31 09:00:00", "2027-03-31 09:00:00"},
      {"2027-02-28 09:00:00", "month", nil, "2027-02-28 09:00:00", "2027-03-28 09:00:00"},
      {"2026-11-20 09:00:00", "day", nil, "2026-11-25 12:00:00", "2026-11-26 09:00:00"}
    ]

    for {from, every, anchor, now, expected} <- @steps do
      test "#{from} every #{every} (anchor #{anchor || "none"}) after #{now} is #{expected}" do
        local = fn text -> text |> NaiveDateTime.from_iso8601!() |> Clock.utc() end

        assert Clock.next(local.(unquote(from)), unquote(every), local.(unquote(now)), unquote(anchor)) ==
                 local.(unquote(expected))
      end
    end

    test "latest/4 is the newest occurrence that has come" do
      from = Clock.utc(~N[2026-11-20 09:00:00])
      assert Clock.latest(from, "3 day", Clock.utc(~N[2026-11-30 00:00:00]), nil) == Clock.utc(~N[2026-11-29 09:00:00])
      assert Clock.latest(from, "3 day", Clock.utc(~N[2026-11-21 00:00:00]), nil) == from
    end
  end

  test "resume/2 trusts a kept slot only under the setting it was kept for" do
    assert Clock.resume({~D[2026-11-20], "17:30"}, "17:30") == ~D[2026-11-20]
    assert Clock.resume({~D[2026-11-20], "17:30"}, "22:30") == :boot
    assert Clock.resume(nil, "17:30") == :boot
  end

  test "slot/3 is the date of the newest slot not after now" do
    assert Clock.slot(at("2026-11-20", "17:35:00"), "17:30") == ~D[2026-11-20]
    assert Clock.slot(at("2026-11-20", "17:20:00"), "17:30") == ~D[2026-11-19]
    assert Clock.slot(at("2026-11-20", "17:35:00"), "17:30", "sun") == ~D[2026-11-15]
    assert Clock.slot(at("2026-11-20", "17:35:00"), "") == nil
  end
end
