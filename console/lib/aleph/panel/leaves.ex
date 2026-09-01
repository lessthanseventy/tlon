defmodule Console.Panel.Leaves do
  @moduledoc """
  THREADS (reshape slice C; module name pending the surface-rename slice) — the machine-scoped
  **unified thread list**: chat threads and TRACKED threads are one list. A header count line
  (open / stalled / done, with conflicts called out) then one row per thread — lead + status,
  and on a tracked row its stage chip, a ⏸ gate when parked on the operator, and the failing
  check when verify is red. The glance-value summary the operator reads without switching tabs.

  Navigable in Tlön nav mode: `j/k` selects a leaf (the cursor row washes :selected), `Enter`
  attaches that leaf in the Workspace center — re-points the tmux window (Slice 0 collapse; was a jump
  into the now-deleted Sessions space); its own `t<id>` window if live, else its lead's (C3.3). Data
  is `%{summary: %{open, stalled, done, conflicts}, rows: [%{id, title, lead, status, conflicts,
  workspace_id, stage, awaiting, blocking}], selected, attached}` (the last four nil on a plain chat
  thread) — `selected` (cursor) and `attached` (the leaf whose own window IS the
  center, persistent) both injected by the View, either `nil`; either washes the row :selected — or
  `nil` when server is down / there are no machine threads. Pure over `Console.Orbis.rollup/0`.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  alias Server.Bus

  # The header chrome above the leaf rows: the rollup line, blank (title now lives on the frame).
  @header_rows 2

  @impl Console.Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Console.Panel
  def render(nil, rect) do
    Console.Panel.clip([line("no machine threads", :dim)], rect)
  end

  def render(%{summary: summary, rows: rows} = data, rect) do
    selected = Map.get(data, :selected)
    attached = Map.get(data, :attached)
    rows = ordered(rows, Map.get(data, :focused_lead))
    header = [summary_row(summary), blank()]

    body =
      if rows == [],
        do: [line("all clear", :dim)],
        else:
          rows
          |> Enum.with_index()
          |> Enum.map(fn {row, i} -> leaf_row(row, i == selected or row.id == attached, rect.w) end)

    Console.Panel.clip(header ++ body, rect)
  end

  # Click a leaf row → focus that thread (so composing targets it). The header rows are inert.
  # Uses the SAME `ordered/2` as render so a click lands on the row the operator sees (C3.2).
  @impl Console.Panel
  def pick(%{rows: _} = data, _rect, local_y) do
    case row_at(data, local_y - @header_rows) do
      %{id: id} -> {:focus_thread, id}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  @doc """
  The rollup row under `index` in the ON-SCREEN order — the one `ordered/2` reorder render, pick,
  yank, and the cockpit's attach/preview all index by, so a cursor can never land on a different
  row than the paint highlighted. nil off the list, below the header, or on nil data.
  """
  def row_at(%{rows: rows} = data, index) when is_integer(index) and index >= 0,
    do: Enum.at(ordered(rows, Map.get(data, :focused_lead)), index)

  def row_at(_data, _index), do: nil

  # C3.2: float the focused leader's leaves to the top, stable within each group (split_with keeps
  # source order), so the active leader owns the top of the panel. `focused_lead` = the active
  # WindowBar tab's agent handle, injected by the View; nil (no leader active) → source order.
  defp ordered(rows, nil), do: rows

  defp ordered(rows, focused_lead) do
    {mine, others} = Enum.split_with(rows, &(&1.lead == focused_lead))
    mine ++ others
  end

  @doc """
  The rollup line as a styled row: the operator's three buckets, conflicts appended only when there
  are any — a clean board reads clean, and a cut without a count would be its own little lie. Public
  so the Home/Orbis survey shares the identical line, not a hand-rolled copy that could drift.
  """
  @spec summary_row(map()) :: Console.Panel.row()
  def summary_row(%{open: open, stalled: stalled, done: done} = summary) do
    base = [
      {"#{open} open", :normal},
      {" · ", :dim},
      {"#{stalled} stalled", stalled_style(stalled)},
      {" · ", :dim},
      {"#{done} done", :dim}
    ]

    case summary[:conflicts] || 0 do
      0 -> base
      n -> base ++ [{" · ", :dim}, {"#{n} conflicts", :label}]
    end
  end

  defp stalled_style(0), do: :normal
  defp stalled_style(_n), do: :label

  # One thread: a status glyph, the title, and the lead; a stalled row trails its conflict count.
  # A TRACKED row (reshape slice C: stage non-nil — chat and tracked are one list) appends its
  # stage chip, a ⏸ gate when parked on the operator, and the failing check when verify is red.
  # The selected row (j/k) washes :selected so the eye lands on which Enter would jump to.
  defp leaf_row(%{title: title, lead: lead, status: status} = row, selected?, _w) do
    {glyph, glyph_style} = status_glyph(status)
    who = if lead && lead != "", do: lead, else: "?"
    title_style = if selected?, do: :selected, else: :normal

    base = [{glyph, glyph_style}, {title || "untitled", title_style}, {" · ", :dim}, {who, :accent}]

    base = base ++ stage_chips(row)

    case {status, row[:conflicts] || 0} do
      {:stalled, n} when n > 0 -> base ++ [{" · ", :dim}, {"#{n}⚠", :label}]
      _ -> base
    end
  end

  defp stage_chips(row) do
    chip = if stage = row[:stage], do: [{" · ", :dim}, {stage, :accent}], else: []
    gate = if awaiting = row[:awaiting], do: [{" ⏸ awaiting #{awaiting}", :label}], else: []

    warn =
      case row[:blocking] do
        %{cmd: cmd, tail: tail} -> [{" ⚠ #{cmd} — #{tail}", :warm}]
        _ -> []
      end

    chip ++ gate ++ warn
  end

  defp status_glyph(:stalled), do: {"▲ ", :label}
  defp status_glyph(:done), do: {"✓ ", :dim}
  defp status_glyph(_open), do: {"▸ ", :accent}

  @impl Console.Panel
  def hints(_data), do: [{"j/k", "leaves"}, {"⏎", "attach"}, {"y", "title"}, {"d", "delete"}]

  @doc "The semantic yank for the cursor row: the leaf title, same float order as render/pick."
  def yank(data, cursor) do
    case row_at(data, cursor) do
      %{title: title} when is_binary(title) -> {"title", title}
      _ -> nil
    end
  end
end
