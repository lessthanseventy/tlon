defmodule Console.PickerTest do
  # The two overlays of UX slice 2 as one pure thing: a query, a cursor, and a filtered corpus.
  # The switcher's corpus is the rail's OWN sidebar read, so these fixtures are the shape
  # `Server.Board.sidebar/0` returns.
  use ExUnit.Case, async: true

  alias Console.Picker

  @groups [
    %{
      workspace: %{id: 1, name: "ficciones"},
      channels: [
        %{
          id: 10,
          name: "general",
          kind: "general",
          threads: [%{id: 100, title: "cockpit slice two"}, %{id: 101, title: "menard gaps"}]
        },
        %{id: 11, name: "reviews", kind: "topic", threads: [%{id: 102, title: "palette review"}]}
      ]
    },
    %{
      workspace: %{id: 2, name: "freedonia"},
      channels: [%{id: 20, name: "general", kind: "general", threads: [%{id: 200, title: "duck soup"}]}]
    }
  ]

  defp state(over \\ %{}), do: Map.merge(%{sidebar: @groups, active_key: 1}, over)

  defp labels(picker, state), do: picker |> Picker.entries(state) |> Enum.map(& &1.label)

  describe "the switcher's corpus" do
    test "is every workspace, channel and thread — not just the active workspace's" do
      shown = labels(Picker.open(:switcher), state())

      assert "ficciones" in shown
      assert "freedonia" in shown
      assert "#reviews" in shown
      # freedonia is NOT the active workspace, but its thread is still reachable — the point of it
      assert "duck soup" in shown
    end

    test "a thread row carries the workspace and channel a jump has to switch to" do
      row = :switcher |> Picker.open() |> Picker.entries(state()) |> Enum.find(&(&1.label == "duck soup"))

      assert row.kind == :thread
      assert row.workspace_id == 2
      assert row.channel_id == 20
      assert row.thread_id == 200
    end

    test "matches on the whole path, so a workspace name narrows to its threads" do
      shown = :switcher |> Picker.open() |> Picker.type("freedonia") |> labels(state())

      assert "duck soup" in shown
      refute "menard gaps" in shown
    end

    test "a query narrows to what matches, dropping the rest" do
      shown = :switcher |> Picker.open() |> Picker.type("menard") |> labels(state())
      assert shown == ["menard gaps"]
    end

    test "an empty sidebar (server down, first frame) yields no rows rather than crashing" do
      assert Picker.entries(Picker.open(:switcher), %{}) == []
      assert Picker.entries(Picker.open(:switcher), state(%{sidebar: []})) == []
    end
  end

  describe "the palette's corpus" do
    test "is every verb the cockpit has" do
      rows = Picker.entries(Picker.open(:palette), state())
      assert length(rows) == length(Console.Verbs.all())
    end

    test "a row carries the keycap, the sentence, and the event picking it replays" do
      row = :palette |> Picker.open() |> Picker.type("term") |> Picker.entries(state()) |> List.first()

      assert row.keys
      assert row.context != ""
      assert row.kind == :verb
    end

    test "finds a verb by what it DOES, not only by its key — the whole point of it" do
      shown = :palette |> Picker.open() |> Picker.type("clipboard") |> labels(state())
      assert "yank" in shown
    end

    test "finds a verb by its group, so \"drawer\" lists the drawer's keys" do
      rows = :palette |> Picker.open() |> Picker.type("drawer") |> Picker.entries(state())
      assert Enum.any?(rows, &(&1.tag == "drawer"))
    end
  end

  describe "the query and the cursor" do
    test "typing and backspacing edit the query and put the cursor back on the best match" do
      picker = :switcher |> Picker.open() |> Picker.type("m") |> Picker.type("e")
      assert picker.query == "me"

      moved = Picker.move(picker, 1, 5)
      assert moved.cursor == 1
      assert Picker.backspace(moved).query == "m"
      assert Picker.backspace(moved).cursor == 0
    end

    test "backspace on an empty query is a no-op, not an error" do
      assert Picker.backspace(Picker.open(:palette)).query == ""
    end

    test "clear_query empties it but keeps the picker open" do
      picker = :palette |> Picker.open() |> Picker.type("x") |> Picker.clear_query()
      assert picker.query == ""
      assert picker.kind == :palette
    end

    test "the cursor wraps in both directions — a short list is a ring" do
      picker = Picker.open(:switcher)
      assert Picker.move(picker, -1, 3).cursor == 2
      assert picker |> Picker.move(1, 3) |> Picker.move(1, 3) |> Picker.move(1, 3) |> Map.fetch!(:cursor) == 0
    end

    test "a cursor against an empty list is 0, never out of range" do
      assert Picker.move(Picker.open(:switcher), 1, 0).cursor == 0
    end

    test "selected/2 reads the cursor's row, and nil past the end" do
      picker = :switcher |> Picker.open() |> Picker.type("menard")
      items = Picker.entries(picker, state())

      assert Picker.selected(items, picker).label == "menard gaps"
      assert Picker.selected(items, %{picker | cursor: 9}) == nil
    end
  end

  test "each kind names itself and says how it is driven" do
    assert Picker.title(:switcher) == "GO TO"
    assert Picker.title(Picker.open(:palette)) == "COMMANDS"
    assert Picker.title(:history) == "HISTORY"
    assert Picker.hint(:switcher) =~ "jump"
    assert Picker.hint(:palette) =~ "run"
    assert Picker.hint(:history) =~ "open"
  end

  describe "the history corpus" do
    defp history_state do
      state(%{
        history: [
          %{
            id: 53,
            title: "Caelestia to Astral migration",
            workspace_id: 1,
            project: "ficciones",
            at: ~U[2026-09-10 12:00:00Z]
          },
          %{id: 54, title: "orient: what is excessibility", workspace_id: 2, project: nil, at: ~U[2026-09-01 08:00:00Z]}
        ]
      })
    end

    test "is the closed threads, each a jump to its workspace and thread" do
      [row | _] = :history |> Picker.open() |> Picker.entries(history_state())

      assert row.kind == :thread
      assert row.label == "Caelestia to Astral migration"
      assert row.context =~ "ficciones"
      assert row.context =~ "2026-09-10"
      assert {row.workspace_id, row.thread_id} == {1, 53}
    end

    test "filters by title and project" do
      assert labels(%{Picker.open(:history) | query: "astral"}, history_state()) == ["Caelestia to Astral migration"]
      assert labels(%{Picker.open(:history) | query: "excess"}, history_state()) == ["orient: what is excessibility"]
    end

    test "no history read yet (the first frame) yields no rows rather than crashing" do
      assert labels(Picker.open(:history), state()) == []
    end
  end
end
