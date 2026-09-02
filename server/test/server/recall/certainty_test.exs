defmodule Server.Recall.CertaintyTest do
  # Verification half-life (design: docs/plans/2026-08-19-funes-forgetting-design.md): "we
  # verified X" loses authority as its check ages. Unlike Brief.certainty/1, a check_cmd that
  # never PASSED (or passed long ago) is not `:checked`. Pure — no DB.
  use ExUnit.Case, async: true

  alias Server.Recall.Certainty

  @now ~U[2026-08-19 12:00:00Z]
  @hl 30 * 24 * 3600

  defp ago(seconds), do: DateTime.shift(@now, second: -seconds)

  test "an operator-stated fact is always :stated, checks or not" do
    assert Certainty.of(%{provenance: "stated", last_pass_at: nil}, @now) == :stated
  end

  test "a derived fact with a fresh passing check is :checked" do
    assert Certainty.of(%{provenance: "derived", last_pass_at: ago(3600)}, @now, half_life_s: @hl) == :checked
  end

  test "a derived fact whose passing check has gone stale decays to :opinion" do
    assert Certainty.of(%{provenance: "derived", last_pass_at: ago(@hl * 2)}, @now, half_life_s: @hl) == :opinion
  end

  test "a derived fact that never passed a check is :opinion (a command is not a proof)" do
    assert Certainty.of(%{provenance: "derived", last_pass_at: nil}, @now) == :opinion
  end
end
