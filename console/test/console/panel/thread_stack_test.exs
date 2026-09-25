defmodule Console.Panel.ThreadStackTest do
  # The cockpit center: the OPEN thread's conversation — scrollable, markdown — and, with nothing
  # open, a line pointing at the rail (the rail is the list). Pure render.
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

  test "an open prompt renders the ask and its options; a resolved one is a receipt" do
    options = [%{"key" => "y", "label" => "Yes"}, %{"key" => "n", "label" => "No"}]

    cards = [
      card(%{
        id: 42,
        title: "orient",
        messages: [
          %{
            author: "tlon",
            body: "…",
            kind: "prompt",
            payload: %{"summary" => "bash: env", "options" => options},
            resolved_at: nil,
            resolution: nil
          },
          %{
            author: "tlon",
            body: "…",
            kind: "prompt",
            payload: %{"summary" => "bash: ls", "options" => options},
            resolved_at: ~U[2026-09-25 10:00:00Z],
            resolution: "answered: y"
          }
        ]
      })
    ]

    out = %{cards: cards, opened: 42} |> ThreadStack.render(rect()) |> text()
    assert out =~ "⚑ waiting on you — bash: env"
    assert out =~ "(y) Yes · (n) No"
    assert out =~ "⚑ bash: ls — answered: y"
  end

  test "an empty stack renders a placeholder" do
    assert %{cards: []} |> ThreadStack.render(rect()) |> text() =~ "no threads yet"
  end

  describe "nothing open" do
    test "the centre is not a list: it points at the rail, and shows no thread" do
      cards = [card(%{id: 39, title: "build the thing", messages: [%{author: "kimi", body: "hi"}]})]
      out = %{cards: cards, opened: nil} |> ThreadStack.render(rect()) |> text()

      assert out =~ "pick a thread on the rail"
      refute out =~ "build the thing"
      refute out =~ "kimi: hi"
    end

    test "its only verb is n" do
      assert ThreadStack.hints(%{cards: [card(%{})], opened: nil}) == [{"n", "new"}]
    end
  end

  describe "conversation mode (a thread opened)" do
    test "shows the opened thread's messages (the reply input is its own band, the esc hint the footer's)" do
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
      assert {"esc", "back"} in ThreadStack.hints(%{cards: cards, opened: 42})
      # the OTHER thread's row is not shown in conversation mode
      refute out =~ "#43 other"
    end

    test "an opened id that no longer exists falls back to pointing at the rail" do
      out = %{cards: [card(%{id: 1, title: "x"})], opened: 999} |> ThreadStack.render(rect()) |> text()
      assert out =~ "pick a thread on the rail"
    end

    test "clicks are inert (so text selection works): the panel picks nothing" do
      refute function_exported?(ThreadStack, :pick, 3)
    end
  end

  describe "the typing indicator (2026-09-10)" do
    test "the typing indicator sits under the last message, not in the header" do
      card = %{
        id: 9,
        title: "general",
        active?: true,
        lead: "hronir",
        typing: "hronir",
        messages: [%{author: "andrew", body: "tell me a joke"}]
      }

      rows = ThreadStack.render(%{cards: [card], opened: 9}, %{x: 0, y: 0, w: 60, h: 20})
      text = Enum.map(rows, fn row -> Enum.map_join(row, "", &elem(&1, 0)) end)

      typing_at = Enum.find_index(text, &(&1 =~ "is typing"))
      message_at = Enum.find_index(text, &(&1 =~ "tell me a joke"))
      header_at = Enum.find_index(text, &(&1 =~ "#9 general"))

      assert typing_at > message_at, "the indicator promises a message — it belongs where that lands"
      assert typing_at > header_at
      refute Enum.at(text, header_at) =~ "is typing"
    end
  end
end
