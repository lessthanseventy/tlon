defmodule Console.Panel.ThreadStackTest do
  # The cockpit center (two-step, 2026-09-01): a LIST of thread rows (no thread opened), or ONE
  # thread's CONVERSATION (opened: id) — scrollable, markdown, esc back. Pure render.
  use ExUnit.Case, async: true

  import Console.PanelText, only: [text: 1]

  alias Console.Panel.ThreadStack

  defp rect(h \\ 40), do: %{x: 0, y: 0, w: 80, h: h}

  defp card(over) do
    Map.merge(
      %{id: 1, title: "a thread", lead: nil, stage: nil, awaiting: nil, active?: false, typing: nil, messages: []},
      over
    )
  end

  test "an empty stack renders a placeholder" do
    assert %{cards: []} |> ThreadStack.render(rect()) |> text() =~ "no threads yet"
  end

  describe "list mode (no thread opened)" do
    test "each thread is a single row — id, title, lead/stage chips; no messages" do
      cards = [
        card(%{
          id: 39,
          title: "build the thing",
          lead: "kimi",
          stage: "build",
          messages: [%{author: "kimi", body: "hi"}]
        }),
        card(%{id: 40, title: "review PR"})
      ]

      rows = ThreadStack.render(%{cards: cards}, rect())
      assert length(rows) == 2
      out = text(rows)
      assert out =~ "#39 build the thing"
      assert out =~ "@kimi"
      assert out =~ "build"
      # bodies are NOT shown in the list
      refute out =~ "kimi: hi"
    end

    test "the active (cursor) row is lit with the gutter" do
      cards = [card(%{id: 1, active?: true}), card(%{id: 2, active?: false})]
      [first, second] = ThreadStack.render(%{cards: cards}, rect())
      assert Enum.any?(first, fn {t, s} -> t == "▌ " and s == :accent end)
      refute Enum.any?(second, fn {t, s} -> t == "▌ " and s == :accent end)
    end

    test "a typing thread shows the typing chip" do
      out = %{cards: [card(%{typing: "hronir"})]} |> ThreadStack.render(rect()) |> text()
      assert out =~ "hronir is typing…"
    end

    test "a click on a row OPENS that thread (not fold)" do
      cards = [card(%{id: 7}), card(%{id: 8})]
      assert ThreadStack.pick(%{cards: cards}, rect(), 0) == {:open_thread_view, 7}
      assert ThreadStack.pick(%{cards: cards}, rect(), 1) == {:open_thread_view, 8}
      assert ThreadStack.pick(%{cards: cards}, rect(), 9) == nil
    end
  end

  describe "conversation mode (a thread opened)" do
    test "shows the opened thread's messages and an esc-back hint (the reply input is its own band now)" do
      cards = [
        card(%{
          id: 42,
          title: "review PR",
          lead: "hronir",
          stage: "review",
          messages: [%{author: "andrew", body: "take a look"}, %{author: "hronir", body: "on it"}]
        }),
        card(%{id: 43, title: "other"})
      ]

      out = %{cards: cards, opened: 42} |> ThreadStack.render(rect()) |> text()
      assert out =~ "‹ #42 review PR"
      assert out =~ "andrew:"
      assert out =~ "take a look"
      assert out =~ "hronir:"
      # the inline `↳ reply… (c)` stub is gone — replying is the persistent Panel.Reply band below
      refute out =~ "reply to #42"
      assert out =~ "esc"
      # the OTHER thread's row is not shown in conversation mode
      refute out =~ "#43 other"
    end

    test "an opened id that no longer exists falls back to the list" do
      out = %{cards: [card(%{id: 1, title: "x"})], opened: 999} |> ThreadStack.render(rect()) |> text()
      assert out =~ "#1 x"
    end

    test "clicks are inert in conversation mode (so text selection works)" do
      assert ThreadStack.pick(%{cards: [card(%{id: 1})], opened: 1}, rect(), 3) == nil
    end
  end
end
