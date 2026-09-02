defmodule Console.Panel do
  @moduledoc """
  A panel is a component; a view is a composition of panels; nothing is a prebaked
  full-screen template (design §3). A panel is a **thin view over a server read model**
  and holds no logic of its own:

    - `topics/1` — the server Bus topics whose events should re-render this panel.
    - `render/2` — turn the panel's data into styled rows, clipped to its rect.

  A panel renders **styled rows**: `render/2` returns `[row]`, where a `row` is a list of
  `{text, style}` runs (`style` a semantic atom resolved by `Console.Style`). Rows are plain
  data — a panel is a pure function `(server read, rect) → rows`, so the whole render path is
  headlessly testable and the same panel can later paint in a LiveView (§7).
  """

  @type style :: atom()
  @type run :: {String.t(), style()}
  @type row :: [run()]
  @type rect :: %{x: non_neg_integer(), y: non_neg_integer(), w: pos_integer(), h: pos_integer()}

  @doc "The server Bus topics whose events should re-render this panel (may depend on assigns like the focused thread)."
  @callback topics(assigns :: map()) :: [String.t()]

  @doc "Render the panel's data into styled rows, clipped to the rect."
  @callback render(data :: term(), rect()) :: [row()]

  @doc """
  Map a click at terminal-local row `local_y` (already scroll-adjusted: the panel adds its
  `:scroll` offset to land on a content row) to a selection action, or `nil` if nothing
  selectable is there. Optional — only list panels that select-on-click implement it.

  Actions the Cockpit understands: `{:focus_thread, id}`, `{:switch_space, key}`.
  """
  @callback pick(data :: term(), rect(), local_y :: non_neg_integer()) :: term() | nil

  @doc "The pane's footer verbs as `{keycap, label}` pairs — the contextual footer's third segment."
  @callback hints(data :: term()) :: [{String.t(), String.t()}]

  @doc "Image placements to draw over this panel's rect (kitty hosts) — `%{id, data, rect}`s."
  @callback images(data :: term(), rect()) :: [map()]

  @optional_callbacks [pick: 3, hints: 1, images: 2]

  @doc "A one-run row in a given style — the common case."
  @spec line(String.t(), style()) :: row()
  def line(text, style \\ :normal), do: [{text, style}]

  @doc "A blank spacer row."
  @spec blank() :: row()
  def blank, do: []

  @doc """
  A horizontal rule: a row of `─` `w` graphemes wide, in `:separator` style — the section
  divider inside a panel's own body (distinct from `Panel.Rule`, the `│` gutter BETWEEN panels).
  Width is fixed at build time since `clip/2` truncates by width anyway, not measured against
  the caller's rect — pass the panel's content width (rect.w, or a narrower column width).
  """
  @spec rule(pos_integer()) :: row()
  def rule(w) when w > 0, do: [{String.duplicate("─", w), :separator}]
  def rule(_w), do: []

  # A tall stand-in for "unclipped height" — panels render into this then we window the rows.
  # 10k covers any realistic panel (a dossier, a long chat) without allocating meaningfully more.
  @max_rows 10_000

  @doc """
  Clip rows to a rect: at most `h` rows, each truncated to `w` graphemes across its runs.
  Truncation walks runs left-to-right, keeping whole runs until the width budget is spent
  and slicing the run that straddles the edge.
  """
  @spec clip([row()], rect()) :: [row()]
  def clip(rows, %{w: w, h: h}) do
    rows
    |> Enum.take(h)
    |> Enum.map(&clip_row(&1, w))
  end

  @doc """
  Render a panel for `rect`, applying a scroll window when its data carries a `:scroll` offset.

  Scrollable panels (declared by `Console.View` injecting `:scroll` into their data) are rendered
  UNclipped in height — `render/2` is called with a tall rect so `clip/2` keeps every row — then
  the window `[offset, offset + h)` is taken. Panels whose data has no `:scroll` render exactly as
  before, so non-scrollable panels (Terminal, StatusBar, Border) and `nil` data are unaffected.
  """
  @spec render_scroll(module(), term(), rect()) :: [row()]
  # Unscrolled (the common case, every tick): render straight into the real rect — no tall
  # render, no windowing, exactly the pre-scroll cost.
  def render_scroll(panel, %{scroll: 0} = data, rect), do: panel.render(data, rect)

  # Scrolled: render tall, then window. The offset is re-clamped here because content can
  # shrink between wheel events (a thread closes, the feed compacts) and the stored offset
  # would otherwise window past the end — a blank panel until the next wheel event.
  def render_scroll(panel, %{scroll: offset} = data, rect) do
    rows = panel.render(data, %{rect | h: @max_rows})

    rows
    |> Enum.drop(min(offset, max(length(rows) - rect.h, 0)))
    |> Enum.take(rect.h)
  end

  def render_scroll(panel, data, rect), do: panel.render(data, rect)

  @doc "Whether a panel's data carries a scroll offset (injected by `Console.View` for scrollable panels)."
  @spec scrollable?(term()) :: boolean()
  def scrollable?(data), do: is_map(data) and Map.has_key?(data, :scroll)

  @doc """
  Full content height (rows) at width `w` — the bound for clamping a scroll offset. Renders the
  panel unclipped in height and counts the rows; one extra render, called only on a wheel event.
  """
  @spec content_height(module(), term(), pos_integer()) :: non_neg_integer()
  def content_height(panel, data, w) do
    length(panel.render(data, %{x: 0, y: 0, w: w, h: @max_rows}))
  end

  @doc """
  Route a click to a panel's `pick/3` if it implements it, else `nil`. `local_y` is the
  terminal-local row inside the panel's content rect; the panel adds its own `:scroll` offset.
  """
  @spec pick(module(), term(), rect(), non_neg_integer()) :: term() | nil
  def pick(panel, data, rect, local_y) do
    if function_exported?(panel, :pick, 3), do: panel.pick(data, rect, local_y)
  end

  @doc "A panel's declared footer verbs, or [] — `hints/1` is optional."
  @spec hints(module(), term()) :: [{String.t(), String.t()}]
  def hints(panel, data) do
    # function_exported?/3 is false for an unloaded module (it does NOT load it) — a panel that
    # hasn't rendered yet this VM would silently read as hint-less without this.
    Code.ensure_loaded?(panel)
    if function_exported?(panel, :hints, 1), do: panel.hints(data) || [], else: []
  end

  @doc "A panel's image placements, or [] — `images/2` is optional (same load-first footgun as hints/2)."
  @spec images(module(), term(), rect()) :: [map()]
  def images(panel, data, rect) do
    Code.ensure_loaded?(panel)
    if function_exported?(panel, :images, 2), do: panel.images(data, rect) || [], else: []
  end

  @doc "The scroll offset a panel's data carries (0 when unscrolled or not scrollable)."
  @spec scroll_offset(term()) :: non_neg_integer()
  def scroll_offset(%{scroll: n}), do: n
  def scroll_offset(_data), do: 0

  defp clip_row(_runs, w) when w <= 0, do: []

  defp clip_row(runs, w) do
    {kept, _left} =
      Enum.reduce_while(runs, {[], w}, fn {text, style}, {acc, left} ->
        len = String.length(text)

        cond do
          left <= 0 -> {:halt, {acc, 0}}
          len <= left -> {:cont, {[{text, style} | acc], left - len}}
          true -> {:halt, {[{String.slice(text, 0, left), style} | acc], 0}}
        end
      end)

    Enum.reverse(kept)
  end

  @doc "Total grapheme width of a row's runs."
  @spec row_width(row()) :: non_neg_integer()
  def row_width(runs), do: Enum.reduce(runs, 0, fn {t, _}, acc -> acc + String.length(t) end)

  @doc """
  Pad a row with trailing spaces (in `style`) out to `w` graphemes — used to extend a
  selection's background across the full column width.
  """
  @spec pad(row(), non_neg_integer(), style()) :: row()
  def pad(runs, w, style) do
    gap = w - row_width(runs)
    if gap > 0, do: runs ++ [{String.duplicate(" ", gap), style}], else: runs
  end
end
