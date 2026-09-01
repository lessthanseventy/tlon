defmodule Console.Panel.Sidebar do
  @moduledoc """
  The thin far-left SPINE (Slice 3.4) — an icon dock, replacing the fat Slack sidebar. A stack of
  chunky, fully-clickable **tiles** (Andrew 2026-08-31): **numbered workspace tiles at the TOP** (a
  matching thin-sans DIGIT icon each — the super+1..9 mental model), then a big flex gap, then the
  pinned BOTTOM group down by each other — the specials (Home/god-view, Tickets, Notes) and the
  actions (settings cog, `+`). A tile IS the space nav (`Enter`/click switches; the active tile fills
  SOLID — the colour is the cue, no arrow). No text labels — the active space's name rides the status
  bar. Icons are two-tier (`Console.Icons`): a Lucide/thin-sans PNG on kitty, a Nerd glyph fallback off it.

  Pure over `Server.Board.sidebar/0`'s read: data is `%{groups, active_key}`, plus `selected` (the
  nav cursor over the PICKABLE tiles — Home then each workspace, the order `key_at/2` resolves),
  `graphics?` (kitty host → blank the fallback glyph so the PNG covers cleanly), and `:scroll` — all
  injected by the View/Cockpit.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0, pad: 3]

  alias Console.Icons
  alias Server.Bus

  # Each tile is this many rows — a chunky, fully-clickable button (icon centered), not a thin line.
  @tile_h 3

  @impl Console.Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Console.Panel
  def render(%{active_key: active_key} = data, rect) do
    cursor = data[:selected]
    graphics? = data[:graphics?] == true

    body =
      data
      |> slots(rect.h)
      |> Enum.map(&slot_row(&1, active_key, cursor, rect.w, graphics?))

    Console.Panel.clip(body, rect)
  end

  def render(_data, rect), do: Console.Panel.clip([line("no workspaces — is server up?", :dim)], rect)

  # Click → the tile under local_y, the same slot list render walks (so the height it lays out to must
  # match render's — both pass the box's inset `rect.h`). Every tile row (anchor + padding) carries its
  # `kind`, so a click ANYWHERE on the tile picks; only the `─` rules and the flex gap are inert.
  @impl Console.Panel
  def pick(%{groups: _} = data, rect, local_y) do
    case data |> slots(rect.h) |> Enum.at(local_y) do
      {:tile, kind, _cursor, _label, _icon} -> pick_action(kind)
      {:pad, kind, _cursor} -> pick_action(kind)
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  @doc "The workspace map under `local_y`, if that tile is a workspace — the right-click menu's target."
  def workspace_at(%{groups: _} = data, rect, local_y) do
    case data |> slots(rect.h) |> Enum.at(local_y) do
      {:tile, {:workspace, ws}, _c, _l, _i} -> ws
      {:pad, {:workspace, ws}, _c} -> ws
      _ -> nil
    end
  end

  def workspace_at(_data, _rect, _local_y), do: nil

  # A workspace's display icon: the operator's chosen one (`knobs["icon"]`, coerced to a known name)
  # or the position digit as the default.
  defp workspace_icon(workspace, i), do: Icons.icon_name(workspace[:icon]) || Icons.digit(i)

  defp pick_action(:home), do: {:switch_space, :orbis}
  defp pick_action({:workspace, %{id: id}}), do: {:switch_space, id}
  defp pick_action(:tickets), do: {:open_board, :tickets}
  defp pick_action(:notes), do: {:open_board, :notes}
  defp pick_action(:settings), do: {:settings}
  defp pick_action(:add), do: {:new_workspace}
  defp pick_action(_kind), do: nil

  # The kitty raster tier: over each tile's ANCHOR row, place its icon PNG (Lucide for tools, a
  # matching thin-sans digit for workspaces). The render loop transmits/places these on kitty hosts
  # only (`Panel.images/2` isn't called otherwise), and render blanks the fallback glyph there (see
  # `slot_row/5`) so the PNG's transparent parts don't reveal it. Walks the SAME slots as render, so the
  # images track the layout.
  @impl Console.Panel
  def images(%{groups: _} = data, rect) do
    data
    |> slots(rect.h)
    |> Enum.with_index()
    |> Enum.flat_map(fn {slot, row} -> tile_image(slot, row, rect) end)
  end

  def images(_data, _rect), do: []

  # A small SQUARE icon (Andrew 2026-08-31): a `@icon_w`×1-cell box on the tile's anchor row. A cell is
  # ~half as wide as tall, so 2×1 cells ≈ a square in pixels — 3×1 squished the icon flat. Kitty scales
  # the PNG to that box. A tile with no icon (a workspace past digit 9) shows its text digit instead.
  @icon_w 2
  defp tile_image({:tile, _kind, _cursor, _label, nil}, _row, _rect), do: []

  defp tile_image({:tile, _kind, _cursor, _label, icon}, row, rect) do
    w = min(max(rect.w - 2, 1), @icon_w)
    x = rect.x + div(rect.w - w, 2)
    List.wrap(Icons.image(icon, %{x: x, y: rect.y + row, w: w, h: 1}))
  end

  defp tile_image(_slot, _row, _rect), do: []

  @doc """
  The space key under nav-cursor `index` — pickables in render order: 0 = Home (`:orbis`),
  then each workspace's id. The cockpit's Enter-to-switch resolves through this, so the
  cursor can never switch to a different space than the row the paint marked.
  """
  def key_at(_data, 0), do: :orbis

  def key_at(%{groups: groups}, index) when is_integer(index) and index > 0,
    do: with(%{workspace: %{id: id}} <- Enum.at(groups, index - 1), do: id)

  def key_at(_data, _index), do: nil

  @doc "How many pickable rows (Home + workspace headers) — what j/k clamps against."
  def pickable_count(%{groups: groups}), do: 1 + length(groups)
  def pickable_count(_data), do: 1

  # The SCREEN-ROW list render + pick share — every visible row, in order, laid out to `height`.
  # Layout (Andrew 2026-08-31): **numbered workspaces at the TOP**, then a big flex gap, then the pinned
  # BOTTOM group — a `─` rule, the specials (Home/god-view cursor 0, Tickets, Notes), a `─` rule, and
  # the actions (settings, `+`) — so the tools sit together down by the bottom. Each tile is `@tile_h`
  # rows: an ANCHOR row (label + icon) in the middle, PADDING rows above/below — ALL clickable (they
  # carry `kind`), so the whole button is one target. The j/k ring is Home+workspaces (key_at/2 over
  # Space.all order); tools/actions are click-only.
  defp slots(%{groups: groups}, height) do
    workspaces =
      groups
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {g, i} ->
        tile({:workspace, g.workspace}, i, Integer.to_string(i), workspace_icon(g.workspace, i))
      end)

    tools =
      tile(:home, 0, Icons.home(), :home) ++
        tile(:tickets, nil, Icons.ticket(), :ticket) ++
        tile(:notes, nil, Icons.note(), :note) ++
        [{:sep}] ++
        tile(:settings, nil, Icons.settings(), :settings) ++
        tile(:add, nil, Icons.add(), :add)

    bottom = [{:sep}] ++ tools
    flex = List.duplicate({:gap}, max(height - length(workspaces) - length(bottom), 0))
    workspaces ++ flex ++ bottom
  end

  # A tile: `@tile_h` rows. The middle row is the ANCHOR (carries the label + icon name); the rest are
  # PADDING (blank, but still carry `kind`+`cursor` so the whole tile is clickable and fills when active).
  defp tile(kind, cursor, label, icon) do
    mid = div(@tile_h - 1, 2)
    for i <- 0..(@tile_h - 1), do: if(i == mid, do: {:tile, kind, cursor, label, icon}, else: {:pad, kind, cursor})
  end

  # A section rule spanning the inset width; the flex gap is empty. Tiles render per face: the active
  # space fills solid (its colour IS the selection — no arrow marker), the nav cursor gets an accent
  # glyph, the rest sit quiet. On kitty the ANCHOR's label is BLANKED (the icon PNG covers it, so its
  # transparent parts don't reveal the glyph); off kitty the label/digit shows as the fallback.
  defp slot_row({:sep}, _active_key, _cursor, w, _graphics?), do: [{String.duplicate("─", max(w, 0)), :dim}]
  defp slot_row({:gap}, _active_key, _cursor, _w, _graphics?), do: blank()

  defp slot_row({:pad, kind, cursor_idx}, active_key, cursor, w, _graphics?) do
    glyph_run(tile_face(kind, cursor_idx, active_key, cursor), "", w)
  end

  defp slot_row({:tile, kind, cursor_idx, label, icon}, active_key, cursor, w, graphics?) do
    shown = if graphics? and not is_nil(icon), do: "", else: label
    glyph_run(tile_face(kind, cursor_idx, active_key, cursor), shown, w)
  end

  # active = the current space (solid fill); cursor = where Enter/j-k sits (accent); idle = neither.
  # Tools (`:tickets`/`:notes`) and actions (`:add`/`:settings`) are click-only — never active/cursor.
  defp tile_face(kind, _cursor_idx, _active_key, _cursor) when kind in [:add, :settings, :tickets, :notes], do: :idle
  defp tile_face(:home, cursor_idx, :orbis, cursor), do: face(true, cursor_idx == cursor)
  defp tile_face(:home, cursor_idx, _active_key, cursor), do: face(false, cursor_idx == cursor)

  defp tile_face({:workspace, %{id: id}}, cursor_idx, active_key, cursor),
    do: face(active_key == id, cursor_idx == cursor)

  defp face(true = _active?, _cursor?), do: :active
  defp face(false, true = _cursor?), do: :cursor
  defp face(false, false), do: :idle

  # The tile row, glyph CENTERED (so the centered kitty image overpaints it, not sits beside it).
  # Active = solid fill (the colour is the cue, no arrow); the nav cursor = an accent glyph; idle sits
  # quiet. Blank rows (glyph "") are a full-width fill — the button's height.
  defp glyph_run(:active, glyph, w), do: centered(glyph, w, :selected_accent, :selected)
  defp glyph_run(:cursor, glyph, w), do: centered(glyph, w, :accent, :normal)
  defp glyph_run(:idle, glyph, w), do: centered(glyph, w, :normal, :normal)

  defp centered("", w, _fg, bg), do: pad([], w, bg)

  defp centered(glyph, w, fg, bg) do
    lead = max(div(w, 2) - 1, 0)
    pad([{String.duplicate(" ", lead), bg}, {glyph, fg}], w, bg)
  end

  @impl Console.Panel
  def hints(_data), do: [{"j/k", "workspaces"}, {"⏎", "switch"}]
end
