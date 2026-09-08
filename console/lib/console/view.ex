defmodule Console.View do
  @moduledoc """
  Composition: turn the cockpit's state into placed panels (design §3, "a view is plain data").
  Given the assembled server `reads` and the terminal size, `compose/3` lays out the fixed frame —
  left sidebar (space picker + the active space's situational panels), the center surface, the
  right sidebar — each section in its own bordered box — and the status footer, as a list of
  `{panel, data, rect}` placements the `Console.Board` paints. Pure and testable: no TTY, no server.

  `reads` is the map the Cockpit assembles (`Console.Cockpit` `do_render/1`): `active_key`,
  `focused_id`, `focused_title`, `roster`, `threads`, `thread_stack`, `machine`, the rail reads, …
  """
  alias Console.Panel
  alias Console.Space
  alias Console.Tlon.Focus
  alias Console.Workspaces

  # Space.workspace?/1 is a defguard — usable outside a guard too, but only once required.
  require Space

  # The frame's bars (UX slice 1): one line each, top and bottom. The top bar says where you are
  # and who is on it (Console.Panel.TopBar); the footer is the contextual hints (Panel.StatusBar).
  @top_h 1
  @status_h 1
  # Below this width (phone / a shrunk tile) the three columns collapse to one (Addendum §D).
  @wide_min 80
  # Below this the centre stays ONE pane: two halves of a narrower frame are too thin to read a
  # conversation and a terminal side by side. A live session still splits it — that pane was asked for.
  @two_pane_min 100
  # Panels whose content can overflow their box and so accept a `:scroll` offset (wheel scroll).
  # The center Terminal and StatusBar/Border never overflow.
  @scrollable [
    Panel.Rail,
    Panel.ThreadStack,
    Panel.Crew,
    Panel.Roster,
    Panel.Stack,
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
    body_h = max(h - @top_h - @status_h - composer_h, 1)

    # Each column holds a stack of *sections*, each its own bordered box, so sections read as
    # defined regions. A section is a bare panel module (data resolved by `data_for/2`) or a
    # `{panel, read_key}` pair reading straight from `reads[key]` — how Tlön's two Terminal panes
    # get distinct data. Wide viewports get three columns; narrow ones collapse to one.
    # MAIN is the terminal by default; a Tlön focus that opened a detail (Enter) replaces it with
    # the Detail panel until Esc closes it (the tmux terminal keeps running underneath, unpainted).
    center_panels = if detail_open?(reads), do: [Panel.Detail], else: chat_center(space.surface, reads)

    # UX slice 1: TWO regions — the always-on RAIL (workspaces + the active workspace's threads) at
    # the frame's left edge, and the CENTER (thread stack + tertius). The spine and the funes rail
    # (`space.left`, NOW·CREW·MEMORY·STACK) are off the frame; the drawer hosts those panes.
    rail = [Panel.Rail]

    boxes =
      case layout_for(w) do
        :wide ->
          right = right_section(reads, w)
          cols = wide_columns(w, body_h, right != nil)

          # Nav v2 (Andrew 2026-08-31): NO pane digits. Alt+N is tmux tabs, Alt+Shift+N is workspaces.
          base =
            no_digits(boxed(rail, cols.rail)) ++
              no_digits(boxed(center_panels, cols.center, new_thread_overrides(reads, cols.center.w)))

          if right, do: base ++ no_digits(boxed([right], cols.right)), else: base

        :narrow ->
          no_digits(boxed(rail ++ center_panels, %{x: 0, y: @top_h, w: w, h: body_h}))
      end

    # A box under 2 rows can't hold a frame (Border renders [] below 2) and its inset content would
    # poke a row past the column — drop it whole.
    boxes = Enum.reject(boxes, fn {_section, rect, _digit} -> rect.h < 2 end)

    # In Tlön nav mode one sidebar pane is focused — its border lights up (the lazygit "active
    # pane" cue). Every other box, and every other space, stays neutral.
    focused = focused_section(reads)

    # Slice 3.4: the rail stacks every panel, so there's no carousel and no border tab strip — every
    # box carries a plain digit-first title.
    borders =
      Enum.map(boxes, fn {section, rect, digit} ->
        {Panel.Border, border_data(section, digit, focused, nil), rect}
      end)

    # The focused pane alone is fed a slice of the focus — its item cursor (j/k) as `selected` and
    # the active `section` (Tab) — so it lights the row Enter would open and the section Tab landed
    # on; every other pane gets nil (no selection, default section).
    slice = focus_slice(reads)

    contents =
      Enum.map(boxes, fn {section, rect, _digit} ->
        content_for(section, reads, inset(rect), if(section == focused, do: slice))
      end)

    top = {Panel.TopBar, top_data(reads, space), %{x: 0, y: 0, w: w, h: @top_h}}

    status =
      {Panel.StatusBar, status_data(reads, focused), %{x: 0, y: h - @status_h, w: w, h: @status_h}}

    # The top bar, then the borders: panel content paints over each box interior, leaving only the
    # frames. The two bars are borderless, so neither is in `boxes`.
    [top | borders] ++ contents ++ composer_placement(reads, composer_h, w, h) ++ [status]
  end

  # The center's chat face: `v` flips center_view to :chat — swap the Terminal section for the
  # THREAD STACK (Slice 3: a stack of foldable Slack-style thread cards, the whole workspace's
  # threads at once), keeping the bands around it. Only when the read resolved: a
  # failed/empty read (server down) degrades to the PTY, never a blank center.
  defp chat_center(surface, %{center_view: :chat} = reads) do
    if is_map(reads[:thread_stack]) do
      # The bottom band morphs with the center step (2026-09-01): with a thread OPENED the new-thread
      # band gives way to that thread's persistent Reply box (one band, two faces, never both).
      # Read `opened` off the SAME thread_stack read the center's list⇄conversation switch uses, so the
      # band and the center can never disagree about whether a thread is open.
      opened? = is_integer(reads.thread_stack[:opened])

      Enum.map(surface, fn
        {Panel.Terminal, _read_key} -> {Panel.ThreadStack, :thread_stack}
        Panel.NewThread when opened? -> Panel.Reply
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

  # The new-thread band grows with its buffer (Andrew 2026-09-01): a height override for the center
  # `boxed/3` = the wrapped line count + the 2-row frame, capped. The wrap width matches the panel's
  # own (`Panel.NewThread.wrap_width/1`) over the band's inset content width, so height ↔ render agree.
  defp new_thread_overrides(%{input: %{kind: :new_thread, buffer: buffer}}, center_w) do
    content_w = max(center_w - 4, 8)
    lines = buffer |> Panel.NewThread.wrapped_lines(Panel.NewThread.wrap_width(content_w)) |> length() |> max(1)

    %{Panel.NewThread => min(lines + 2, 12)}
  end

  # The reply band grows the same way (its wrap width nets the id-dependent `↳ reply to #N ▸` prefix).
  defp new_thread_overrides(%{input: %{kind: :reply, thread_id: id, buffer: buffer}}, center_w) do
    content_w = max(center_w - 4, 8)
    lines = buffer |> Panel.Reply.wrapped_lines(Panel.Reply.wrap_width(content_w, id)) |> length() |> max(1)

    %{Panel.Reply => min(lines + 2, 12)}
  end

  defp new_thread_overrides(_reads, _center_w), do: %{}

  defp composer_placement(_reads, 0, _w, _h), do: []

  defp composer_placement(reads, composer_h, w, h),
    do: [{Panel.Composer, %{input: reads[:input]}, %{x: 0, y: h - @status_h - composer_h, w: w, h: composer_h}}]

  defp layout_for(w) when w >= @wide_min, do: :wide
  defp layout_for(_w), do: :narrow

  # The pane the Tlön focus sits on — only in nav mode (out of the terminal), so the frame lights the
  # instant you Ctrl+Space out. nil while in the terminal (the terminal is the active pane then).
  # UX slice 1: the left column is the rail alone; while the drawer is open ITS pane has the focus
  # (the rail isn't walkable then), so the footer's hints are the open pane's own.
  defp focused_section(%{drawer: key}) when not is_nil(key), do: Console.Cockpit.Drawer.panel(key)

  defp focused_section(%{focus: %Focus{in_terminal?: false} = focus}),
    do: Focus.focused_pane(focus, %{left: [Panel.Rail], right: [], sections: %{}})

  defp focused_section(_reads), do: nil

  # Nav v2: no pane digits (the numbers are gone from the frames) — every box just carries `nil`.
  defp no_digits(boxes), do: Enum.map(boxes, fn {section, rect} -> {section, rect, nil} end)

  defp border_data(section, digit, focused, tabs) do
    %{
      focused: not is_nil(focused) and section == focused,
      digit: digit,
      title: if(tabs, do: nil, else: section_title(section)),
      tabs: tabs,
      hint: if(tabs, do: "[ ] cycle")
    }
  end

  # The on-frame title per section. A section with no entry (Terminal, the center surfaces) gets a
  # bare frame.
  # The right session pane's frame title (the open thread's live lead PTY).
  defp section_title({Panel.Terminal, :session}), do: "SESSION"
  # Same box, same name — only the contents differ (no live PTY to attach yet).
  defp section_title(Panel.Placeholder), do: "SESSION"
  defp section_title({panel, _read_key}), do: section_title(panel)
  # The always-on left rail (UX slice 1) — workspaces + the active workspace's threads.
  defp section_title(Panel.Rail), do: "RAIL"
  defp section_title(Panel.Stack), do: "STACK"
  defp section_title(Panel.Memory), do: "MEMORY"
  defp section_title(Panel.Crew), do: "CREW"
  # NOW since Slice 3.4 — the rail's top pane is the attention/activity feed.
  defp section_title(Panel.Activity), do: "NOW"
  defp section_title(Panel.Roster), do: "ACTIVE"
  defp section_title(Panel.Triage), do: "TRIAGE"
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

  # What the right pane holds, or nil — the conversation then spans the whole centre. A live session
  # puts the coworker's PTY there; with none, an OPEN conversation still keeps the pane, holding the
  # stand-in, so the frame doesn't reflow every time a session ends. Only an EXPLICIT `true` splits a
  # frame under the two-pane floor, and `false` means no box at all — the footer says "pane off".
  defp right_section(reads, w) do
    mode = reads[:session_pane_mode]

    cond do
      is_integer(reads[:session_pane]) and (w >= @two_pane_min or mode == true) -> {Panel.Terminal, :session}
      mode == false -> nil
      w >= @two_pane_min and conversation_open?(reads) -> Panel.Placeholder
      true -> nil
    end
  end

  # The pane sits beside the CONVERSATION (design 2026-09-08 §2) — never beside the machine terminal,
  # which owns the whole centre.
  defp conversation_open?(reads), do: reads[:center_view] == :chat and not is_nil(opened_id(reads))

  # The two-region geometry (UX slice 1): the RAIL at the frame's left edge, and the CENTER (the
  # rest) — the single source of truth for where each region sits. `compose/3` places panels into
  # these, and `center_rect/3` derives the center Terminal's content rect from the SAME math, so the
  # embedded PTY is sized to exactly what's on screen (a wider PTY spills pi past the frame; a
  # shorter one leaves a dead band).
  defp wide_columns(w, body_h, session? \\ false) do
    rail_w = rail_width(w)
    center_x = rail_w + 1
    center_total = max(w - center_x, 1)

    base = %{rail: %{x: 0, y: @top_h, w: rail_w, h: body_h}}

    # The right SESSION PANE (design 2026-09-08 §2): the conversation is the centre with the
    # coworker's terminal beside it — TWO EQUAL panes, the odd column going to the conversation.
    # No pane = the conversation spans the whole centre.
    if session? do
      right_w = max(div(center_total - 1, 2), 1)
      center_w = max(center_total - right_w - 1, 1)

      Map.merge(base, %{
        center: %{x: center_x, y: @top_h, w: center_w, h: body_h},
        right: %{x: center_x + center_w + 1, y: @top_h, w: right_w, h: body_h}
      })
    else
      Map.put(base, :center, %{x: center_x, y: @top_h, w: center_total, h: body_h})
    end
  end

  # Thin, but wide enough for a thread title: a fifth of the frame, floored at 22 columns so a rail
  # row is readable, capped at a third so it can never crowd the conversation.
  defp rail_width(w), do: w |> div(5) |> max(22) |> min(div(w, 3))

  @doc """
  The content rect the center Terminal renders into for a `space_key`/`w`×`h` cockpit — the single
  source of truth the embedded PTY sizes to, so pi never draws wider or taller than the visible
  area. A missing space carries no center Terminal → this falls back
  to the full center column. `input` is the cockpit's open input (nil = none), so an open composer
  shortens the rect the same way it shortens the frame. A Workspace's NewThread/Tertius bands (`Console.Space`) share the column
  with its Terminal, so its box is smaller — found via the SAME `boxed/2` stacking `compose/3` uses, not a
  second formula that could drift. (The PTY is only sized in the wide layout — a real cockpit is
  never below the narrow threshold.)
  """
  @spec center_rect(atom(), pos_integer(), pos_integer(), map() | nil) :: Panel.rect()
  def center_rect(space_key, w, h, input \\ nil) do
    center_col = wide_columns(w, body_height(w, h, input)).center
    surface = fetch_space(space_key).surface

    case Enum.find(boxed(surface, center_col), &terminal_section?/1) do
      {_section, rect} -> inset(rect)
      nil -> inset(center_col)
    end
  end

  @doc """
  The frame's CENTER region: everything right of the rail, between the two bars (an open composer
  shortens it, like every body rect). The drawer covers exactly this — the rail and the bars stay
  on screen, and the PTYs underneath keep the sizes `center_rect/4` and `session_rect/3` give them.
  """
  @spec center_region(pos_integer(), pos_integer(), map() | nil) :: Panel.rect()
  def center_region(w, h, input \\ nil), do: wide_columns(w, body_height(w, h, input)).center

  @doc """
  The content rect the right SESSION pane's PTY renders into — the same split `compose/3` places the
  pane into, so the attached tmux client is sized to exactly what's on screen (one authority, like
  `center_rect/3` for the centre).
  """
  @spec session_rect(pos_integer(), pos_integer(), map() | nil) :: Panel.rect()
  def session_rect(w, h, input \\ nil), do: inset(wide_columns(w, body_height(w, h, input), true).right)

  # The body both rects live in — the frame less the two bars AND the open composer, exactly as
  # `compose/3` computes it, so a PTY attached while `c` is open isn't sized over the compose box.
  defp body_height(w, h, input), do: max(h - @top_h - @status_h - composer_height(%{input: input}, w, h), 1)

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

  @doc false
  # A keyed surface section reads its data directly; a bare module resolves via data_for/2. The
  # 4-arity variant injects the focused pane's `selected` cursor into its data (nil elsewhere).
  # Public for the drawer (`Console.Cockpit.Drawer`), which places the same panels over the centre
  # and must resolve their data the one way the frame does.
  def content_for(section, reads, rect, slice) do
    {panel, data, rect} = content_for(section, reads, rect)
    {panel, data |> merge_slice(slice) |> follow_cursor(rect), rect}
  end

  # A pane whose j/k cursor is an ABSOLUTE row index (the rail) is windowed by `render_scroll` over
  # those same absolute rows, so the window must follow the cursor — else j walks the selection off
  # the visible rail and Enter acts on a row nobody can see. The wheel offset is the starting point;
  # it only moves as far as it must to keep the cursor on screen.
  defp follow_cursor(%{selected: selected, scroll: scroll} = data, %{h: h}) when is_integer(selected) and h > 0,
    do: %{data | scroll: scroll |> min(selected) |> max(selected - h + 1) |> max(0)}

  defp follow_cursor(data, _rect), do: data

  defp content_for({panel, read_key}, reads, rect), do: {panel, scroll_data(panel, reads[read_key], reads), rect}
  defp content_for(panel, reads, rect), do: {panel, scroll_data(panel, data_for(panel, reads), reads), rect}

  defp merge_slice(data, nil), do: data
  defp merge_slice(data, slice) when is_map(data), do: Map.merge(data, slice)
  defp merge_slice(data, _slice), do: data

  @doc "Resolve the data a panel is fed from the assembled reads (keeps spaces plain data)."
  def data_for(Panel.Rail, r), do: %{groups: r[:sidebar] || [], active_key: r.active_key, opened: opened_id(r)}

  def data_for(Panel.Roster, r), do: %{sessions: r.roster}

  # CONFIG's workspace list — `Console.Workspaces.all/0` directly, so a thread-less workspace (a
  # fresh "blank" template) is real here (D2.2). `edit` (D2.4 Chunk 2a) is nil unless `e`
  # opened the field editor — `Panel.Author` switches its render on its presence.
  def data_for(Panel.Author, r),
    do: %{workspaces: author_workspaces(), cursor: r[:author_cursor] || 0, edit: r[:author_edit]}

  def data_for(Panel.Stack, r), do: r.stack
  def data_for(Panel.Crew, r), do: r[:crew]
  def data_for(Panel.Activity, r), do: %{events: r[:activity] || [], gates: r[:gates] || []}
  # The permanent tertius band (Slice 3): the orchestrator input + a short receipts log.
  def data_for(Panel.Tertius, r), do: %{receipts: r[:receipts] || [], input: r[:input]}
  def data_for(Panel.NewThread, r), do: %{input: r[:input]}
  def data_for(Panel.Reply, r), do: %{input: r[:input]}
  def data_for(Panel.Triage, r), do: r[:triage]
  # HEALTH is a drawer pane now (the footer's old health segment) — the same probe read the
  # composer's /status readout flattens.
  def data_for(Panel.Health, r), do: r[:health]
  def data_for(Panel.Memory, r), do: r[:memory]
  def data_for(Panel.Detail, r), do: r[:detail]
  # The stand-in's line is its own (Panel.Placeholder.copy/0) — nothing to resolve from the reads.
  def data_for(Panel.Placeholder, _r), do: %{}
  def data_for(_other, _r), do: nil

  # Inject the panel's current scroll offset into scrollable panels' data (nil data left alone — a
  # panel with no data renders its placeholder, no scroll needed).
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

  # The top bar's read (UX slice 1): where you are, what you're on, who is on it, is the server up.
  # The thread/stage/lead the old footer info row carried moved HERE — the footer is hints only now.
  defp top_data(reads, space) do
    card = opened_card(reads)
    lead = card && lead_of(reads, card.id)

    %{
      workspace: space.label,
      thread: card && card[:title],
      stage: card && card[:stage],
      lead: lead && lead.agent,
      warm?: lead != nil and lead.warm? == true,
      link: reads[:link] || :up
    }
  end

  # The OPEN thread's card (design 2026-09-08 §2), never the rail's selection cursor — nothing open,
  # nothing named. Same thread_stack read the center's list⇄conversation switch uses, so the bar and
  # the center can never disagree about what is open.
  defp opened_card(%{thread_stack: %{opened: id, cards: cards}}) when not is_nil(id), do: Enum.find(cards, &(&1.id == id))

  defp opened_card(_reads), do: nil

  # The OPEN thread's id — what the rail marks and the top bar names, off the one thread_stack read.
  defp opened_id(%{thread_stack: %{opened: id}}), do: id
  defp opened_id(_reads), do: nil

  # The roster row working that thread (agent + warmth), or nil.
  defp lead_of(reads, id), do: Enum.find(reads[:roster] || [], &(&1.thread_id == id))

  defp status_data(reads, focused) do
    %{
      # When the operator is typing a new-thread title, the footer becomes the prompt.
      input: reads[:input],
      # A transient result line (a spawn's pane id or failure), shown until the next keypress.
      flash: reads[:flash],
      # True for the one keypress after Ctrl+Space — the hints line shows the armed-prefix state.
      leader_pending?: reads[:leader_pending?],
      # The contextual footer's keys (design 2026-08-23) — workspace-ness, never the label.
      mode: footer_mode(reads),
      workspace?: Space.workspace?(reads.active_key),
      # Which way Alt+\ is set, so the footer's pane verb names the mode it is in.
      session_pane_mode: reads[:session_pane_mode],
      pane_hints: pane_hints(reads, focused)
    }
  end

  # The open drawer is its own mode: it owns every key, so the footer names ITS verbs (task 4).
  defp footer_mode(%{drawer: key}) when not is_nil(key), do: :drawer
  defp footer_mode(%{lock?: true}), do: :lock
  defp footer_mode(%{focus: %Focus{in_terminal?: true}}), do: :term
  defp footer_mode(%{focus: %Focus{}}), do: :nav
  defp footer_mode(_reads), do: nil

  # The focused pane's declared verbs.
  defp pane_hints(_reads, nil), do: []

  defp pane_hints(reads, focused) do
    {panel, data, _rect} = content_for(focused, reads, %{x: 0, y: 0, w: 40, h: 10})
    Panel.hints(panel, data)
  end

  @gap 1

  # Stack sections vertically down a column as box rects, a 1-row gap between them. The picker
  # takes a fixed height, the rest split the remainder (the last absorbs the rounding remainder).
  defp boxed(panels, rect, overrides \\ %{})
  defp boxed([], _rect, _overrides), do: []

  defp boxed(panels, %{x: x, y: y, w: w, h: h}, overrides) do
    gaps = max(length(panels) - 1, 0) * @gap
    # The section budget is the column minus the inter-section gaps; never inflate it past what
    # fits (a `length(panels)` floor would push short columns off-frame). split_heights/2 fits the
    # sections into exactly this budget, so no placed box's `y + h` ever exceeds the column bottom.
    heights = split_heights(panels, max(h - gaps, 0), overrides)

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
  defp split_heights(panels, total_h, overrides) do
    fixed = Enum.map(panels, fn p -> Map.get(overrides, p) || fixed_height(p) end)
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

  # The tertius band: the input line + up to 2 receipts, plus the 2-row frame.
  defp fixed_height(Panel.Tertius), do: 5
  # The new-thread band and its conversation-step twin, the reply band: one input row + the 2-row frame.
  defp fixed_height(Panel.NewThread), do: 3
  defp fixed_height(Panel.Reply), do: 3
  defp fixed_height({panel, _read_key}), do: fixed_height(panel)
  defp fixed_height(_panel), do: nil
end
