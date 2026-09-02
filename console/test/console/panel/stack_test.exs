defmodule Console.Panel.StackTest do
  # The Commits pane (Stack panel): the j/k selection highlight. The git/branch plumbing is
  # Console.Stack's; this pins that a `selected` index lights exactly one commit's subject row.
  use ExUnit.Case, async: true

  alias Console.Panel.Stack

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp commit(hash, subject),
    do: %{hash: hash, subject: subject, relative: "1 minute ago", date: "Aug 20 13:00", author: "T", agent?: false}

  defp base(commits, extra \\ %{}) do
    Map.merge(
      %{branch: "main", dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: commits, files: []},
      extra
    )
  end

  # The style each subject row is drawn in (the row whose text ends with the subject).
  defp subject_style(rows, subject) do
    Enum.find_value(rows, fn row ->
      case row do
        [{text, style}] -> if String.contains?(text, subject), do: style
        _ -> nil
      end
    end)
  end

  test "with no selection, no subject row is :selected" do
    rows = Stack.render(base([commit("a1", "first"), commit("b2", "second")]), @rect)
    assert subject_style(rows, "first") == :normal
    assert subject_style(rows, "second") == :normal
  end

  test "the selected index lights that commit's subject with a ▸ gutter" do
    rows = Stack.render(base([commit("a1", "first"), commit("b2", "second")], %{selected: 1}), @rect)
    assert subject_style(rows, "second") == :selected
    assert subject_style(rows, "first") == :normal

    assert Enum.any?(rows, fn
             [{text, :selected}] -> String.starts_with?(text, "▸ ")
             _ -> false
           end)
  end

  test "hints/1 declares the pane's footer verbs" do
    assert Console.Panel.hints(Stack, %{}) == [{"j/k", "commits"}, {"⏎", "diff"}, {"y", "sha"}]
  end

  test "a panel without hints/1 declares nothing" do
    assert Console.Panel.hints(Console.Panel.Health, %{}) == []
  end

  test "yank/2 returns the cursor commit's full sha" do
    data = base([commit("abc123", "s")])
    assert Stack.yank(data, 0) == {"sha abc123", "abc123"}
    assert Stack.yank(data, 9) == nil
    assert Stack.yank(nil, 0) == nil
  end
end
