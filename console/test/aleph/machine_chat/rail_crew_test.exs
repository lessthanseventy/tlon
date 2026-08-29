defmodule Console.MachineChat.RailCrewTest do
  @moduledoc "The THREADS rail renders pre-annotated data; selection stays visible. (CREW moved to Console.Panel.Crew.)"
  use ExUnit.Case, async: true

  alias Console.MachineChat.Rail

  defp texts(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, "", fn {t, _s} -> t end) end)

  defp row(id, title, opts \\ []) do
    %{
      id: id,
      title: title,
      state: Keyword.get(opts, :state, "open"),
      status: Keyword.get(opts, :status, :none),
      unread: Keyword.get(opts, :unread, 0)
    }
  end

  describe "Rail.render/2" do
    test "glyphs by status/state, unread badge, selection styled" do
      rows = [
        row(1, "⌂ Tlön", status: :live),
        row(2, "fix the bug", status: :working, unread: 3),
        row(3, "old thing", state: "closed")
      ]

      rendered = Rail.render(%{rows: rows, selected_id: 1}, %{x: 0, y: 0, w: 26, h: 20})
      body = texts(rendered)

      assert Enum.at(body, 0) =~ "THREADS"
      assert Enum.any?(body, &(&1 =~ "⌂ Tlön"))
      assert Enum.any?(body, &(&1 =~ "fix the bug" and &1 =~ "•3"))
      assert Enum.any?(body, &(&1 =~ "✓ old thing"))

      # the selected row carries the :selected style on its title
      selected_runs = rendered |> Enum.flat_map(& &1) |> Enum.filter(fn {_t, s} -> s == :selected end)
      assert [{t, _}] = selected_runs
      assert t =~ "Tlön"
    end

    test "a long title clips to the rail width" do
      rows = [row(1, String.duplicate("x", 60))]
      [_, _, only] = Rail.render(%{rows: rows, selected_id: 1}, %{x: 0, y: 0, w: 20, h: 10})
      assert only |> Enum.map_join("", fn {t, _} -> t end) |> String.length() <= 20
    end

    test "windowing keeps a deep selection visible" do
      rows = for i <- 1..30, do: row(i, "thread #{i}")
      rendered = Rail.render(%{rows: rows, selected_id: 25}, %{x: 0, y: 0, w: 26, h: 10})
      assert Enum.any?(texts(rendered), &(&1 =~ "thread 25"))
    end

    test "a workline row wears its stage chip; a parked gate outranks it; plain rows don't" do
      rows = [
        row(1, "plain thread"),
        2 |> row("workline") |> Map.merge(%{stage: "spec", awaiting: nil}),
        3 |> row("parked") |> Map.merge(%{stage: "spec", awaiting: "andrew"})
      ]

      body = %{rows: rows, selected_id: 1} |> Rail.render(%{x: 0, y: 0, w: 26, h: 20}) |> texts()

      assert Enum.any?(body, &(&1 =~ "·spec"))
      assert Enum.any?(body, &(&1 =~ "⏸gate"))
      refute Enum.any?(body, &(&1 =~ "plain thread ·"))
    end
  end
end
