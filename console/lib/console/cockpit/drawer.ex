defmodule Console.Cockpit.Drawer do
  @moduledoc """
  The drawer (design 2026-09-08 §2, "depth on demand"): the panes that used to line the left rail —
  NOW · CREW · MEMORY · STACK · ROSTER · TRIAGE · TICKETS · NOTES · HEALTH — as ONE overlay over the
  centre. `Alt+d` opens it on the pane it last showed, `Esc` closes it; `1`-`9` and `h`/`l` walk the
  tab strip.

  It covers everything right of the rail, between the two bars — the conversation AND the session
  pane — and never the rail or the bars: where you are stays on screen while you go deep. The
  drawer is PAINT, not layout: `Console.View.center_rect/4` and `session_rect/3` are untouched, so
  the PTYs underneath keep their size and don't reflow when it opens.

  Pure but for the two board panes, whose rows come from the server exactly as the full-screen
  boards read them (`Console.Cockpit.Boards`).
  """

  alias Console.Cockpit.Boards
  alias Console.Panel
  alias Console.Reads
  alias Console.Tlon.Focus
  alias Console.View

  # The tab strip, in order. One atom, one panel — the pane key is what `state.drawer` holds and
  # what `Alt+d` restores.
  @panes [
    now: Panel.Activity,
    crew: Panel.Crew,
    memory: Panel.Memory,
    stack: Panel.Stack,
    roster: Panel.Roster,
    triage: Panel.Triage,
    tickets: Panel.TicketBoard,
    notes: Panel.NoteBoard,
    health: Panel.Health
  ]

  # Only keys the drawer itself binds — the strip is walkable and closable, nothing more is claimed
  # here (each pane's own verbs come from its `Console.Panel.hints/1`, in the footer).
  @hint "1-9·h/l pane · esc close"

  @doc "The pane table: `[{key, panel}]`, in tab order."
  @spec panes() :: keyword(module())
  def panes, do: @panes

  @doc "The panel a pane key renders, or nil for an unknown key."
  @spec panel(atom()) :: module() | nil
  def panel(key), do: Keyword.get(@panes, key)

  @doc "The pane keys, in tab order."
  @spec keys() :: [atom()]
  def keys, do: Keyword.keys(@panes)

  @doc "The panel modules, in tab order — the column `Console.Tlon.Focus` walks while the drawer is open."
  @spec pane_modules() :: [module()]
  def pane_modules, do: Keyword.values(@panes)

  @doc "A pane key's position in the strip (0-based), or nil."
  @spec index(atom()) :: non_neg_integer() | nil
  def index(key), do: Enum.find_index(keys(), &(&1 == key))

  @doc "The pane key at a position, or nil past the end (so a stray digit is a no-op)."
  @spec at(term()) :: atom() | nil
  def at(i) when is_integer(i) and i >= 0, do: Enum.at(keys(), i)
  def at(_i), do: nil

  @doc "One step along the strip, clamped at both ends — h/l walk a list, they don't spin a carousel."
  @spec step(atom(), -1 | 1) :: atom()
  def step(key, delta) do
    i = index(key) || 0
    (i + delta) |> max(0) |> min(length(keys()) - 1) |> at()
  end

  @doc """
  Open the drawer on `key` (or switch the open one to it). The drawer has the focus by definition —
  the keys are its own, not the terminal's — and the focus pane index tracks the strip, so every
  pane keeps its own j/k cursor.
  """
  @spec open(map(), atom() | nil) :: map()
  def open(state, key) do
    key = if panel(key), do: key, else: :memory
    focus = %{state.focus | in_terminal?: false, column: :left, pane: index(key), section: 0, detail?: false}
    %{state | drawer: key, focus: focus}
  end

  @doc "Close the drawer, remembering the pane for the next `Alt+d`, and step back into the terminal."
  @spec close(map()) :: map()
  def close(%{drawer: key} = state) do
    focus = %{state.focus | in_terminal?: true, column: :left, pane: 0, section: 0, detail?: false}
    %{state | drawer: nil, last_drawer: key || state.last_drawer, focus: focus}
  end

  @doc "True when `{x, y}` is inside the open drawer — a click outside it closes instead of picking."
  @spec covers?(map(), integer(), integer()) :: boolean()
  def covers?(%{drawer: nil}, _x, _y), do: false

  def covers?(%{w: w, h: h} = state, x, y) do
    r = rect(state, w, h)
    x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
  end

  @doc """
  The drawer's placements: one `Console.Panel.Border` carrying the tab strip over the centre, then
  the open pane's content inset inside it. `[]` while closed. `state` is the cockpit's, plus the
  frame's assembled `reads` (the pane data is resolved the one way `Console.View` resolves it).
  """
  @spec placements(map(), pos_integer(), pos_integer()) :: [Console.Board.placement()]
  def placements(%{drawer: nil}, _w, _h), do: []

  def placements(%{drawer: key} = state, w, h) do
    rect = rect(state, w, h)
    [{Panel.Border, border(key), rect} | content(key, state, inset(rect))]
  end

  defp rect(state, w, h), do: View.center_region(w, h, Map.get(state, :input))

  @doc "The pane under a click on the tab strip (the drawer's top rule), or nil anywhere else."
  @spec tab_at(map(), non_neg_integer(), non_neg_integer()) :: atom() | nil
  def tab_at(%{drawer: nil}, _x, _y), do: nil

  def tab_at(%{drawer: key, w: w, h: h} = state, x, y) do
    r = rect(state, w, h)

    if y == r.y and x >= r.x and x < r.x + r.w,
      do: at(Panel.Border.tab_at_x(border(key), x - r.x))
  end

  defp border(key) do
    tabs = for {k, _panel} <- @panes, do: {Atom.to_string(k), k == key}
    %{focused: true, digit: nil, title: nil, tabs: tabs, hint: @hint}
  end

  # An open detail replaces the pane's content until Esc (the lazygit feel, inside the drawer) —
  # only when one actually resolved, so Enter can never blank a pane with nothing to show.
  defp content(_key, %{focus: %Focus{detail?: true}, reads: %{detail: detail}}, rect) when not is_nil(detail),
    do: [{Panel.Detail, detail, rect}]

  # The boards read their rows from the server, like the full-screen boards did.
  defp content(kind, state, rect) when kind in [:tickets, :notes],
    do: [{panel(kind), Boards.board_data(kind, state), rect}]

  defp content(key, %{reads: reads} = state, rect), do: [View.content_for(panel(key), reads, rect, slice(state))]

  # The open pane's j/k cursor and Tab section — the drawer's pane IS the focused pane, so it always
  # gets the slice (in the frame only one box does).
  defp slice(%{focus: %Focus{} = focus} = state) do
    layout = Reads.tlon_layout(state)
    %{selected: Focus.cursor(focus, layout), section: focus.section}
  end

  # The content region inside the border: one cell of frame + one of padding, matching `View`'s.
  defp inset(%{x: x, y: y, w: w, h: h}), do: %{x: x + 2, y: y + 1, w: max(w - 4, 1), h: max(h - 2, 1)}
end
