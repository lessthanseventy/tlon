defmodule Console.Panel.PlaceholderTest do
  @moduledoc """
  The right pane's stand-in (UX slice 1, task 3): a thread is open, its coworker isn't live, so the
  pane names the verb that starts one instead of showing an empty box.
  """
  use ExUnit.Case, async: true

  import Console.PanelText, only: [text: 1, row_text: 1]

  alias Console.Panel.Placeholder

  defp rect(w \\ 60, h \\ 10), do: %{x: 0, y: 0, w: w, h: h}

  test "one centred line, and it names no verb that doesn't exist" do
    rows = Placeholder.render(%{}, rect())

    assert text(rows) =~ Placeholder.copy()
    # `s` is :section_next in Tlön nav and nothing spawns on demand — the old copy promised both.
    refute text(rows) =~ "spawns one"
    refute text(rows) =~ "Enter to spawn"
    assert Enum.count(rows, &(&1 != [])) == 1
  end

  test "the line is centred in the box, vertically and horizontally" do
    rows = Placeholder.render(%{}, rect(60, 9))
    {row, index} = Enum.find(Enum.with_index(rows), fn {row, _i} -> row != [] end)

    assert index == 4
    line = row_text(row)
    lead = String.length(line) - String.length(String.trim_leading(line))
    assert lead == div(60 - String.length(String.trim(line)), 2)
  end

  test "a box too small to hold the line clips instead of overflowing" do
    rows = Placeholder.render(%{}, rect(10, 1))

    assert length(rows) == 1
    assert String.length(row_text(hd(rows))) <= 10
  end

  test "no data renders nothing" do
    assert Placeholder.render(nil, rect()) == []
  end
end
