defmodule Console.Panel.ConversationTest do
  # The cockpit chat box: messages plus the trailing presence indicator — explicit thinking
  # (accent) outranks tmux-inferred working (dim). Headless, pure render.
  use ExUnit.Case, async: true

  alias Console.Panel.Conversation

  @rect %{x: 0, y: 0, w: 60, h: 40}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  defp style_of(rows, needle) do
    Enum.find_value(rows, fn row -> Enum.find_value(row, fn {t, s} -> if t =~ needle, do: s end) end)
  end

  test "a blank row separates messages; body paragraphs render with a blank line" do
    rows =
      Conversation.render(
        %{title: "t", messages: [%{author: "a", body: "one\n\ntwo"}, %{author: "b", body: "three"}]},
        @rect
      )

    texts = lines(rows)
    # message one: first line, paragraph gap, second paragraph (hanging indent)
    assert texts |> Enum.drop_while(&(&1 != "a: one")) |> Enum.take(5) == ["a: one", "", "  two", "", "b: three"]
  end

  test "operator messages render pink (:operator); agent messages keep amber author / green body" do
    rows =
      Conversation.render(
        %{title: "t", messages: [%{author: "andrew", body: "ship it"}, %{author: "hronir", body: "on it"}]},
        @rect
      )

    assert style_of(rows, "andrew") == :operator
    assert style_of(rows, "ship it") == :operator
    assert style_of(rows, "hronir") == :label
    assert style_of(rows, "on it") == :normal
  end

  test "no presence data renders just the messages — no indicator row" do
    text =
      %{title: "t", messages: [%{author: "hronir", body: "hi"}]}
      |> Conversation.render(@rect)
      |> lines()
      |> Enum.join("\n")

    refute text =~ "thinking"
    refute text =~ "working"
  end

  test "a thinking agent renders an accent indicator with its ticking elapsed time" do
    rows =
      Conversation.render(
        %{title: "t", messages: [%{author: "hronir", body: "hi"}], thinking: [{"tertius", 192}], working: []},
        @rect
      )

    assert rows |> lines() |> Enum.join("\n") =~ "⋯ tertius is thinking… (3m12s)"
    assert style_of(rows, "is thinking") == :accent
  end

  test "a working (tmux-inferred) agent renders dim; both can show at once" do
    rows =
      Conversation.render(
        %{title: "t", messages: [], thinking: [{"tertius", 5}], working: ["hronir"]},
        @rect
      )

    text = rows |> lines() |> Enum.join("\n")
    assert text =~ "⋯ tertius is thinking… (5s)"
    assert text =~ "⋯ hronir is working…"
    assert style_of(rows, "is working") == :dim
  end

  test "a message with an attachment renders a placeholder row after its body (graphics seam)" do
    rows =
      Conversation.render(
        %{title: "t", messages: [%{author: "a", body: "look", attachment: %{w: 24, h: 6}}]},
        @rect
      )

    assert Console.Graphics.placeholder(24, 6) in rows
  end

  test "a message without an attachment renders no placeholder row" do
    rows = Conversation.render(%{title: "t", messages: [%{author: "a", body: "hi"}]}, @rect)
    refute Enum.any?(rows, &(Enum.map_join(&1, fn {t, _} -> t end) =~ "image"))
  end
end
