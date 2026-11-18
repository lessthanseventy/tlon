defmodule Server.Office.WeatherTest do
  # The weather outside, for the office's windows: wttr.in's current conditions, read into the few
  # kinds the room can draw, cached, fetched in the background so the snapshot never waits on it.
  use ExUnit.Case, async: false

  alias Server.Office.Weather

  @rainy ~s({"current_condition": [{"weatherCode": "296", "temp_C": "11", "weatherDesc": [{"value": "Light rain"}]}]})

  test "a report reads as one of the kinds the room draws, with the temperature" do
    assert Weather.parse(@rainy) == %{kind: "rain", temp_c: 11, desc: "Light rain"}
    assert Weather.kind(113) == "clear" and Weather.kind(116) == "partly" and Weather.kind(122) == "cloudy"
    assert Weather.kind(248) == "fog" and Weather.kind(338) == "snow" and Weather.kind(389) == "storm"
    assert Weather.parse("not json") == nil
  end

  test "the first read asks in the background; a later read has it; a fresh one is not asked again" do
    me = self()

    start_supervised!(
      {Weather,
       fetch: fn ->
         send(me, :fetched)
         {:ok, @rainy}
       end}
    )

    assert Weather.now() == nil
    assert_receive :fetched

    assert Enum.find_value(1..20, fn _ -> Process.sleep(20) && Weather.now() end) == %{
             kind: "rain",
             temp_c: 11,
             desc: "Light rain"
           }

    refute_receive :fetched, 100
  end

  defp hour(time, code, rain, snow),
    do: %{"time" => time, "weatherCode" => code, "chanceofrain" => rain, "chanceofsnow" => snow}

  defp day(date, hi, lo, hourly), do: %{"date" => date, "maxtempC" => hi, "mintempC" => lo, "hourly" => hourly}

  defp body(days) do
    JSON.encode!(%{
      "current_condition" => [
        %{"weatherCode" => "296", "temp_C" => "11", "weatherDesc" => [%{"value" => "Light rain"}]}
      ],
      "weather" => days
    })
  end

  test "three days read as high, low, the worst kind of the daytime and its chance of wet" do
    days = [
      day("2026-11-18", "12", "-1", [
        hour("0", "338", "0", "99"),
        hour("900", "116", "10", "60"),
        hour("1500", "113", "0", "0")
      ]),
      day("2026-11-19", "8", "2", [hour("1200", "296", "70", "0"), hour("1500", "389", "20", "5")]),
      day("2026-11-20", "15", "6", [hour("900", "113", "0", "0"), hour("2100", "338", "0", "90")])
    ]

    assert Weather.parse_forecast(body(days)) == [
             %{date: "2026-11-18", high_c: 12, low_c: -1, kind: "partly", wet: 60},
             %{date: "2026-11-19", high_c: 8, low_c: 2, kind: "storm", wet: 70},
             %{date: "2026-11-20", high_c: 15, low_c: 6, kind: "clear", wet: 0}
           ]
  end

  test "snow outranks rain, and a day that does not read is left out" do
    good = day("2026-11-18", "3", "0", [hour("900", "296", "40", "0"), hour("1200", "338", "0", "30")])
    bad = day("2026-11-19", "warm", "0", [hour("900", "113", "0", "0")])
    no_kind = day("2026-11-20", "3", "0", [hour("900", "999", "0", "0")])
    no_day_hours = day("2026-11-21", "3", "0", [hour("0", "113", "0", "0")])

    assert [%{date: "2026-11-18", kind: "snow", wet: 40}] =
             Weather.parse_forecast(body([good, bad, no_kind, no_day_hours]))
  end

  test "a body without the days has no forecast but still has the conditions" do
    assert Weather.parse_forecast(@rainy) == []
    assert Weather.parse_forecast("not json") == []
    assert Weather.parse(@rainy) == %{kind: "rain", temp_c: 11, desc: "Light rain"}
  end

  test "the forecast comes with the first report and now/0 is unchanged" do
    full = body([day("2026-11-18", "12", "-1", [hour("900", "296", "40", "0")])])
    start_supervised!({Weather, fetch: fn -> {:ok, full} end})

    assert Weather.forecast() == []
    forecast = Enum.find_value(1..20, fn _ -> Process.sleep(20) && Weather.forecast() != [] && Weather.forecast() end)
    assert [%{date: "2026-11-18", high_c: 12, low_c: -1, kind: "rain", wet: 40}] = forecast
    assert Weather.now() == %{kind: "rain", temp_c: 11, desc: "Light rain"}
  end

  test "with the weather off there is no forecast" do
    assert Weather.forecast() == []
  end

  test "a fetch that fails leaves the last report standing" do
    start_supervised!({Weather, fetch: fn -> {:error, :down} end})
    assert Weather.now() == nil
    Process.sleep(50)
    assert Weather.now() == nil
  end

  test "with the weather off there is none" do
    assert Weather.now() == nil
  end
end
