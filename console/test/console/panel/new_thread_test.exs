defmodule Console.Panel.NewThreadTest do
  # The persistent new-thread input band: an idle placeholder, or the live buffer when focused.
  use ExUnit.Case, async: true

  import Console.PanelText, only: [text: 1]

  alias Console.Panel.NewThread

  @rect %{x: 0, y: 0, w: 60, h: 3}

  test "idle: a placeholder inviting a new thread" do
    out = %{input: nil} |> NewThread.render(@rect) |> text()
    assert out =~ "＋"
    assert out =~ "new thread"
  end

  test "focused: the live buffer with a caret" do
    out = %{input: %{kind: :new_thread, buffer: "add redis"}} |> NewThread.render(@rect) |> text()
    assert out =~ "new thread ▸ add redis"
  end

  test "another input kind (e.g. orchestrate) leaves it idle" do
    out = %{input: %{kind: :orchestrate, buffer: "x"}} |> NewThread.render(@rect) |> text()
    assert out =~ "start a new thread"
  end

  test "grows to multiple rows for a multi-line buffer" do
    rows = NewThread.render(%{input: %{kind: :new_thread, buffer: "line one\nline two"}}, @rect)
    assert length(rows) == 2
    assert text(rows) =~ "line one"
    assert text(rows) =~ "line two"
  end

  test "names the project the thread will open on, idle and typing" do
    idle = %{input: nil, project: "excessibility"} |> NewThread.render(@rect) |> text()
    assert idle =~ "start a new thread in excessibility"

    typing = %{input: %{kind: :new_thread, buffer: "fix"}, project: "excessibility"} |> NewThread.render(@rect) |> text()
    assert typing =~ "excessibility ▸ fix"
  end

  test "the wrap width follows the prefix the project makes — the View sizes the band with it" do
    assert NewThread.wrap_width(60, "excessibility") == 60 - String.length("＋ excessibility ▸ ")
    assert NewThread.wrap_width(60, nil) == 60 - String.length("＋ new thread ▸ ")
  end
end
