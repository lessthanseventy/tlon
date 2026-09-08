defmodule Console.Panel.Memory do
  @moduledoc """
  MEMORY — what server knows, closing the loop with the forgetting engine (design §Memory). A header
  of coverage stats over two navigable sections the focus cycles with `Tab`:

    * **PINNED** — the always-loaded constraint facts (`Server.pinned/0`). `Enter` opens a
      fact's full text in MAIN.
    * **HABITS** — pending habits (`Server.pending_habits/0`) as candidate constraints: `a` approves
      one into the pinned set, `r` rejects it. This is the write-path into memory.

  Data is `%{coverage, pinned: [fact], habits: [habit], section, selected}` — `section` (0=pinned,
  1=habits) and `selected` (the j/k cursor) are injected by the View only when this pane is focused,
  so an unfocused Memory shows the pinned with no cursor. A thin view: no server calls here.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0, rule: 1]

  alias Server.Bus

  @pinned_section 0
  @habits_section 1

  @impl Console.Panel
  def topics(_assigns), do: [Bus.habits_topic()]

  @impl Console.Panel
  def render(nil, rect), do: Console.Panel.clip([line("no recall yet", :dim)], rect)

  def render(%{pinned: pinned, habits: habits} = data, rect) do
    section = Map.get(data, :section, @pinned_section)
    selected = Map.get(data, :selected)

    rows =
      coverage_rows(Map.get(data, :coverage)) ++
        [rule(rect.w)] ++
        pinned_rows(pinned, section == @pinned_section, selected, rect.w) ++
        habit_block(habits, section == @habits_section, selected, rect.w)

    Console.Panel.clip(rows, rect)
  end

  # coverage: "embedded 30/30 · pinned 8 ~1.1k/4k tok · N forgotten" — the corpus at a glance. A
  # forgotten count (facts not embedded, i.e. beyond recall) is derived from facts vs embedded.
  defp coverage_rows(nil), do: [blank()]

  defp coverage_rows(%{facts: facts, embedded: embedded, pinned_count: fc, pinned_tokens: ft, budget: budget}) do
    forgotten = max(facts - embedded, 0)

    [
      [
        {"  embedded ", :dim},
        {"#{embedded}/#{facts}", :normal},
        {" · pinned ", :dim},
        {"#{fc}", :normal},
        {" ~#{tok(ft)}/#{tok(budget)}", :dim},
        {" · ", :dim},
        {"#{forgotten} forgotten", if(forgotten > 0, do: :warm, else: :dim)}
      ]
    ]
  end

  defp tok(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp tok(n), do: "#{n}"

  defp pinned_rows(pinned, active?, selected, w) do
    label = [{"PINNED", section_style(active?)}, {" (#{length(pinned)})", :dim}]

    body =
      case pinned do
        [] -> [line("  —", :dim)]
        facts -> facts |> Enum.with_index() |> Enum.map(fn {f, i} -> fact_row(f, active? and i == selected, w) end)
      end

    [label | body]
  end

  # Empty HABITS collapses to nothing (design 2026-08-23): PINNED takes the space, and the
  # cockpit's section count drops to 1 so Tab can't land on a section that isn't drawn.
  defp habit_block([], _active?, _selected, _w), do: []
  defp habit_block(habits, active?, selected, w), do: [blank() | habit_rows(habits, active?, selected, w)]

  defp habit_rows(habits, active?, selected, w) do
    hint = if active?, do: [{"  a", :accent}, {" approve  ", :dim}, {"r", :accent}, {" reject", :dim}], else: []
    label = [{"HABITS", section_style(active?)}, {" (#{length(habits)})", :dim}]
    body = habits |> Enum.with_index() |> Enum.map(fn {h, i} -> habit_row(h, active? and i == selected, w) end)

    [label | body] ++ [hint]
  end

  # The active section's label lights amber; the dormant one dims, so the eye knows where Tab landed.
  defp section_style(true), do: :label
  defp section_style(false), do: :dim

  defp fact_row(%{text: text}, selected?, w) do
    {gutter, style} = if selected?, do: {"▸ ", :selected}, else: {"  ", :normal}
    [{gutter <> truncate(text, w - 2), style}]
  end

  defp habit_row(%{text: text} = habit, selected?, w) do
    by = Map.get(habit, :proposed_by)
    tag = if is_binary(by), do: " (#{by})", else: ""
    {gutter, style} = if selected?, do: {"▸ ", :selected}, else: {"⋯ ", :dim}
    [{gutter <> truncate(text <> tag, w - 2), style}]
  end

  defp truncate(text, max) when max > 1 do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  defp truncate(text, _max), do: text

  # `s` cycles PINNED/HABITS since the C3.4 reshuffle handed Tab to space-switching.
  @impl Console.Panel
  def hints(_data),
    do: [{"s", "section"}, {"j/k", "facts"}, {"⏎", "open"}, {"y", "text"}, {"d", "forget"}, {"a/r", "habit"}]

  @doc "The semantic yank for the cursor row: section-aware, data carries :section like render/2."
  def yank(%{habits: habits, section: @habits_section}, cursor) do
    case Enum.at(habits, cursor) do
      %{text: text} -> {"habit", text}
      _ -> nil
    end
  end

  def yank(%{pinned: pinned}, cursor) do
    case Enum.at(pinned, cursor) do
      %{text: text} -> {"fact", text}
      _ -> nil
    end
  end

  def yank(_data, _cursor), do: nil
end
