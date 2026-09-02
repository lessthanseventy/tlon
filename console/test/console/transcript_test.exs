defmodule Console.TranscriptTest do
  use ExUnit.Case, async: true

  alias Console.Transcript

  # A wide rect so nothing wraps unless a test wants it to.
  defp rect(w \\ 80, h \\ 1000), do: %{x: 0, y: 0, w: w, h: h}

  defp m(author, body, at \\ ~U[2026-08-18 14:30:00Z]), do: %{author: author, body: body, created_at: at}

  defp block(title, id, messages, state \\ "open"),
    do: %{thread: %{id: id, title: title, state: state}, messages: messages}

  defp view(blocks, opts \\ []) do
    %{
      blocks: blocks,
      selected: Keyword.get(opts, :selected, 0),
      folded: Keyword.get(opts, :folded, MapSet.new()),
      zoom: Keyword.get(opts, :zoom, nil)
    }
  end

  defp texts(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, "", fn {t, _s} -> t end) end)

  # Author-name runs carry a per-author truecolor (`{:rgb, _, _}`); one per turn header.
  defp author_runs(rows, name) do
    rows
    |> Enum.flat_map(& &1)
    |> Enum.filter(fn {t, s} -> t == name and match?({:rgb, _, _}, s) end)
  end

  test "a folded thread renders as one header row with its count, no message bodies" do
    rows = Transcript.render(view([block("Tlön", 1, [m("pi", "hidden")])], folded: MapSet.new([1])), rect())
    body = texts(rows)

    assert Enum.any?(body, &(&1 =~ "▸" and &1 =~ "Tlön" and &1 =~ "(1)"))
    refute Enum.any?(body, &(&1 =~ "hidden"))
  end

  test "an expanded thread renders an open arrow, its title, and its message body" do
    rows = Transcript.render(view([block("Tlön", 1, [m("pi", "visible")])]), rect())
    body = texts(rows)

    assert Enum.any?(body, &(&1 =~ "▾" and &1 =~ "Tlön"))
    assert Enum.any?(body, &(&1 =~ "visible"))
  end

  test "the selected block's header row carries the :selected style" do
    rows = Transcript.render(view([block("A", 1, []), block("B", 2, [])], selected: 1), rect())

    selected_titled =
      Enum.filter(rows, fn row ->
        Enum.any?(row, fn {t, _} -> t =~ "B" end) and Enum.any?(row, fn {_, s} -> s == :selected end)
      end)

    assert selected_titled != []
  end

  test "consecutive messages from one author collapse under a single turn header" do
    rows = Transcript.render(view([block("Tlön", 1, [m("pi", "one"), m("pi", "two")])]), rect())

    assert length(author_runs(rows, "pi")) == 1
    assert Enum.any?(texts(rows), &(&1 =~ "one"))
    assert Enum.any?(texts(rows), &(&1 =~ "two"))
  end

  test "a change of author starts a new turn header" do
    rows = Transcript.render(view([block("Tlön", 1, [m("pi", "hi"), m("claude", "yo")])]), rect())

    assert length(author_runs(rows, "pi")) == 1
    assert length(author_runs(rows, "claude")) == 1
  end

  test "messages crossing a day boundary drop a dated divider" do
    msgs = [m("pi", "day one", ~U[2026-08-15 10:00:00Z]), m("pi", "day two", ~U[2026-08-16 10:00:00Z])]
    rows = Transcript.render(view([block("Tlön", 1, msgs)]), rect())

    assert Enum.any?(texts(rows), &(&1 =~ "16 Aug"))
  end

  test "zoom renders only the target thread, hiding the others" do
    blocks = [block("A", 1, [m("x", "aaa")]), block("B", 2, [m("y", "bbb")])]
    rows = Transcript.render(view(blocks, zoom: 2), rect())
    body = texts(rows)

    assert Enum.any?(body, &(&1 =~ "bbb"))
    refute Enum.any?(body, &(&1 =~ "aaa"))
    assert Enum.any?(body, &(&1 =~ "B"))
  end

  test "a folded episode header shows its participants and message count" do
    msgs = [m("pi", "hi"), m("claude", "yo"), m("pi", "more")]
    rows = Transcript.render(view([block("Debate", 1, msgs)], folded: MapSet.new([1])), rect())
    header = rows |> texts() |> Enum.find(&(&1 =~ "Debate"))

    assert header =~ "pi"
    assert header =~ "claude"
    assert header =~ "(3)"
  end

  test "a closed episode is marked closed in its header" do
    rows = Transcript.render(view([block("Done thing", 1, [m("pi", "x")], "closed")], folded: MapSet.new([1])), rect())
    assert Enum.any?(texts(rows), &(&1 =~ "Done thing" and &1 =~ "closed"))
  end

  test "a long body wraps to the rect width across multiple rows" do
    long = "word " |> String.duplicate(20) |> String.trim()
    rows = Transcript.render(view([block("Tlön", 1, [m("pi", long)])]), rect(20))

    assert Enum.all?(texts(rows), &(String.length(&1) <= 20))
    assert Enum.count(texts(rows), &(&1 =~ "word")) > 1
  end

  # selected_row/2 — the viewport-reveal anchor (the browse j/k fix): the row index of the
  # selected block's header must equal that block's first row in render/2's output.
  describe "selected_row/2" do
    test "the first block's header is row 0; a later block's header lands where render puts it" do
      blocks = [block("one", 1, [m("pi", "a"), m("pi", "b")]), block("two", 2, [m("pi", "c")])]
      v = view(blocks, selected: 1)

      row = Transcript.selected_row(v, 80)
      rendered = texts(Transcript.render(v, rect()))

      assert Transcript.selected_row(view(blocks, selected: 0), 80) == 0
      assert Enum.at(rendered, row) =~ "two"
    end

    test "folded blocks above the selection shrink the offset in lockstep with render" do
      blocks = [block("one", 1, [m("pi", "a"), m("pi", "b")]), block("two", 2, [m("pi", "c")])]
      v = view(blocks, selected: 1, folded: MapSet.new([1]))

      row = Transcript.selected_row(v, 80)
      assert Enum.at(texts(Transcript.render(v, rect())), row) =~ "two"
    end

    test "zoomed or empty views have no list selection to reveal" do
      assert Transcript.selected_row(view([block("one", 1, [])], zoom: 1), 80) == nil
      assert Transcript.selected_row(view([]), 80) == nil
    end
  end

  test "the operator's turn header and body render :operator pink; agents keep truecolor + green" do
    rows = Transcript.render(view([block("Tlön", 1, [m("andrew", "do it"), m("pi", "ok")])]), rect())
    runs = Enum.flat_map(rows, & &1)

    assert {"andrew", :operator} in runs
    assert {"  do it", :operator} in runs
    assert author_runs(rows, "pi") != []
    assert {"  ok", :normal} in runs
  end

  test "a paragraph break in a body renders as a blank row" do
    rows = Transcript.render(view([block("Tlön", 1, [m("pi", "one\n\ntwo")])]), rect())
    body = texts(rows)
    one = Enum.find_index(body, &(&1 == "  one"))
    assert one
    assert Enum.at(body, one + 1) == ""
    assert Enum.at(body, one + 2) == "  two"
  end
end
