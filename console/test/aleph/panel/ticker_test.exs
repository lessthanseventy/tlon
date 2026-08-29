defmodule Console.Panel.TickerTest do
  @moduledoc """
  The bottom band framing the Tlön center: the newest funes activity event, one line, reusing
  `Activity.summarize/1` so the pulse and the full feed never drift on how an event reads.
  """
  use ExUnit.Case, async: true

  alias Console.Panel.Ticker

  @rect %{x: 0, y: 0, w: 60, h: 3}

  test "the latest event renders via Activity.summarize/1" do
    fact = %{id: 35, kind: "note", text: "hello"}
    [row] = Ticker.render(%{events: [{:fact_banked, fact}]}, @rect)
    text = Enum.map_join(row, fn {t, _} -> t end)

    assert text =~ "funes"
    assert text =~ "fact #35"
    assert Enum.any?(row, fn {_t, s} -> s == :event_ok end)
  end

  test "an empty buffer renders a dim idle line" do
    [row] = Ticker.render(%{events: []}, @rect)
    text = Enum.map_join(row, fn {t, _} -> t end)

    assert text =~ "funes"
    assert text =~ "idle"
    assert Enum.any?(row, fn {_t, s} -> s == :dim end)
  end
end
