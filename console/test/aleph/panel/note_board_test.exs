defmodule Console.Panel.NoteBoardTest do
  @moduledoc "The Notes board — a plain list of a scope's freeform notes."
  use ExUnit.Case, async: true

  alias Console.Panel.NoteBoard

  defp text(row), do: Enum.map_join(row, fn {t, _s} -> t end)
  @rect %{x: 0, y: 0, w: 60, h: 20}

  test "renders each note's body headline with its author" do
    notes = [
      %{body: "check the deploy gate", author: "hronir"},
      %{body: "multi\nline\nnote", author: nil}
    ]

    lines = %{notes: notes} |> NoteBoard.render(@rect) |> Enum.map(&text/1)

    assert Enum.any?(lines, &(&1 =~ "check the deploy gate" and &1 =~ "hronir"))
    assert Enum.any?(lines, &(&1 =~ "multi"))
    assert Enum.any?(lines, &(&1 =~ "line"))
  end

  test "empty scope shows a quiet hint" do
    lines = %{notes: []} |> NoteBoard.render(@rect) |> Enum.map(&text/1)
    assert Enum.any?(lines, &(&1 =~ "no notes"))
  end

  test "a nil body doesn't crash" do
    assert NoteBoard.render(%{notes: [%{body: nil, author: "x"}]}, @rect) != []
  end
end
