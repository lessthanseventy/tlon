defmodule Server.Presence.Engine.OllamaWindowTest do
  use ExUnit.Case, async: true

  alias Server.Presence.Engine.OllamaWindow

  @now ~U[2026-10-10 15:40:00Z]

  defp legacy(session, weekly) do
    Jason.encode!(%{
      "included" => %{
        "session" => %{"remaining_percent" => session, "resets_at" => "2026-10-10T16:00:00Z"},
        "weekly" => %{"remaining_percent" => weekly, "resets_at" => "2026-10-12T00:00:00Z"}
      },
      "purchased" => %{"balance_usd" => 0}
    })
  end

  test "a spent session window holds until it resets" do
    assert OllamaWindow.spent_until(legacy(0, 26.1), @now) == ~U[2026-10-10 16:00:00Z]
  end

  test "a spent week holds until the week resets, even with session room" do
    assert OllamaWindow.spent_until(legacy(40, 0), @now) == ~U[2026-10-12 00:00:00Z]
  end

  test "room in both windows: nothing held" do
    assert OllamaWindow.spent_until(legacy(81.5, 26.1), @now) == nil
  end

  test "a reset already past holds nothing" do
    assert OllamaWindow.spent_until(legacy(0, 26.1), ~U[2026-10-10 16:00:01Z]) == nil
  end

  test "purchased credits keep the plan running past its included windows" do
    body = 0 |> legacy(0) |> Jason.decode!() |> put_in(["purchased", "balance_usd"], 4.5) |> Jason.encode!()
    assert OllamaWindow.spent_until(body, @now) == nil
  end

  test "a credits plan with its allowance spent holds until the period ends" do
    body =
      Jason.encode!(%{
        "included" => %{"allowance_usd" => 20, "balance_usd" => 0, "period" => %{"until" => "2026-11-01T00:00:00Z"}},
        "purchased" => %{"balance_usd" => 0}
      })

    assert OllamaWindow.spent_until(body, @now) == ~U[2026-11-01 00:00:00Z]
  end

  test "a body it can't read holds nothing: an unknown meter never stops the office" do
    assert OllamaWindow.spent_until("<html>", @now) == nil
    assert OllamaWindow.spent_until(Jason.encode!(%{"included" => %{}}), @now) == nil
  end
end
