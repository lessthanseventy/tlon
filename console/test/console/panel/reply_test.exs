defmodule Console.Panel.ReplyTest do
  # The persistent per-thread reply band: born focused (no idle placeholder), the live buffer, and
  # the caret whenever the box actually has the keys.
  use ExUnit.Case, async: true

  import Console.PanelText, only: [text: 1]

  alias Console.Panel.Reply

  @rect %{x: 0, y: 0, w: 60, h: 3}

  test "renders the reply prompt with the thread id and the live buffer" do
    out = %{input: %{kind: :reply, thread_id: 7, buffer: "on it"}} |> Reply.render(@rect) |> text()
    assert out =~ "reply to #7"
    assert out =~ "on it"
  end

  test "shows a caret — the box is born focused with the thread" do
    out = %{input: %{kind: :reply, thread_id: 7, buffer: ""}} |> Reply.render(@rect) |> text()
    assert out =~ "▎"
  end

  test "with the drawer open the caret goes but the draft stays — the keys are the drawer's" do
    data = %{input: %{kind: :reply, thread_id: 7, buffer: "half typed"}, drawer: :stack}
    out = data |> Reply.render(@rect) |> text()

    assert out =~ "half typed"
    refute out =~ "▎"
  end

  test "grows to multiple rows for a multi-line buffer" do
    rows = Reply.render(%{input: %{kind: :reply, thread_id: 7, buffer: "line one\nline two"}}, @rect)
    assert length(rows) == 2
    assert text(rows) =~ "line one"
    assert text(rows) =~ "line two"
  end

  test "a trailing space shows — the box renders what was typed, not a re-flowed paragraph" do
    out = %{input: %{kind: :reply, thread_id: 7, buffer: "on it "}} |> Reply.render(@rect) |> text()
    assert out =~ "on it ▎"
  end

  test "a double space survives" do
    out = %{input: %{kind: :reply, thread_id: 7, buffer: "on  it"}} |> Reply.render(@rect) |> text()
    assert out =~ "on  it"
  end
end
