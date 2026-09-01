defmodule Console.Panel.NewThreadTest do
  # The persistent new-thread input band: an idle placeholder, or the live buffer when focused.
  use ExUnit.Case, async: true

  alias Console.Panel.NewThread

  @rect %{x: 0, y: 0, w: 60, h: 3}

  defp text(rows), do: Enum.map_join(rows, "\n", fn row -> Enum.map_join(row, fn {t, _s} -> t end) end)

  test "idle: a placeholder inviting a new thread" do
    out = NewThread.render(%{input: nil}, @rect) |> text()
    assert out =~ "＋"
    assert out =~ "new thread"
  end

  test "focused: the live buffer with a caret" do
    out = NewThread.render(%{input: %{kind: :new_thread, buffer: "add redis"}}, @rect) |> text()
    assert out =~ "new thread ▸ add redis"
  end

  test "another input kind (e.g. orchestrate) leaves it idle" do
    out = NewThread.render(%{input: %{kind: :orchestrate, buffer: "x"}}, @rect) |> text()
    assert out =~ "start a new thread"
  end
end
