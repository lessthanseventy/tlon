defmodule Console.View do
  @moduledoc """
  Composition: turn the cockpit's state into placed panels (design §3, "a view is plain data").
  Given the assembled server `reads` and the terminal size, `compose/3` lays out the fixed frame —
  left sidebar (space picker + the active space's situational panels), the center surface, the
  right sidebar — each section in its own bordered box — and the status footer, as a list of
  `{panel, data, rect}` placements the `Console.Board` paints. Pure and testable: no TTY, no server.

  `reads` is the map the Cockpit assembles:
    `%{active_key, focused_id, focused_title, roster, threads, scope, chatter, session}`
  """
  alias Console.Mention
  alias Console.Panel
  alias Console.Space
  alias Console.Tlon.Focus
  alias Console.Workspaces
  alias Server.Presence

  # Space.workspace?/1 is a defguard — usable outside a guard too, but only once required.
  require Space

  @min_col 16
  # The bottom footer: an info line + a hints line (Console.Panel.StatusBar).
  @status_h 2
  # Below this width (phone / a shrunk tile) the three columns collapse to one (Addendum §D).
  @wide_min 80
  # Panels whose content can overflow their box and so accept a `:scroll` offset (wheel scroll).
  # The center Terminal and StatusBar/Border never overflow.
  @scrollable [
    Panel.Sidebar,
    Panel.Overview,
    Panel.Conversation,
    Panel.Crew,
    Panel.Brief,
    Panel.Roster,
    Panel.Stack,
    Panel.Leaves,
    Panel.Activity,
    Panel.Triage,
    Panel.Memory,
    Panel.Detail,
    Panel.Author
  ]

  @spec compose(map(), pos_integer(), pos_integer()) :: [Console.Board.placement()]
  def compose(reads, w, h) do
    space = fetch_space(reads.active_key)
    composer_h = composer_height(reads, w, h)
    body_h = max(h - @status_h - composer_h, 1)

    # Each column holds a stack of *sections*, each its own bordered box, so sections read as
    # defined regions. A section is a bare panel module (data resolved by `data_for/2`) or a
    # `{panel, read_key}` pair reading straight from `reads[key]` — how Tlön's two Terminal panes
    # get distinct data. Wide viewports get three columns; narrow ones collapse to one.
    # MAIN is the terminal by default; a Tlön focus that opened a detail (Enter) replaces it with
    # the Detail panel until Esc closes it (the tmux terminal keeps running underneath, unpainted).
    # Orbis' author face (D2.1) replaces the survey (Overview) with Panel.Author the same way.
    center_panels =
      cond do
        detail_open?(reads) -> [Panel.Detail]
        reads.active_key == :orbis and reads[:orbis_face] == :author -> [Panel.Author]
        true -> chat_center(space.surface, reads)
      end

    left_sections = [Panel.Sidebar | space.left]
    # The contextual right rail (slice D): pinned head (workspace → STACK, attached thread → the
    # BRIEF) + the view-indexed carousel panel — the single source (Space.visible_right/3)
    # View/keymap/cockpit all read, so they can't disagree.
    right_sections =
      Space.visible_right(space, reads[:right_pane_view] || 0, Space.rail_context(reads[:focused_session]))

    boxes =
      case layout_for(w) do
        :wide ->
          %{left: left, center: center, right: right} = wide_columns(w, body_h)

          assign_digits(boxed(left_sections, left), 1) ++
            assign_digits(boxed(center_panels, center), :center) ++
            assign_digits(pinned_boxes(right_sections, right, reads), 1 + length(left_sections))

        :narrow ->
          sections = left_sections ++ center_panels ++ right_sections
          assign_digits(boxed(sections, %{x: 0, y: 0, w: w, h: body_h}), 1)
      end

    # A box under 2 rows can't hold a frame (Border renders [] below 2) and its inset content
    # would poke a row past the column — drop it whole. AFTER digit assignment, so a collapsed
    # box never renumbers its neighbors (the digits must match the focus layout's ordering).
    boxes = Enum.reject(boxes, fn {_section, rect, _digit} -> rect.h < 2 end)

    # In Tlön nav mode one sidebar pane is focused — its border lights up (the lazygit "active
    # pane" cue). Every other box, and every other space, stays neutral.
    focused = focused_section(reads[:focus], space, right_sections)

    # The carousel box's own section (the one right_sections member that isn't the pinned head) —
    # its border gets the tab strip instead of a plain title.
    carousel_active = List.last(right_sections)

    borders =
      Enum.map(boxes, fn {section, rect, digit} ->
        tabs = carousel_border(space, reads, section, carousel_active)
        {Panel.Border, border_data(section, digit, focused, tabs), rect}
      end)

    # The focused pane alone is fed a slice of the focus — its item cursor (j/k) as `selected` and
    # the active `section` (Tab) — so it lights the row Enter would open and the section Tab landed
    # on; every other pane gets nil (no selection, default section).
    slice = focus_slice(reads)

    contents =
      Enum.map(boxes, fn {section, rect, _digit} ->
        content_for(section, reads, inset(rect), if(section == focused, do: slice))
      end)

    status =
      {Panel.StatusBar, status_data(reads, space, focused), %{x: 0, y: h - @status_h, w: w, h: @status_h}}

    # Borders first: panel content paints over each box interior, leaving only the frames.
    borders ++ contents ++ composer_placement(reads, composer_h, w, h) ++ [status]
  end

  # The center's chat face: `v` flips center_view to :chat — swap the Terminal section for the
  # THREAD STACK (Slice 3: a stack of foldable Slack-style thread cards, the whole workspace's
  # threads at once), keeping the WindowBar/Ticker frame around it. Only when the read resolved: a
  # failed/empty read (server down) degrades to the PTY, never a blank center.
  defp chat_center(surface, %{center_view: :chat} = reads) do
    if is_map(reads[:thread_stack]) do
      Enum.map(surface, fn
        {Panel.Terminal, _read_key} -> {Panel.ThreadStack, :thread_stack}
        other -> other
      end)
    else
      surface
    end
  end

  defp chat_center(surface, _reads), do: surface

  # The growable compose box: sits between the body and the status bar while the `c` composer is
  # open. Height = the wrapped line count (wrap + grow, never truncate), capped at half the frame —
  # past the cap the box scrolls (Panel.Composer keeps the cursor line visible).
  defp composer_height(%{input: %{kind: :compose} = input}, w, h) do
    input
    |> Panel.Composer.lines(Panel.Composer.text_width(w))
    |> length()
    |> min(max(div(h, 2), 1))
  end

  defp composer_height(_reads, _w, _h), do: 0

  defp composer_placement(_reads, 0, _w, _h), do: []

  defp composer_placement(reads, composer_h, w, h),
    do: [{Panel.Composer, %{input: reads[:input]}, %{x: 0, y: h - @status_h - composer_h, w: w, h: composer_h}}]

  defp layout_for(w) when w >= @wide_min, do: :wide
  defp layout_for(_w), do: :narrow

  # The sidebar pane the Tlön focus sits on — only in nav mode (out of the terminal), so the frame
  # lights the instant you Ctrl+Space out. nil for other spaces and while in the terminal (the
  # terminal is the active pane then). Matches by section module — the panes are distinct, so module
  # identity is unambiguous. The Sidebar leads the left column here exactly as it does on screen, so
  # its frame lights when the focus navigates onto the workspace nav.
  defp focused_section(%Focus{in_terminal?: false} = focus, space, right_sections),
    do: Focus.focused_pane(focus, %{left: [Panel.Sidebar | space.left], right: right_sections, sections: %{}})

  defp focused_section(_focus, _space, _right_sections), do: nil

  # Sidebar boxes number top-down from `start` (left 1.., right continuing); the center's
  # terminal box alone is 0 — Alt+0/`0` mean "back to the terminal" (design 2026-08-23).
  defp assign_digits(boxes, :center),
    do: Enum.map(boxes, fn {section, rect} -> {section, rect, if(terminal_section?({section, rect}), do: 0)} end)

  defp assign_digits(boxes, start) do
    boxes
    |> Enum.with_index(start)
    |> Enum.map(fn {{section, rect}, d} -> {section, rect, d} end)
  end

  defp border_data(section, digit, focused, tabs) do
    %{
      focused: not is_nil(focused) and section == focused,
      digit: digit,
      title: if(tabs, do: nil, else: section_title(section)),
      tabs: tabs,
      hint: if(tabs, do: "[ ] cycle")
    }
  end

  # The carousel box's tab strip: every carousel member's title, the visible one lit. nil for
  # every other box (and when there's no carousel — Orbis).
  defp carousel_border(space, reads, section, carousel_active) do
    carousel = Space.carousel(space)

    if carousel != [] and section == carousel_active and section in carousel do
      # Integer.mod matches Space.visible_right's wrap, so the lit tab is the shown panel.
      active = Enum.at(carousel, Integer.mod(reads[:right_pane_view] || 0, length(carousel)))
      Enum.map(carousel, fn p -> {section_title(p), p == active} end)
    end
  end

  # The on-frame title per section. A section with no entry (Terminal, WindowBar, Ticker, the
  # center surfaces) gets a bare frame.
  defp section_title({panel, _read_key}), do: section_title(panel)
  defp section_title(Panel.Sidebar), do: "WORKSPACES"
  defp section_title(Panel.Stack), do: "STACK"
  defp section_title(Panel.Memory), do: "MEMORY"
  defp section_title(Panel.Crew), do: "CREW"
  defp section_title(Panel.Activity), do: "ACTIVITY"
  # THREADS since reshape slice C: chat + tracked threads are ONE list; stage rides as a chip.
  defp section_title(Panel.Leaves), do: "THREADS"
  defp section_title(Panel.Roster), do: "ACTIVE"
  defp section_title(Panel.Triage), do: "TRIAGE"
  defp section_title(Panel.Brief), do: "BRIEF"
  defp section_title(_section), do: nil

  # True when the Tlön focus has a detail open AND the cockpit resolved content for it — an Enter on
  # a pane with no detail (nil) leaves the terminal in place rather than blanking MAIN.
  defp detail_open?(%{focus: %Focus{detail?: true}} = reads), do: reads[:detail] != nil
  defp detail_open?(_reads), do: false

  # The slice of the focus the focused pane needs to render: `selected` (the clamped j/k cursor) and
  # the active `section` (Tab). nil outside Tlön nav — panes then render their default (section 0,
  # no selection).
  defp focus_slice(%{focus: %Focus{} = focus, tlon_layout: layout}) when is_map(layout),
    do: %{selected: Focus.cursor(focus, layout), section: focus.section}

  defp focus_slice(_reads), do: nil

  # The three-column geometry (left ¼ · center ½ · right ¼) of the wide layout, as box rects — the
  # single source of truth for where each column sits. `compose/3` places panels into these, and
  # `center_rect/3` derives the center Terminal's content rect from the SAME math, so the embedded
  # PTY can be sized to exactly what's on screen (a wider PTY spills pi past the frame; a shorter
  # one leaves a dead band).
  defp wide_columns(w, body_h) do
    left_w = clamp_col(div(w, 4), w)
    right_w = clamp_col(div(w, 4), w)
    center_w = max(w - left_w - right_w - 2, 1)
    center_x = left_w + 1
    right_x = center_x + center_w + 1
    right_w = max(w - right_x, 1)

    %{
      left: %{x: 0, y: 0, w: left_w, h: body_h},
      center: %{x: center_x, y: 0, w: center_w, h: body_h},
      right: %{x: right_x, y: 0, w: right_w, h: body_h}
    }
  end

  @doc """
  The content rect the center Terminal renders into for a `space_key`/`w`×`h` cockpit — the single
  source of truth the embedded PTY sizes to, so pi never draws wider or taller than the visible
  area. Orbis carries no center Terminal (its surface is `[Overview]`, the survey) → this falls back
  to the full center column. Tlön's WindowBar/Ticker bands (`Console.Space`) share the column with its
  Terminal, so its box is smaller — found via the SAME `boxed/2` stacking `compose/3` uses, not a
  second formula that could drift. (The PTY is only sized in the wide layout — a real cockpit is
  never below the narrow threshold.)
  """
  @spec center_rect(atom(), pos_integer(), pos_integer()) :: Panel.rect()
  def center_rect(space_key, w, h) do
    center_col = wide_columns(w, max(h - @status_h, 1)).center
    surface = fetch_space(space_key).surface

    case Enum.find(boxed(surface, center_col), &terminal_section?/1) do
      {_section, rect} -> inset(rect)
      nil -> inset(center_col)
    end
  end

  # `Space.fetch/1` returns nil on a miss (Phase C1: no silent Orbis default at the Space layer) —
  # a stale/unknown active_key mid-render degrades to an empty space here instead of crashing the
  # paint (View chooses to be forgiving; Space stays honest).
  defp fetch_space(key), do: Space.fetch(key) || %Space{key: key, label: "?", surface: []}

  defp terminal_section?({Panel.Terminal, _rect}), do: true
  defp terminal_section?({{Panel.Terminal, _read_key}, _rect}), do: true
  defp terminal_section?(_boxed), do: false

  # The content region inside a section box: one cell of frame + one of padding on each side.
  defp inset(%{x: x, y: y, w: w, h: h}) do
    %{x: x + 2, y: y + 1, w: max(w - 4, 1), h: max(h - 2, 1)}
  end

  # A keyed surface section reads its data directly; a bare module resolves via data_for/2. The
  # 4-arity variant injects the focused pane's `selected` cursor into its data (nil elsewhere).
  defp content_for(section, reads, rect, slice) do
    {panel, data, rect} = content_for(section, reads, rect)
    {panel, merge_slice(data, slice), rect}
  end

  defp content_for({panel, read_key}, reads, rect), do: {panel, scroll_data(panel, reads[read_key], reads), rect}
  defp content_for(panel, reads, rect), do: {panel, scroll_data(panel, data_for(panel, reads), reads), rect}

  defp merge_slice(data, nil), do: data
  defp merge_slice(data, slice) when is_map(data), do: Map.merge(data, slice)
  defp merge_slice(data, _slice), do: data

  @doc "Resolve the data a panel is fed from the assembled reads (keeps spaces plain data)."
  def data_for(Panel.Sidebar, r), do: %{groups: r[:sidebar] || [], active_key: r.active_key}
  def data_for(Panel.Roster, r), do: %{sessions: r.roster}

  def data_for(Panel.Brief, r), do: r.scope

  def data_for(Panel.Overview, r),
    do: %{workspaces: r[:workspaces] || [], survey_cursor: r[:survey_cursor], orbis_focus: r[:orbis_focus]}

  # The author face's own workspace list — `Console.Workspaces.all/0` directly (not the survey's rollup
  # cache), since a thread-less workspace (a fresh "blank" template) is real here even when
  # `Console.Orbis.rollup/0` has nothing to show (D2.2). `edit` (D2.4 Chunk 2a) is nil unless `e`
  # opened the field editor — `Panel.Author` switches its render on its presence.
  def data_for(Panel.Author, r),
    do: %{workspaces: author_workspaces(), cursor: r[:author_cursor] || 0, edit: r[:author_edit]}

  # `presence` (thinking/working lists for the focused thread) is optional so pure View tests
  # can compose reads without it — the panel treats missing lists as empty.
  def data_for(Panel.Conversation, r), do: Map.merge(%{title: r.focused_title, messages: r.chatter}, r[:presence] || %{})
  def data_for(Panel.Stack, r), do: r.stack
  def data_for(Panel.Crew, r), do: r[:crew]
  # `r.orbis` arrives ALREADY enriched with `:focused_lead`/`:attached` (the cockpit's
  # `leaves_data/1`, the single enrichment its yank/attach/preview paths share), so the row order
  # here can never disagree with what those paths index.
  def data_for(Panel.Leaves, r), do: r.orbis
  def data_for(Panel.Activity, r), do: %{events: r[:activity] || []}
  def data_for(Panel.Ticker, r), do: %{events: r[:activity] || []}
  # The permanent tertius band (Slice 3): the orchestrator input + a short receipts log.
  def data_for(Panel.Tertius, r), do: %{receipts: r[:receipts] || [], input: r[:input]}
  def data_for(Panel.WindowBar, r), do: %{tabs: window_tabs(r), engine: engine_state(), thread: r.focused_id}
  def data_for(Panel.Triage, r), do: r.triage
  def data_for(Panel.Memory, r), do: r[:memory]
  def data_for(Panel.Detail, r), do: r[:detail]
  def data_for(_other, _r), do: nil

  # Inject the panel's current scroll offset into scrollable panels' data (nil data left alone —
  # e.g. Brief with no focused thread renders its placeholder, no scroll needed).
  defp scroll_data(_panel, nil, _reads), do: nil

  defp scroll_data(panel, data, reads) when panel in @scrollable,
    do: Map.put(data, :scroll, (reads[:scrolls] || %{})[panel] || 0)

  defp scroll_data(_panel, data, _reads), do: data

  # `Console.Workspaces` isn't started under `mix test` (config/test.exs `start_workspaces: false` — it
  # would subscribe to the server workspaces Bus and pollute the pure-render tests), so a call here
  # degrades to `[]` instead of crashing the paint — same guard as `Console.Space.fetch_workspaces/0`.
  defp author_workspaces do
    Workspaces.all()
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp status_data(reads, space, focused) do
    %{
      space: space.label,
      thread: reads.focused_title,
      thread_count: length(reads.threads),
      live_count: Enum.count(reads.roster, & &1.warm?),
      # HEALTH demoted to the footer (reshape slice D) — the condensed segment's read.
      health: reads[:health],
      # When the operator is typing a new-thread title, the footer becomes the prompt.
      input: reads[:input],
      # A transient result line (a spawn's pane id or failure), shown until the next keypress.
      flash: reads[:flash],
      # True for the one keypress after Ctrl+Space — the hints line shows the armed-prefix state.
      leader_pending?: reads[:leader_pending?],
      # Tlön's focus (nil elsewhere) — the footer shows NAV/TERM and the focus-model hints.
      focus: reads[:focus],
      # The contextual footer's keys (design 2026-08-23) — workspace-ness, never the label.
      mode: footer_mode(reads),
      workspace?: Space.workspace?(space.key),
      lock?: reads[:lock?] == true,
      pane_hints: pane_hints(reads, space, focused)
    }
  end

  defp footer_mode(%{lock?: true}), do: :lock
  defp footer_mode(%{focus: %Focus{in_terminal?: true}}), do: :term
  defp footer_mode(%{focus: %Focus{}}), do: :nav
  defp footer_mode(_reads), do: nil

  # The focused pane's declared verbs; the carousel slot appends the view-cycle key.
  defp pane_hints(_reads, _space, nil), do: []

  defp pane_hints(reads, space, focused) do
    {panel, data, _rect} = content_for(focused, reads, %{x: 0, y: 0, w: 40, h: 10})
    hints = Panel.hints(panel, data)
    if focused in Space.carousel(space), do: hints ++ [{"[/]", "view"}], else: hints
  end

  @gap 1

  # The right column (design 2026-08-23): the pinned head at intrinsic height (content + 2
  # frame rows, never flexed), the carousel below at full remaining height.
  defp pinned_boxes([], _rect, _reads), do: []
  defp pinned_boxes([only], rect, _reads), do: boxed([only], rect)

  defp pinned_boxes([pinned, carousel_panel], %{x: x, y: y, w: w, h: h}, reads) do
    # A short column shrinks the pinned head before the carousel dies: capped so the carousel
    # keeps at least a 2-row frame, floored at a 2-row frame of its own, never past the column.
    # A half that still lands under 2 rows is dropped whole by `compose/3` — a sliver box's
    # inset would poke a row past the frame (the no-overflow invariant).
    pinned_h = h |> min(max(h - @gap - 2, 2)) |> min(intrinsic_height(pinned, reads, w) + 2)
    rest_h = max(h - pinned_h - @gap, 0)

    [
      {pinned, %{x: x, y: y, w: w, h: pinned_h}},
      {carousel_panel, %{x: x, y: y + pinned_h + @gap, w: w, h: rest_h}}
    ]
  end

  # Content height at the box's inset width. nil data (probe not run yet — pure tests, boot
  # frame) gets a stable nominal so the layout doesn't jump when the probe lands ≈ its size.
  defp intrinsic_height(section, reads, box_w) do
    {panel, data, _rect} = content_for(section, reads, %{x: 0, y: 0, w: max(box_w - 4, 1), h: 1})
    if data == nil, do: 10, else: Panel.content_height(panel, data, max(box_w - 4, 1))
  end

  # Stack sections vertically down a column as box rects, a 1-row gap between them. The picker
  # takes a fixed height, the rest split the remainder (the last absorbs the rounding remainder).
  defp boxed([], _rect), do: []

  defp boxed(panels, %{x: x, y: y, w: w, h: h}) do
    gaps = max(length(panels) - 1, 0) * @gap
    # The section budget is the column minus the inter-section gaps; never inflate it past what
    # fits (a `length(panels)` floor would push short columns off-frame). split_heights/2 fits the
    # sections into exactly this budget, so no placed box's `y + h` ever exceeds the column bottom.
    heights = split_heights(panels, max(h - gaps, 0))

    {placed, _y} =
      panels
      |> Enum.zip(heights)
      |> Enum.map_reduce(y, fn {panel, ph}, cy ->
        {{panel, %{x: x, y: cy, w: w, h: ph}}, cy + ph + @gap}
      end)

    placed
  end

  # Resolve each section's height within `total_h` (the column's row budget net of gaps). The
  # invariant is that the resolved heights SUM to at most `total_h`, so `boxed/2` never places a box
  # past the column bottom (design: "no overflow past the frame").
  defp split_heights(panels, total_h) do
    fixed = Enum.map(panels, &fixed_height/1)
    fixed_sum = fixed |> Enum.reject(&is_nil/1) |> Enum.sum()
    flex_count = Enum.count(fixed, &is_nil/1)

    if fixed_sum <= total_h do
      # Room for every fixed section at nominal height: the flex sections split the remainder, and
      # any rounding leftover goes to the last section so the column is fully used.
      flex = if flex_count > 0, do: max(div(total_h - fixed_sum, flex_count), 0), else: 0
      resolved = Enum.map(fixed, fn f -> f || flex end)
      used = Enum.sum(resolved)
      List.update_at(resolved, -1, &(&1 + max(total_h - used, 0)))
    else
      # Too short even for the fixed sections: no room for flex (0), and the fixed sections shrink in
      # stack order against a running budget — a lower section collapses to 0 (not rendered) before
      # anything is placed off-frame.
      shrink_to_fit(fixed, total_h)
    end
  end

  defp shrink_to_fit(sections, total_h) do
    {resolved, _left} =
      Enum.map_reduce(sections, total_h, fn nominal, left ->
        take = min(nominal || 0, left)
        {take, left - take}
      end)

    resolved
  end

  # The WindowBar/Ticker bands framing the Tlön terminal: one content row + their own 2-row frame.
  defp fixed_height(Panel.WindowBar), do: 3
  defp fixed_height(Panel.Ticker), do: 3
  # The tertius band is taller than the Ticker pulse it replaces: the input line + up to 2 receipts,
  # plus the 2-row frame.
  defp fixed_height(Panel.Tertius), do: 5
  defp fixed_height({panel, _read_key}), do: fixed_height(panel)
  defp fixed_height(_panel), do: nil

  # The Tlön window strip, presence-joined: `reads.machine`'s tabs (from `tlon_tabs()`, forked
  # once per render by the Cockpit) each get their agent handle (window → agent via
  # `Console.Mention.coworkers/1`, inverted, sourced from the active space's roster) and warmth
  # (`reads.roster`, already fetched for the sidebar) — so WindowBar stays a pure render with no
  # server reads of its own.
  # C3.1: the strip is LEADERS only — leaf windows (spawned by ensure_thread_sessions) move to the
  # Leaves panel. A leaf is any window carrying a thread tag (`@funes_thread` → `thread_id`); the
  # `t<id>` name is only the legacy fallback (Slice 0: descriptive names like `builder-…` dodged a
  # name-only reject and leaked onto the strip). Reject by the leaf SHAPE, not a roster allowlist, so
  # an unexpected leader window (roster not yet loaded, a hand-made window) still shows.
  @leaf_window ~r/^t\d+$/

  # Mirrors Cockpit.leaf_window?/1 (that one is a private seam over the same tab shape) — retire the
  # duplication when leaf/leader is renamed out (Slice 4).
  defp leaf_tab?(%{thread_id: tid}) when is_integer(tid), do: true
  defp leaf_tab?(%{name: name}), do: Regex.match?(@leaf_window, name)

  defp window_tabs(r) do
    agents = Map.new(Mention.coworkers(fetch_space(r.active_key).roster), fn {agent, window} -> {window, agent} end)
    warm_agents = r.roster |> Enum.filter(& &1.warm?) |> MapSet.new(& &1.agent)

    r
    |> Map.get(:machine, %{})
    |> tabs_of()
    |> Enum.reject(&leaf_tab?/1)
    |> Enum.map(fn tab ->
      agent = agents[tab.name]
      Map.merge(tab, %{agent: agent, warm?: agent != nil and MapSet.member?(warm_agents, agent)})
    end)
  end

  defp tabs_of(%{tabs: tabs}), do: tabs
  defp tabs_of(_render_state), do: []

  @doc """
  The active leader — the focused WindowBar tab's agent handle, off `window_tabs/1` (C3.2). The
  ONE derivation of the Leaves reorder context: the cockpit calls it per render (over the same
  `machine`/`roster` reads compose sees) and caches it, so render, yank, attach, and preview all
  float rows by the identical lead. `reads` needs `:machine`, `:active_key`, `:roster`.
  """
  def focused_lead(r), do: r |> window_tabs() |> Enum.find_value(fn t -> if t.active?, do: t.agent end)

  # The Claude-engine clock readout: `:off` only once the operator has manually clocked "claude"
  # out (`Server.Presence.clock_out/1`, e.g. from `server:console`) — nothing calls that today, so
  # this reads `:on` until that console verb exists. A real per-agent engine reader (§3b,
  # `Server.Presence.Engine`) is a later, local backend swapped into the same seam.
  defp engine_state, do: if("claude" in Presence.clocked_out_engines(), do: :off, else: :on)

  defp clamp_col(v, w), do: v |> max(@min_col) |> min(max(div(w, 3), @min_col))
end
