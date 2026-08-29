defmodule Console.Tlon.Focus do
  @moduledoc """
  The Tlön lazygit focus state machine (design: `docs/plans/2026-08-20-tlon-lazygit-panels-design.md`):
  a PURE reducer over where keyboard focus sits — which sidebar column, which pane down that column,
  which section within the pane, and whether we're in the center terminal (which forwards its keys to
  tmux). The Cockpit renders the focus highlight and routes `j/k`/`Enter` to the focused pane off
  this; nothing here touches the TTY.

  The 4-level nav (design §interaction model): `Ctrl+Space` toggles the terminal; `h`/`l` move a pane
  up/down a column; `H`/`L` jump between columns; `Tab` cycles sections within a pane; `j`/`k` move
  the item cursor WITHIN the focused pane. Each pane remembers its own cursor (`cursors` is keyed by
  pane), so moving away and back restores where you were. `Enter` opens the focused selection's
  detail in MAIN (`detail?`), `Esc` closes it; `detail?` is a MODE, not a snapshot — the content is
  always the focused pane's live cursor, so j/k re-resolves the detail as it moves (the lazygit feel).

  `layout` is the shape the reducer navigates:
  `%{left: [pane], right: [pane], sections: %{pane => n}, counts: %{pane => n}}` — `counts` is the
  item count per pane, what j/k clamps against (derived per keypress by the Cockpit from the reads).
  """

  defstruct in_terminal?: true, column: :left, pane: 0, section: 0, cursors: %{}, detail?: false

  @type intent ::
          :toggle_terminal
          | :pane_next
          | :pane_prev
          | :col_left
          | :col_right
          | :section_next
          | :item_next
          | :item_prev
          | :open_detail
          | :close_detail
  @type t :: %__MODULE__{
          in_terminal?: boolean(),
          column: :left | :right,
          pane: non_neg_integer(),
          section: non_neg_integer(),
          cursors: %{optional(atom()) => non_neg_integer()},
          detail?: boolean()
        }

  @doc "Initial focus: in the terminal, keys forwarding to tmux."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The pane key focus currently sits on, per `layout`."
  @spec focused_pane(t(), map()) :: atom() | nil
  def focused_pane(%__MODULE__{column: col, pane: i}, layout), do: Enum.at(column(layout, col), i)

  @doc """
  The focused pane's item cursor, clamped into `[0, count-1]` per `layout.counts` — so a list that
  shrank beneath the stored cursor (a habit approved, a commit GC'd) reads a valid row, never past
  the end. 0 when the pane is empty.
  """
  @spec cursor(t(), map()) :: non_neg_integer()
  def cursor(%__MODULE__{} = s, layout) do
    count = item_count(s, layout)
    if count <= 0, do: 0, else: min(Map.get(s.cursors, focused_pane(s, layout), 0), count - 1)
  end

  @doc "Advance the focus by an intent. A nav intent while in the terminal is a no-op (tmux owns the keys)."
  @spec handle(t(), map(), intent()) :: t()
  def handle(%__MODULE__{} = s, _layout, :toggle_terminal), do: %{s | in_terminal?: not s.in_terminal?}
  def handle(%__MODULE__{in_terminal?: true} = s, _layout, _intent), do: s

  def handle(%__MODULE__{} = s, layout, :pane_next), do: move_pane(s, layout, +1)
  def handle(%__MODULE__{} = s, layout, :pane_prev), do: move_pane(s, layout, -1)
  def handle(%__MODULE__{} = s, layout, :col_right), do: switch_column(s, layout, :right)
  def handle(%__MODULE__{} = s, layout, :col_left), do: switch_column(s, layout, :left)

  # Tab to the next section wraps within the pane and drops the item cursor to the top — each
  # section is its own list (Memory's floor vs habits), so j/k should start fresh, not carry an
  # index that meant something in the previous section.
  def handle(%__MODULE__{} = s, layout, :section_next) do
    pane = focused_pane(s, layout)
    %{s | section: rem(s.section + 1, section_count(s, layout)), cursors: Map.put(s.cursors, pane, 0)}
  end

  def handle(%__MODULE__{} = s, layout, :item_next), do: move_item(s, layout, +1)
  def handle(%__MODULE__{} = s, layout, :item_prev), do: move_item(s, layout, -1)
  def handle(%__MODULE__{} = s, _layout, :open_detail), do: %{s | detail?: true}
  def handle(%__MODULE__{} = s, _layout, :close_detail), do: %{s | detail?: false}

  def handle(%__MODULE__{} = s, _layout, _unknown), do: s

  @doc """
  Jump straight to pane number `digit` (the border-title numbers): 0 = the terminal, left
  column 1..n top-down, right column continuing — implicit nav, section reset. Out-of-range
  digits no-op. Works FROM the terminal too (unlike nav intents) — that's the point.
  """
  @spec jump(t(), map(), non_neg_integer()) :: t()
  def jump(%__MODULE__{} = s, _layout, 0), do: %{s | in_terminal?: true}

  def jump(%__MODULE__{} = s, layout, digit) do
    left = column(layout, :left)
    right = column(layout, :right)

    cond do
      digit <= length(left) ->
        %{s | in_terminal?: false, column: :left, pane: digit - 1, section: 0}

      digit <= length(left) + length(right) ->
        %{s | in_terminal?: false, column: :right, pane: digit - 1 - length(left), section: 0}

      true ->
        s
    end
  end

  # Clamp within the current column (no wrap — h/l is vertical movement, not a carousel); a pane
  # change clears the section.
  defp move_pane(s, layout, delta) do
    max_i = length(column(layout, s.column)) - 1
    pane = min(max(s.pane + delta, 0), max_i)
    %{s | pane: pane, section: if(pane == s.pane, do: s.section, else: 0)}
  end

  # Jump columns, clamping the pane index into the target column's bounds; section clears.
  defp switch_column(s, layout, col) do
    max_i = max(length(column(layout, col)) - 1, 0)
    %{s | column: col, pane: min(s.pane, max_i), section: 0}
  end

  # Move the focused pane's cursor, clamped to its item count (no wrap — a list, not a carousel).
  # The cursor is stored per pane, so each pane keeps its place.
  defp move_item(s, layout, delta) do
    pane = focused_pane(s, layout)
    count = item_count(s, layout)
    cur = Map.get(s.cursors, pane, 0)
    next = if count <= 0, do: 0, else: cur |> Kernel.+(delta) |> max(0) |> min(count - 1)
    %{s | cursors: Map.put(s.cursors, pane, next)}
  end

  defp section_count(s, layout) do
    max(Map.get(layout[:sections] || %{}, focused_pane(s, layout), 1), 1)
  end

  defp item_count(s, layout), do: Map.get(layout[:counts] || %{}, focused_pane(s, layout), 0)

  defp column(layout, :left), do: layout[:left] || []
  defp column(layout, :right), do: layout[:right] || []
end
