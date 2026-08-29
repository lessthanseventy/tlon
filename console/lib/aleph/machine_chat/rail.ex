defmodule Console.MachineChat.Rail do
  @moduledoc """
  The left THREADS rail — one row per machine thread, Slack-channel-style: a liveness glyph
  (● working / ● live / ○ no session / ✓ closed), the title, and an unread badge. Pure rows from
  pre-annotated data `%{rows: [%{id, title, state, status, unread}], selected_id}`; the loop
  annotates (Host order + Presence status), this renders and windows around the selection so the
  selected thread is always on screen.
  """

  import Console.Panel, only: [blank: 0]

  @doc "The rail's rows, windowed to `rect.h` with the selection kept visible."
  @spec render(map(), map()) :: [[{String.t(), term()}]]
  def render(%{rows: rows, selected_id: selected_id}, rect) do
    header = [[{"THREADS", :header}], blank()]
    budget = max(rect.h - length(header), 1)
    selected_index = Enum.find_index(rows, &(&1.id == selected_id)) || 0

    body =
      rows
      |> window(selected_index, budget)
      |> Enum.map(&row(&1, &1.id == selected_id, rect.w))

    header ++ body
  end

  # Keep the selection inside the visible slice: scroll the slice, not the selection.
  @doc false
  def window(rows, selected_index, budget) do
    start = selected_index |> Kernel.-(budget - 1) |> max(0) |> min(max(length(rows) - budget, 0))
    # Prefer showing from the top until the selection would fall off the bottom.
    start = if selected_index < budget, do: 0, else: start
    rows |> Enum.drop(start) |> Enum.take(budget)
  end

  defp row(%{title: title, state: state, status: status, unread: unread} = r, selected?, w) do
    {glyph, glyph_style} = glyph(state, status)
    badge = if unread > 0, do: " •#{min(unread, 99)}", else: ""
    {chip_text, chip_style} = stage_chip(r)
    title_style = title_style(selected?, state)
    text = clip(title || "untitled", w - 2 - String.length(badge) - String.length(chip_text))

    [{glyph <> " ", glyph_style}, {text, title_style}] ++
      if(badge == "", do: [], else: [{badge, :accent}]) ++
      if(chip_text == "", do: [], else: [{chip_text, chip_style}])
  end

  # A workline row wears its stage; a parked gate outranks it — the operator's cue.
  defp stage_chip(%{awaiting: awaiting}) when not is_nil(awaiting), do: {" ⏸gate", :warm}
  defp stage_chip(%{stage: stage}) when is_binary(stage), do: {" ·#{stage}", :dim}
  defp stage_chip(_row), do: {"", :dim}

  defp glyph("closed", _status), do: {"✓", :dim}
  defp glyph(_state, :working), do: {"●", :accent}
  defp glyph(_state, :live), do: {"●", :dim}
  defp glyph(_state, :none), do: {"○", :dim}

  defp title_style(true, _state), do: :selected
  defp title_style(false, "closed"), do: :dim
  defp title_style(false, _state), do: :normal

  defp clip(text, max) when max < 1, do: String.slice(text, 0, 1)

  defp clip(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end
end
