defmodule Server.Recall.StrengthTest do
  # The forgetting engine's heart (design: docs/plans/2026-08-19-funes-forgetting-design.md):
  # a fact's strength is the decayed sum of signed touches. Pure — no DB.
  use ExUnit.Case, async: true

  alias Server.Recall.Strength

  @now ~U[2026-08-19 12:00:00Z]

  defp ago(seconds), do: DateTime.shift(@now, second: -seconds)

  describe "of/3 — decayed sum of signed touches" do
    test "no touches is zero strength" do
      assert Strength.of([], @now) == 0.0
    end

    test "a fresh touch contributes ~its full weight" do
      assert_in_delta Strength.of([%{weight: 2.0, at: @now}], @now), 2.0, 0.001
    end

    test "an older touch is worth less than a fresher one of equal weight" do
      fresh = Strength.of([%{weight: 1.0, at: ago(0)}], @now)
      old = Strength.of([%{weight: 1.0, at: ago(30 * 24 * 3600)}], @now)
      assert old < fresh
    end

    test "one half-life halves a touch's contribution" do
      hl = 10 * 24 * 3600
      assert_in_delta Strength.of([%{weight: 4.0, at: ago(hl)}], @now, half_life_s: hl), 2.0, 0.001
    end

    test "negative touches subtract" do
      s = Strength.of([%{weight: 3.0, at: @now}, %{weight: -2.0, at: @now}], @now)
      assert_in_delta s, 1.0, 0.001
    end
  end

  describe "touches_for/2 — funes history → signed touches" do
    test "birth plus a passing recheck is positive" do
      touches =
        Strength.touches_for(
          %{created_at: ago(3600), touches: [%{kind: "check_passed", at: @now}], superseded?: false},
          @now
        )

      assert Strength.of(touches, @now) > 0.0
    end

    test "a failing recheck pulls strength below a passing one" do
      passed =
        Strength.touches_for(
          %{created_at: @now, touches: [%{kind: "check_passed", at: @now}], superseded?: false},
          @now
        )

      failed =
        Strength.touches_for(
          %{created_at: @now, touches: [%{kind: "check_failed", at: @now}], superseded?: false},
          @now
        )

      assert Strength.of(failed, @now) < Strength.of(passed, @now)
    end

    test "a superseded fact is dragged below a live one" do
      live = Strength.touches_for(%{created_at: @now, touches: [], superseded?: false}, @now)
      dead = Strength.touches_for(%{created_at: @now, touches: [], superseded?: true}, @now)
      assert Strength.of(dead, @now) < Strength.of(live, @now)
    end
  end
end
