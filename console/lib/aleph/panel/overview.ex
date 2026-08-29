defmodule Console.Panel.Overview do
  @moduledoc """
  ORBIS — the **survey**: Orbis' center, one row per WORKSPACE. Each workspace row shows its name and the
  leads/open/stalled/done/trouble rollup for all its leaves — the god-view glance the operator
  opens on. `Enter` (keymap, `orbis_focus == :survey`) or a click zooms to the row's OWN workspace id
  (D0.2 — no more a single hardcoded lens). Data is `%{workspaces: [%{id, name, summary, leaves}],
  survey_cursor, orbis_focus}` — `workspaces` from `Console.Orbis.rollup/0`'s `workspaces` key (an empty list
  when funes is down / there are no workspaces); `survey_cursor`/`orbis_focus` (View-injected, D0.3)
  wash the cursor row `:selected`, only while the survey (not the thread list) has focus.

  Was a per-thread message feed (`Server.Channel.chorus/1`); re-pointed to workspaces in the Slice 0
  collapse so the survey surveys workspaces, not threads. The per-thread rollup still lives in the
  LEAVES sidebar (`Console.Panel.Leaves`), whose `summary_row/1` this reuses so the two never drift.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  alias Console.Panel.Leaves

  # Header (title) + blank spacer above the workspace rows; each workspace block is head + summary + blank.
  @header_rows 2
  @workspace_rows 3

  # The cockpit already subscribes to ALL activity events, so the survey repaints on any thread's
  # activity — no per-thread topic needed.
  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{workspaces: workspaces} = data, rect) do
    header = [line("ORBIS · workspaces", :header), blank()]
    # Only wash a row :selected while the SURVEY (not the thread list) has focus — D0.3.
    cursor = if Map.get(data, :orbis_focus) == :survey, do: Map.get(data, :survey_cursor)

    body =
      case workspaces do
        [] -> [line("no workspaces yet", :dim)]
        ws -> ws |> Enum.with_index() |> Enum.flat_map(fn {w, i} -> workspace_rows(w, i == cursor) end)
      end

    Console.Panel.clip(header ++ body, rect)
  end

  # Click a workspace's rows → zoom to ITS id (D0.2). The header + blank (rows 0–1) and clicks past
  # the last workspace are inert.
  @impl Console.Panel
  def pick(%{workspaces: workspaces} = data, _rect, local_y) do
    idx = Console.Panel.scroll_offset(data) + local_y - @header_rows
    workspace_at(workspaces, idx)
  end

  def pick(_data, _rect, _local_y), do: nil

  # Every workspace block is a fixed @workspace_rows tall, so idx→workspace is plain integer division; a
  # wrapping/variable-height summary would need to measure each block's rendered height instead.
  defp workspace_at(workspaces, idx) when idx >= 0 do
    case Enum.at(workspaces, div(idx, @workspace_rows)) do
      %{id: id} -> {:switch_space, id}
      nil -> nil
    end
  end

  defp workspace_at(_workspaces, _idx), do: nil

  # One workspace: a ▸ + its name (washed :selected under the survey cursor), then an indented summary
  # line — leaf count + the shared rollup line (open/stalled/done, trouble called out only when
  # there is any), then a blank spacer.
  defp workspace_rows(%{name: name, summary: summary, leaves: leaves}, selected?) do
    name_style = if selected?, do: :selected, else: :header
    head = [{"▸ ", :accent}, {name, name_style}]
    count = length(leaves)
    summary_line = [{"  #{count} #{leaf_word(count)} · ", :dim} | Leaves.summary_row(summary)]
    [head, summary_line, blank()]
  end

  defp leaf_word(1), do: "leaf"
  defp leaf_word(_n), do: "leaves"
end
