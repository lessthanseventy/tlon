defmodule Console.Panel.MemoryTest do
  # The Memory pane: coverage header + PINNED/HABITS sections, the active section (Tab) and the j/k
  # cursor lit. A thin view; funes reads are the cockpit's. Pins the panel → styled-rows path.
  use ExUnit.Case, async: true

  import Console.PanelText, only: [lines: 1]

  alias Console.Panel.Memory

  @rect %{x: 0, y: 0, w: 60, h: 100}

  defp fact(text),
    do: %{text: text, kind: "constraint", provenance: "stated", check_cmd: nil, incident: nil, taught: nil}

  defp habit(text, by), do: %{text: text, proposed_by: by, rationale: nil, id: 1}

  defp coverage, do: %{facts: 30, embedded: 23, pinned_count: 8, pinned_tokens: 1100, budget: 4000, model: "m"}

  defp data(extra \\ %{}) do
    Map.merge(
      %{coverage: coverage(), pinned: [fact("prefer X"), fact("never Y")], habits: [habit("do Z", "glm")]},
      extra
    )
  end

  defp style_of(rows, needle) do
    Enum.find_value(rows, fn
      [{t, s}] -> if String.contains?(t, needle), do: s
      _ -> nil
    end)
  end

  test "nil data renders a placeholder, no crash" do
    assert nil |> Memory.render(@rect) |> lines() |> Enum.any?(&(&1 == "no recall yet"))
  end

  test "coverage header shows embedded/pinned/forgotten" do
    joined = Enum.join(lines(Memory.render(data(), @rect)), "\n")
    assert joined =~ "embedded 23/30"
    assert joined =~ "pinned 8"
    assert joined =~ "7 forgotten"
  end

  test "with the PINNED section active, the selected fact lights with a ▸ gutter" do
    rows = Memory.render(data(%{section: 0, selected: 1}), @rect)
    assert style_of(rows, "never Y") == :selected
    assert style_of(rows, "prefer X") == :normal
  end

  test "with the HABITS section active, the selected habit lights and the a/r hint shows" do
    rows = Memory.render(data(%{section: 1, selected: 0}), @rect)
    joined = Enum.join(lines(rows), "\n")
    assert style_of(rows, "do Z") == :selected
    assert joined =~ "approve"
    assert joined =~ "reject"
  end

  test "an unfocused Memory (no section/selected) shows the pinned with no cursor" do
    rows = Memory.render(data(), @rect)
    refute Enum.any?(lines(rows), &String.starts_with?(&1, "▸"))
  end

  test "an empty HABITS section collapses to nothing — no label, no dash" do
    data = %{coverage: nil, pinned: [%{text: "a fact"}], habits: []}
    rows = Memory.render(data, %{x: 0, y: 0, w: 40, h: 20})
    texts = Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _} -> t end) end)

    refute Enum.any?(texts, &String.contains?(&1, "HABITS"))
    # no trailing blank+placeholder either: the pinned takes the space
    refute List.last(texts) == "  —"
  end

  test "hints/1 names the s-keyed section cycle (Tab now switches spaces, not sections)" do
    assert Console.Panel.hints(Memory, %{}) == [
             {"s", "section"},
             {"j/k", "facts"},
             {"⏎", "open"},
             {"y", "text"},
             {"d", "forget"},
             {"a/r", "habit"}
           ]
  end

  test "yank/2 is section-aware: pinned text in PINNED, habit text in HABITS" do
    assert Memory.yank(Map.put(data(), :section, 0), 0) == {"fact", "prefer X"}
    assert Memory.yank(Map.put(data(), :section, 1), 0) == {"habit", "do Z"}
    assert Memory.yank(data(), 9) == nil
    assert Memory.yank(nil, 0) == nil
  end
end
