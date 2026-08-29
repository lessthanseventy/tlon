defmodule Console.Mouse do
  @moduledoc """
  The pure half of the cockpit's mouse routing (design §8, in the `Keymap`/`View` tradition: the
  decision is a value, the Cockpit interprets it). No TTY, no funes, no PTY — testable headlessly.

    * `hit_panel/3` — which content panel a screen cell lands on (skipping borders + the status
      bar), or `nil`. The Cockpit already has the composed placements (it paints them), so a wheel
      or click is routed to exactly the panel under the cursor — no layout approximation.
    * `clamp_offset/3` — keep a scroll offset within `[0, max(0, content_height - h)]`.
    * `wheel_of/1` — a termbox wheel button → `{direction, step}`.

  The Ghostty forward-vs-scrollback branch for the *center* terminal lives in `Console.Terminal.wheel/5`;
  the per-panel scroll offset lives in the Cockpit's `scrolls` map. This module only decides *where*
  the event goes and *how far*.
  """

  alias Console.Panel.Border
  alias Console.Panel.StatusBar

  # Borders and the status bar are frame/chrome, not content — a hit there is not a panel hit.
  # (Borders' rect is the whole box; the content placement's inset rect is what we want, and it
  # already sits inside the frame, so a cell on the frame matches no content rect.)
  @chrome [Border, StatusBar]

  # Rows per wheel notch — a comfortable default that doesn't leap past a short panel in one tick.
  @wheel_step 3

  @doc """
  Find the content placement whose rect contains `(x, y)`, or `nil`.

  Placements come from `Console.View.compose/3`; content placements carry inset rects (inside the
  border frame), so a hit on the frame itself matches nothing. The first containing rect wins —
  content placements never overlap.
  """
  @spec hit_panel([Console.Board.placement()], non_neg_integer(), non_neg_integer()) ::
          Console.Board.placement() | nil
  def hit_panel(placements, x, y) do
    Enum.find(placements, fn {panel, _data, rect} ->
      panel not in @chrome and contains?(rect, x, y)
    end)
  end

  @doc "Clamp a scroll offset to the valid window `[0, max(0, content_height - h)]`."
  @spec clamp_offset(integer(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  def clamp_offset(offset, content_height, h) do
    offset |> max(0) |> min(max(content_height - h, 0))
  end

  @doc "A termbox wheel button → `{direction, step}` (`:up` is into history / toward the top)."
  @spec wheel_of(:wheel_up | :wheel_down) :: {:up | :down, pos_integer()}
  def wheel_of(:wheel_up), do: {:up, @wheel_step}
  def wheel_of(:wheel_down), do: {:down, @wheel_step}

  @doc """
  An SGR mouse coordinate → a 0-based screen cell. The terminal reports mouse positions
  1-based (SGR `\\e[<b;x;yM`, top-left is `1;1`) and raxol's parser passes them through
  untranslated, while every placement rect from `Console.View` is 0-based — so the cockpit
  normalizes each event's `x`/`y` here before any hit test or local-row math.
  """
  @spec to_cell(pos_integer()) :: non_neg_integer()
  def to_cell(coord), do: max(coord - 1, 0)

  defp contains?(%{x: rx, y: ry, w: rw, h: rh}, x, y), do: x >= rx and x < rx + rw and y >= ry and y < ry + rh
end
