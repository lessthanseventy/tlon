defmodule Console.Panel.Overview do
  @moduledoc """
  HOME — the god-view **dashboard** (Slice D2, 2026-09-01): a stat row across every workspace, then
  one **boxed card per workspace** (framed in the workspace's identity hue) showing its open/stalled/
  done tally as status dots + its top few threads (status dot · title · lead). The per-thread rollup
  rows `Console.Orbis.rollup/0` computes were previously discarded — this surfaces them.

  `Enter` (keymap, `orbis_focus == :survey`) or a click zooms to the card's own workspace id. Data is
  `%{workspaces: [%{id, name, summary, leaves}], survey_cursor, orbis_focus}`; each `summary` is
  `%{open, stalled, done, conflicts}` and each `leaves` entry `%{id, title, lead, status, …}`.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  alias Console.Card

  @header_rows 3
  @threads_shown 4

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{workspaces: workspaces} = data, rect) do
    cursor = if Map.get(data, :orbis_focus) == :survey, do: Map.get(data, :survey_cursor)
    w = rect.w

    body =
      case workspaces do
        [] -> [line("  no workspaces yet — press n to create one", :dim)]
        list -> list |> Enum.with_index() |> Enum.flat_map(fn {ws, i} -> card(ws, i == cursor, w) ++ [blank()] end)
      end

    Console.Panel.clip(header(workspaces) ++ body, rect)
  end

  # A click resolves to the workspace whose card covers `local_y` — walk the real (variable) card
  # heights, exactly as render lays them out, since a card's height depends on its thread count.
  @impl Console.Panel
  def pick(%{workspaces: workspaces} = data, rect, local_y) do
    target = Console.Panel.scroll_offset(data) + local_y - @header_rows

    workspaces
    |> Enum.reduce_while({0, nil}, fn ws, {offset, _} ->
      height = length(card(ws, false, rect.w)) + 1

      if target >= offset and target < offset + height,
        do: {:halt, {offset, {:switch_space, ws.id}}},
        else: {:cont, {offset + height, nil}}
    end)
    |> elem(1)
  end

  def pick(_data, _rect, _local_y), do: nil

  # -- rendering ------------------------------------------------------------

  defp header(workspaces) do
    totals =
      Enum.reduce(workspaces, %{open: 0, stalled: 0, done: 0}, fn ws, acc ->
        %{open: acc.open + ws.summary.open, stalled: acc.stalled + ws.summary.stalled, done: acc.done + ws.summary.done}
      end)

    count = length(workspaces)
    [[{"HOME", :header}, {"  across #{count} workspace#{plural(count)}", :dim}], tally_row(totals), blank()]
  end

  defp card(ws, selected?, w) do
    frame = Card.workspace_hue(ws)
    title_style = if selected?, do: :selected, else: :label
    body = [tally_row(ws.summary)] ++ thread_rows(ws.leaves)
    Card.boxed_card(ws.name, body, w, frame, title_style)
  end

  # A tally as three status dots — the signal tier at a glance. Zeroes stay dim so a clean workspace
  # reads clean; the dot still carries the colour so the eye finds trouble (stalled = red) instantly.
  defp tally_row(%{open: o, stalled: s, done: d}) do
    [
      Card.status_dot(:open),
      {" #{o} open   ", :dim},
      Card.status_dot(:stalled),
      {" #{s} stalled   ", :dim},
      Card.status_dot(:done),
      {" #{d} done", :dim}
    ]
  end

  defp thread_rows(leaves) do
    shown = Enum.take(leaves, @threads_shown)

    rows =
      Enum.map(shown, fn l ->
        [Card.status_dot(l.status), {" ", :normal}, {l.title, :normal}, {"  ", :normal}, {l.lead || "—", :dim}]
      end)

    case length(leaves) - length(shown) do
      more when more > 0 -> rows ++ [[{"+#{more} more", :dim}]]
      _ -> rows
    end
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"
end
