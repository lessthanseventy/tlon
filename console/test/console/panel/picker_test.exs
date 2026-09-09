defmodule Console.Panel.PickerTest do
  # The switcher/palette overlay's body: query line, rule, rows. Pure render — rows in, styled
  # runs out.
  use ExUnit.Case, async: true

  import Console.PanelText, only: [text: 1, row_text: 1]

  alias Console.Panel.Picker

  defp rect(h \\ 12, w \\ 70), do: %{x: 0, y: 0, w: w, h: h}

  defp thread(label, context), do: %{kind: :thread, tag: "thread", keys: nil, label: label, context: context}

  defp verb(keys, label, doc), do: %{kind: :verb, tag: "centre", keys: keys, label: label, context: doc}

  defp items do
    [
      thread("cockpit slice two", "ficciones · #general"),
      thread("menard gaps", "ficciones · #general")
    ]
  end

  test "paints the typed query with a cursor, above a rule" do
    [query, rule | _] = Picker.render(%{items: items(), query: "cock", cursor: 0}, rect())

    assert row_text(query) =~ "▸ cock▎"
    assert row_text(rule) =~ "─"
  end

  test "a switcher row is tag · label · context, and leaves out the keycap column" do
    rows = Picker.render(%{items: items(), query: "", cursor: 0}, rect())
    row = row_text(Enum.at(rows, 2))

    assert row =~ "thread"
    assert row =~ "cockpit slice two"
    assert row =~ "ficciones · #general"
  end

  test "a palette row carries its keycap and the sentence saying what the verb does" do
    items = [verb("v", "term", "flip the centre between the conversation and the terminal")]
    row = %{items: items, query: "", cursor: 0} |> Picker.render(rect()) |> Enum.at(2) |> row_text()

    assert row =~ "v"
    assert row =~ "term"
    assert row =~ "flip the centre"
  end

  test "the cursor row renders inverse and carries the ▸ lead" do
    rows = Picker.render(%{items: items(), query: "", cursor: 1}, rect())
    styles = rows |> Enum.at(3) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    assert styles == [:selected]
    assert row_text(Enum.at(rows, 3)) =~ "▸"
    refute row_text(Enum.at(rows, 2)) =~ "▸"
  end

  test "an empty result set says so rather than painting a blank box" do
    rows = Picker.render(%{items: [], query: "zzz", cursor: 0}, rect())
    assert text(rows) =~ "nothing matches"
  end

  test "more rows than fit scroll so the cursor stays visible" do
    items = for i <- 1..20, do: thread("thread #{i}", "ws")
    rows = Picker.render(%{items: items, query: "", cursor: 19}, rect(8))

    assert text(rows) =~ "thread 20"
    refute text(rows) =~ "thread 1\n"
  end

  test "never draws past its rect" do
    items = for i <- 1..20, do: thread("thread #{i}", "a very long context that would overflow")
    rows = Picker.render(%{items: items, query: "", cursor: 0}, rect(6, 40))

    assert length(rows) <= 6
    assert Enum.all?(rows, &(Console.Panel.row_width(&1) <= 40))
  end

  test "a click on a row picks THAT row, and a click on the query line picks nothing" do
    data = %{items: items(), query: "", cursor: 0}

    assert Picker.pick(data, rect(), 2) == {:picker_pick, Enum.at(items(), 0)}
    assert Picker.pick(data, rect(), 3) == {:picker_pick, Enum.at(items(), 1)}
    assert Picker.pick(data, rect(), 0) == nil
    assert Picker.pick(data, rect(), 1) == nil
    assert Picker.pick(data, rect(), 9) == nil
  end

  test "a click resolves against the SCROLLED list, not the top of it" do
    items = for i <- 1..20, do: thread("thread #{i}", "ws")
    data = %{items: items, query: "", cursor: 19}

    # cursor 19 in a 6-row body scrolls the list; the last body row is the cursor's
    assert {:picker_pick, %{label: "thread 20"}} = Picker.pick(data, rect(8), 7)
  end
end
