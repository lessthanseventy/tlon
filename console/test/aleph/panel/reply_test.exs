defmodule Console.Panel.ReplyTest do
  # The persistent per-thread reply band: born focused (no idle placeholder), the live buffer + caret.
  use ExUnit.Case, async: true

  alias Console.Panel.Reply

  @rect %{x: 0, y: 0, w: 60, h: 3}

  defp text(rows), do: Enum.map_join(rows, "\n", fn row -> Enum.map_join(row, fn {t, _s} -> t end) end)

  test "renders the reply prompt with the thread id and the live buffer" do
    out = %{input: %{kind: :reply, thread_id: 7, buffer: "on it"}} |> Reply.render(@rect) |> text()
    assert out =~ "reply to #7"
    assert out =~ "on it"
  end

  test "shows a caret (it is always focused)" do
    out = %{input: %{kind: :reply, thread_id: 7, buffer: ""}} |> Reply.render(@rect) |> text()
    assert out =~ "▎"
  end

  test "grows to multiple rows for a multi-line buffer" do
    rows = Reply.render(%{input: %{kind: :reply, thread_id: 7, buffer: "line one\nline two"}}, @rect)
    assert length(rows) == 2
    assert text(rows) =~ "line one"
    assert text(rows) =~ "line two"
  end
end
