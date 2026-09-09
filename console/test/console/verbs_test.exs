defmodule Console.VerbsTest do
  # The palette's corpus, and the gate that keeps it honest: a verb's `event` is REPLAYED through
  # the keymap when you pick its row, so a key that moves and a table that doesn't is exactly the
  # drift this file exists to catch.
  use ExUnit.Case, async: true

  alias Console.Keymap
  alias Console.Tlon.Focus
  alias Console.Verbs

  setup do
    Console.TestWorkspaces.put()
  end

  # The two states a verb can be live in: the bare command table (no Focus — the server-down
  # sentinel's path), and a workspace with the thread list focused, which is where the cockpit
  # actually sits.
  defp nav do
    %{
      active_key: 0,
      focused_id: 2,
      composer_thread_id: 2,
      threads: [%{id: 1}, %{id: 2}, %{id: 3}],
      center_live?: false,
      center_view: :chat,
      opened_thread: nil,
      input: nil,
      drawer: nil,
      last_drawer: :memory,
      picker: nil,
      live_workspaces: [],
      author_cursor: 0,
      pending_delete: nil,
      pending_confirm: nil,
      author_edit: nil,
      tlon_delete: nil,
      lock?: false
    }
  end

  defp centre, do: Map.merge(nav(), %{focus: %Focus{in_terminal?: true}, tlon_layout: layout()})

  # The third live state: the keys taken back OUT of the terminal, which is where the rail verbs
  # (`v`, `y`, `s`, `#`, `[`/`]`) live. Without it the gate reported half the table as dead.
  defp rail, do: Map.merge(centre(), %{focus: %Focus{in_terminal?: false}, live_workspaces: two_workspaces()})

  defp layout, do: %{left: [:a, :b], right: [:c], sections: %{}, counts: %{a: 3, b: 2, c: 4}}

  defp two_workspaces,
    do: [
      %{id: 0, name: "Tlön", roster: [], type: "code", paths: [], scope: "machine"},
      %{id: 1, name: "Freedonia", roster: [], type: "code", paths: [], scope: "machine"}
    ]

  defp reaches?(event) do
    Enum.any?([nav(), centre(), rail()], fn state ->
      # A raise here means a clause matched and then read a key this particular state does not
      # carry — that is the state being partial, not the binding being dead, and another state
      # covers it. A verb that reaches nothing in ANY state is the drift worth failing on.
      try do
        match?({_next, effect} when effect != :none, Keymap.handle(event, state))
      rescue
        _error -> false
      end
    end)
  end

  describe "every verb the palette can fire still reaches a live binding" do
    test "each event produces an effect in at least one live state" do
      dead =
        Verbs.all()
        |> Enum.filter(& &1.event)
        |> Enum.reject(&reaches?(&1.event))
        |> Enum.map(& &1.keys)

      # a keycap here is in the palette but bound to nothing — the drift this file exists to catch
      assert dead == []
    end

    test "the two chords open the overlays the table says they do" do
      go_to = Enum.find(Verbs.all(), &(&1.keys == "^⇧K"))
      commands = Enum.find(Verbs.all(), &(&1.keys == "^⇧P"))

      assert {%{picker: %{kind: :switcher}}, :repaint} = Keymap.handle(go_to.event, nav())
      assert {%{picker: %{kind: :palette}}, :repaint} = Keymap.handle(commands.event, nav())
    end
  end

  describe "the table itself" do
    test "every row carries a sentence — a keycap alone was the thing that wasn't working" do
      undocumented = Verbs.all() |> Enum.reject(&(is_binary(&1.doc) and &1.doc != "")) |> Enum.map(& &1.keys)
      assert undocumented == []
    end

    test "every row has a keycap and a label, and its group is one of the five" do
      for verb <- Verbs.all() do
        assert is_binary(verb.keys) and verb.keys != ""
        assert is_binary(verb.label) and verb.label != ""
        assert verb.group in [:global, :centre, :rail, :drawer, :typing]
      end
    end

    test "the fuzzy subject carries all four, so a verb is findable by any of them" do
      verb = Enum.find(Verbs.all(), &(&1.label == "model"))
      subject = Verbs.subject(verb)

      assert subject =~ "centre"
      assert subject =~ "m"
      assert subject =~ "model"
      assert subject =~ "driver model"
    end

    test "the consequential verbs are listed but deliberately NOT fireable from a fuzzy list" do
      for label <- ["quit", "delete thread"] do
        verb = Enum.find(Verbs.all(), &(&1.label == label))
        assert verb, "#{label} should still be listed — the palette is where you learn its key"
        assert verb.event == nil
      end
    end

    test "no two rows share a keycap within one group — a palette that lists a key twice is a bug" do
      duplicates =
        Verbs.all()
        |> Enum.group_by(&{&1.group, &1.keys})
        |> Enum.filter(fn {_key, rows} -> length(rows) > 1 end)
        |> Enum.map(&elem(&1, 0))

      assert duplicates == []
    end

    test "the footer's own workspace hints all exist in the table, so the two cannot drift apart" do
      keycaps = MapSet.new(Verbs.all(), & &1.keys)

      for cap <- ["^⇧P", "Alt+d", "c", "n", "v", "m"] do
        assert MapSet.member?(keycaps, cap), "the footer advertises #{cap} but the palette has no row for it"
      end
    end
  end
end
