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
