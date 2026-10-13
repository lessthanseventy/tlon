defmodule Server.UsageTest do
  # The Claude plan's limits as the last session to report them saw them: the office's meter.
  use ExUnit.Case, async: false

  alias Server.Usage

  setup do
    Usage.clear()
    :ok
  end

  test "nothing reported yet is nil, never a made-up zero" do
    assert Usage.claude() == nil
  end

  test "a report is kept with when it came; the newest wins, a window it leaves out is kept from before" do
    :ok =
      Usage.report(%{
        "five_hour" => %{"percent" => 34, "resets_at" => "2026-10-13T19:00:00Z"},
        "seven_day" => %{"percent" => 44, "resets_at" => nil}
      })

    :ok = Usage.report(%{"five_hour" => %{"percent" => 35.5, "resets_at" => "2026-10-13T19:00:00Z"}})

    assert %{
             five_hour: %{percent: 35.5, resets_at: "2026-10-13T19:00:00Z"},
             seven_day: %{percent: 44, resets_at: nil},
             at: %DateTime{}
           } =
             Usage.claude()
  end

  test "a report that isn't the plan's windows is refused and changes nothing" do
    assert {:error, _} = Usage.report(%{"five_hour" => %{"percent" => "lots"}})
    assert {:error, _} = Usage.report(%{})
    assert Usage.claude() == nil
  end
end
