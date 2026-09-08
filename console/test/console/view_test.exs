defmodule Console.ViewTest do
  @moduledoc """
  The composition layer as plain data (design §3): `Console.View.compose/3` turns the assembled
  reads + a size into placed `{panel, data, rect}` boxes, no TTY. These tests pin the Tlön focus
  highlight — the lazygit "active pane" cue — so a regression (nothing lights, or the wrong column
  lights) is caught headlessly.
  """
  use ExUnit.Case, async: true

  alias Console.Panel
  alias Console.Tlon.Focus
  alias Console.View

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

  # A minimal reads map: compose only needs the keys to exist (it lays out boxes; panel content is
  # rendered later), so the data can be empty/nil. Overrides set the space + focus under test.
  defp reads(overrides) do
    Map.merge(
      %{
        active_key: 0,
        focus: nil,
        focused_id: nil,
        focused_title: nil,
        threads: [],
        roster: [],
        chorus: [],
        machine: :no_session,
        stack: nil,
        health: nil,
        triage: nil,
        scrolls: %{},
        input: nil,
        flash: nil,
        leader_pending?: false,
        tlon_layout: nil,
        detail: nil
      },
      overrides
    )
  end

  # A Tlön layout with a commits count, so Focus.cursor/2 clamps and the Stack pane is navigable.
  # Mirrors production `tlon_layout` since nav v2: the RAIL is the focus nav (`left`), the spine is
  # not navigable (`right` empty). STACK is rail (left) pane 3.
  defp layout(counts \\ %{Panel.Stack => 3}),
    do: %{left: [Panel.Activity, Panel.Crew, Panel.Memory, Panel.Stack], right: [], sections: %{}, counts: counts}

  # The rects of every border flagged as focused.
  defp focused_borders(placements), do: for({Panel.Border, %{focused: true}, rect} <- placements, do: rect)

  describe "the Slack sidebar (reshape slice D)" do
    test "the left column leads with Panel.Sidebar fed from reads[:sidebar]; SPACES is gone" do
      groups = [%{workspace: %{id: 1, name: "ficciones"}, threads: [], crew: []}]
      placements = View.compose(reads(%{active_key: :orbis, sidebar: groups}), 120, 40)

      assert {Panel.Sidebar, data, _rect} =
               Enum.find(placements, &match?({Panel.Sidebar, _, _}, &1))

      assert data.groups == groups
      assert data.active_key == :orbis
      refute Enum.any?(placements, &match?({Panel.Spaces, _, _}, &1))
    end

    test "a missing sidebar read degrades to empty groups, not a crash" do
      placements = View.compose(reads(%{active_key: :orbis}), 120, 40)
      assert {Panel.Sidebar, %{groups: []}, _rect} = Enum.find(placements, &match?({Panel.Sidebar, _, _}, &1))
    end
  end

  describe "the center [chat]|[terminal] toggle (reshape slice D)" do
    defp placed?(placements, mod), do: Enum.any?(placements, &match?({^mod, _, _}, &1))

    test "center_view :chat swaps the Terminal section for the thread stack (Slice 3)" do
      stack = %{
        cards: [%{id: 1, title: "a", lead: nil, stage: nil, awaiting: nil, folded?: false, active?: true, messages: []}]
      }

      placements = View.compose(reads(%{center_view: :chat, thread_stack: stack}), 120, 40)

      assert {Panel.ThreadStack, data, _rect} = Enum.find(placements, &match?({Panel.ThreadStack, _, _}, &1))
      assert [%{id: 1}] = data.cards
      refute placed?(placements, Panel.Terminal)
      # the tertius band still frames the stack below
      assert placed?(placements, Panel.Tertius)
    end

    test "the bottom band morphs with the center step: NewThread in the list, Reply in a conversation" do
      card = %{id: 7, title: "a", lead: nil, stage: nil, awaiting: nil, folded?: false, active?: true, messages: []}

      # LIST step (thread_stack.opened == nil): the new-thread band shows, no reply band.
      list = View.compose(reads(%{center_view: :chat, thread_stack: %{cards: [card], opened: nil}}), 120, 40)
      assert placed?(list, Panel.NewThread)
      refute placed?(list, Panel.Reply)

      # CONVERSATION step (thread_stack.opened set, its reply input seeded): Reply replaces NewThread.
      # `opened` is read off the same thread_stack the center's list⇄conversation switch uses.
      convo =
        View.compose(
          reads(%{
            center_view: :chat,
            thread_stack: %{cards: [card], opened: 7},
            input: %{kind: :reply, thread_id: 7, buffer: "", cursor: 0}
          }),
          120,
          40
        )

      assert placed?(convo, Panel.Reply)
      refute placed?(convo, Panel.NewThread)
    end

    test "center_view :terminal (the default) keeps the live PTY" do
      placements = View.compose(reads(%{center_view: :terminal}), 120, 40)
      assert placed?(placements, Panel.Terminal)
      refute placed?(placements, Panel.ThreadStack)
    end

    test "a reads map without center_view (older/minimal) defaults to the terminal" do
      placements = View.compose(reads(%{}), 120, 40)
      assert placed?(placements, Panel.Terminal)
    end

    test "an open detail still outranks the chat face" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, detail?: true}
      detail = %{title: "commit abc · x", lines: [{"+added", :diff_add}]}
      stack = %{cards: [], opened: nil}

      placements =
        View.compose(
          reads(%{focus: focus, tlon_layout: layout(), detail: detail, center_view: :chat, thread_stack: stack}),
          120,
          40
        )

      assert placed?(placements, Panel.Detail)
      refute placed?(placements, Panel.ThreadStack)
    end
  end

  describe "the toggleable right session pane (2026-08-31)" do
    defp chat_reads(overrides) do
      stack = %{
        cards: [%{id: 7, title: "a", lead: nil, stage: nil, awaiting: nil, folded?: false, active?: true, messages: []}]
      }

      reads(Map.merge(%{center_view: :chat, thread_stack: stack}, overrides))
    end

    test "off (default): no session terminal; the stack spans the center" do
      placements = View.compose(chat_reads(%{}), 120, 40)
      refute placed?(placements, Panel.Terminal)
      assert placed?(placements, Panel.ThreadStack)
    end

    test "on: a right session pane appears and narrows the stack" do
      wide = View.compose(chat_reads(%{}), 120, 40)
      {_, _, wide_stack} = Enum.find(wide, &match?({Panel.ThreadStack, _, _}, &1))

      placements = View.compose(chat_reads(%{session_pane: 7, session: :no_session}), 120, 40)
      assert {Panel.Terminal, _data, sess_rect} = Enum.find(placements, &match?({Panel.Terminal, _, _}, &1))
      {_, _, narrow_stack} = Enum.find(placements, &match?({Panel.ThreadStack, _, _}, &1))

      # the stack gave up width to the session pane, which sits to its right
      assert narrow_stack.w < wide_stack.w
      assert sess_rect.x > narrow_stack.x
    end
  end

  describe "the funes rail (Slice 3.4)" do
    test "the rail stacks NOW·CREW·MEMORY·STACK to the right of the spine; no right rail" do
      placements = View.compose(reads(%{}), 120, 40)

      # Every funes panel is placed, stacked in a single rail column (all at the same x, past the spine).
      rail_rects =
        for mod <- [Panel.Activity, Panel.Crew, Panel.Memory, Panel.Stack] do
          assert {_p, _d, rect} = Enum.find(placements, &match?({^mod, _, _}, &1)), "#{inspect(mod)} not placed"
          rect
        end

      assert Enum.all?(rail_rects, &(&1.x > 0))
      assert rail_rects |> Enum.map(& &1.x) |> Enum.uniq() |> length() == 1
    end
  end

  describe "Tlön focus highlight" do
    test "in nav mode, exactly one RAIL border lights — the focused pane (nav v2)" do
      # Nav v2: the focus nav is the rail (Focus `left` column); the spine is not navigable.
      focus = %Focus{in_terminal?: false, column: :left, pane: 0}
      placements = View.compose(reads(%{focus: focus}), 120, 40)

      assert [rect] = focused_borders(placements)
      # The rail sits to the RIGHT of the thin spine — the lit pane is past x = 0.
      assert rect.x > 0
    end

    test "moving down the rail lights a different rail border" do
      p0 = View.compose(reads(%{focus: %Focus{in_terminal?: false, column: :left, pane: 0}}), 120, 40)
      p1 = View.compose(reads(%{focus: %Focus{in_terminal?: false, column: :left, pane: 1}}), 120, 40)

      assert [r0] = focused_borders(p0)
      assert [r1] = focused_borders(p1)
      assert r0.y != r1.y
    end

    test "in the terminal (default focus), no border is highlighted — the terminal is the active pane" do
      placements = View.compose(reads(%{focus: Focus.new()}), 120, 40)
      assert focused_borders(placements) == []
    end

    test "a non-Tlön space (focus nil) never highlights a border" do
      placements = View.compose(reads(%{active_key: :orbis, focus: nil}), 120, 40)
      assert focused_borders(placements) == []
    end
  end

  describe "MAIN detail (Enter)" do
    # The Terminal keyed section, if present.
    defp terminal_placed?(placements), do: Enum.any?(placements, &match?({Panel.Terminal, _, _}, &1))

    defp detail_placed?(placements), do: Enum.any?(placements, &match?({Panel.Detail, _, _}, &1))

    test "with a detail open and resolved, MAIN shows Panel.Detail instead of the terminal" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, detail?: true}
      detail = %{title: "commit abc · x", lines: [{"+added", :diff_add}]}

      placements =
        View.compose(reads(%{focus: focus, tlon_layout: layout(), detail: detail}), 120, 40)

      assert detail_placed?(placements)
      refute terminal_placed?(placements)
    end

    test "detail? on but nothing resolved (nil) leaves the terminal in place" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, detail?: true}

      placements =
        View.compose(reads(%{focus: focus, tlon_layout: layout(), detail: nil}), 120, 40)

      refute detail_placed?(placements)
      assert terminal_placed?(placements)
    end
  end

  describe "Orbis' author face (D2.1)" do
    defp chorus_placed?(placements), do: Enum.any?(placements, &match?({Panel.Overview, _, _}, &1))
    defp author_placed?(placements), do: Enum.any?(placements, &match?({Panel.Author, _, _}, &1))

    test "orbis_face == :author replaces Overview with Panel.Author" do
      placements = View.compose(reads(%{active_key: :orbis, orbis_face: :author}), 120, 40)
      assert author_placed?(placements)
      refute chorus_placed?(placements)
    end

    test "orbis_face == :survey (the default) keeps Overview, no Panel.Author" do
      placements = View.compose(reads(%{active_key: :orbis, orbis_face: :survey}), 120, 40)
      refute author_placed?(placements)
      assert chorus_placed?(placements)
    end

    test "orbis_face absent from reads (an older/minimal reads map) defaults to the survey" do
      placements = View.compose(reads(%{active_key: :orbis}), 120, 40)
      refute author_placed?(placements)
      assert chorus_placed?(placements)
    end

    test "orbis_face == :author outside Orbis is inert — only Orbis' center swaps" do
      placements = View.compose(reads(%{active_key: 0, orbis_face: :author}), 120, 40)
      refute author_placed?(placements)
    end
  end

  describe "item selection" do
    # The data handed to a given panel module in the placements.
    defp panel_data(placements, mod) do
      Enum.find_value(placements, fn
        {^mod, data, _rect} -> {:ok, data}
        _ -> nil
      end)
    end

    test "the focused pane gets its cursor + section as a slice; other panes don't" do
      # Nav v2: the rail is the focus `left` column — STACK is left pane 3 (NOW·CREW·MEMORY·STACK).
      focus = %Focus{
        in_terminal?: false,
        column: :left,
        pane: 3,
        cursors: %{Panel.Stack => 2},
        section: 0,
        detail?: false
      }

      stack = %{
        branch: nil,
        dirty: false,
        ahead: nil,
        behind: nil,
        status_summary: nil,
        commits: [],
        tools: []
      }

      memory = %{coverage: nil, pinned: [], habits: []}

      placements =
        View.compose(
          reads(%{focus: focus, tlon_layout: layout(), stack: stack, memory: memory}),
          120,
          40
        )

      assert {:ok, %{selected: 2, section: 0}} = panel_data(placements, Panel.Stack)
      # Memory (rail pane 2, not focused) gets no slice merged in.
      assert {:ok, mem} = panel_data(placements, Panel.Memory)
      refute Map.has_key?(mem, :selected)
    end
  end

  # The funes rail (Slice 3.4): NOW·CREW·MEMORY·STACK all stack in one column — no carousel, no
  # cycling. HEALTH stays in the footer + /status; the center thread-stack is the thread list.
  describe "the funes rail stacks (Slice 3.4)" do
    defp right_placed?(placements, mod), do: Enum.any?(placements, &match?({^mod, _, _}, &1))

    test "all four funes panels are placed; HEALTH is not" do
      placements = View.compose(reads(%{active_key: 0, tlon_layout: layout()}), 120, 40)

      assert right_placed?(placements, Panel.Activity)
      assert right_placed?(placements, Panel.Crew)
      assert right_placed?(placements, Panel.Memory)
      assert right_placed?(placements, Panel.Stack)
      refute right_placed?(placements, Panel.Health)
    end

    test "the rail panels stack top-down in NOW·CREW·MEMORY·STACK order" do
      placements = View.compose(reads(%{}), 120, 40)

      ys =
        for mod <- [Panel.Activity, Panel.Crew, Panel.Memory, Panel.Stack] do
          {_p, _d, rect} = Enum.find(placements, &match?({^mod, _, _}, &1))
          rect.y
        end

      assert ys == Enum.sort(ys)
    end

    test "the Orbis god-view carries no funes rail" do
      placements = View.compose(reads(%{active_key: :orbis, focus: nil}), 120, 40)
      refute right_placed?(placements, Panel.Stack)
    end

    test "a short frame never places a box (or its content) past the body — the status rows stay clean" do
      # Regression: the pinned head's intrinsic height could leave the carousel a 1-row sliver,
      # whose inset content landed one row PAST the column bottom (on the status bar). The
      # invariant is total: at any height, every non-status placement fits inside body_h. Boxes
      # too short for a real frame (h < 2) must be dropped whole, never emitted as slivers.
      for h <- [4, 8, 15] do
        placements = View.compose(reads(%{}), 120, h)
        # The body sits between the two one-row bars (UX slice 1): rows 1..h-2.
        body_bottom = h - 1

        for {panel, _data, rect} <- placements, panel not in [Panel.TopBar, Panel.StatusBar] do
          assert rect.y >= 1 and rect.y + rect.h <= body_bottom,
                 "#{inspect(panel)} ends past the body at 120x#{h}: #{inspect(rect)} (bottom #{body_bottom})"
        end
      end
    end
  end

  # UX slice 1, task 1: the frame gains a one-line top bar and its footer shrinks to one line, so
  # the body is exactly the rows between them.
  describe "the frame's bars (UX slice 1)" do
    test "row 0 is the TopBar, the last row is a one-line StatusBar, the body is between" do
      boxes = View.compose(reads(%{}), 120, 40)

      assert {Panel.TopBar, _, %{x: 0, y: 0, w: 120, h: 1}} = Enum.find(boxes, &match?({Panel.TopBar, _, _}, &1))
      assert {Panel.StatusBar, _, %{x: 0, y: 39, w: 120, h: 1}} = Enum.find(boxes, &match?({Panel.StatusBar, _, _}, &1))

      body = for {p, _, r} <- boxes, p not in [Panel.TopBar, Panel.StatusBar], do: r
      assert body != []
      assert Enum.all?(body, &(&1.y >= 1 and &1.y + &1.h <= 39))
    end

    test "the top bar reads the space, the focused thread and its lead's warmth" do
      roster = [%{agent: "hronir", thread_id: 7, thread_title: "review PR 42", pane_ref: nil, warm?: true}]

      cards = [
        %{id: 7, title: "review PR 42", lead: nil, stage: "build", awaiting: nil, active?: true, messages: []}
      ]

      boxes =
        View.compose(
          reads(%{
            focused_id: 7,
            focused_title: "review PR 42",
            roster: roster,
            thread_stack: %{cards: cards, opened: 7}
          }),
          120,
          40
        )

      assert {Panel.TopBar, data, _} = Enum.find(boxes, &match?({Panel.TopBar, _, _}, &1))
      assert data.thread == "review PR 42"
      assert data.stage == "build"
      assert data.lead == "hronir"
      assert data.warm? == true
      # The link is an ambient read resolved in Console.Reads.frame/3 — compose/3 only forwards it.
      assert data.link == :up
    end

    test "a down link rides the frame read through to the bar" do
      boxes = View.compose(reads(%{link: :down}), 120, 40)

      assert {Panel.TopBar, %{link: :down}, _} = Enum.find(boxes, &match?({Panel.TopBar, _, _}, &1))
    end

    # Design 2026-09-08 §2: the top bar carries the OPEN thread, not the rail's selection cursor.
    test "the top bar names the OPENED thread, not the one the cursor sits on" do
      roster = [%{agent: "hronir", thread_id: 7, thread_title: "review PR 42", pane_ref: nil, warm?: true}]

      cards = [
        %{id: 7, title: "review PR 42", lead: nil, stage: "build", awaiting: nil, active?: false, messages: []},
        %{id: 9, title: "flaky test hunt", lead: nil, stage: "triage", awaiting: nil, active?: true, messages: []}
      ]

      boxes =
        View.compose(
          reads(%{
            focused_id: 9,
            focused_title: "flaky test hunt",
            roster: roster,
            thread_stack: %{cards: cards, opened: 7}
          }),
          120,
          40
        )

      assert {Panel.TopBar, data, _} = Enum.find(boxes, &match?({Panel.TopBar, _, _}, &1))
      assert data.thread == "review PR 42"
      assert data.stage == "build"
      assert data.lead == "hronir"
    end

    test "nothing opened: no thread segment at all — the cursor is not a fallback" do
      roster = [%{agent: "hronir", thread_id: 9, thread_title: "flaky test hunt", pane_ref: nil, warm?: true}]

      cards = [
        %{id: 9, title: "flaky test hunt", lead: nil, stage: "triage", awaiting: nil, active?: true, messages: []}
      ]

      boxes =
        View.compose(
          reads(%{
            focused_id: 9,
            focused_title: "flaky test hunt",
            roster: roster,
            thread_stack: %{cards: cards, opened: nil}
          }),
          120,
          40
        )

      assert {Panel.TopBar, data, _} = Enum.find(boxes, &match?({Panel.TopBar, _, _}, &1))
      assert data.thread == nil
      assert data.stage == nil
      assert data.lead == nil
      refute data.warm?
    end

    test "an open composer still sits directly above the (now one-row) footer" do
      input = %{kind: :compose, thread_id: 1, buffer: "one\ntwo", cursor: 7}
      boxes = View.compose(reads(%{input: input}), 120, 40)

      assert {Panel.Composer, _, rect} = Enum.find(boxes, &match?({Panel.Composer, _, _}, &1))
      assert rect.y == 40 - 1 - 2
    end
  end

  describe "compose box" do
    defp composer_placements(placements), do: for({Panel.Composer, data, rect} <- placements, do: {data, rect})

    test "no composer is placed while the input is closed" do
      assert composer_placements(View.compose(reads(%{}), 120, 40)) == []
    end

    test "an open composer places a box above the status bar sized to the wrapped line count" do
      input = %{kind: :compose, thread_id: 1, buffer: "one\ntwo\nthree", cursor: 13}
      placements = View.compose(reads(%{input: input}), 120, 40)

      assert [{%{input: ^input}, rect}] = composer_placements(placements)
      assert rect.h == 3
      # Directly above the one-row status footer, full width.
      assert rect.y == 40 - 1 - 3
      assert rect.w == 120
    end

    test "the box height caps at half the frame — a huge draft scrolls instead of swallowing the screen" do
      buffer = Enum.map_join(1..60, "\n", &"l#{&1}")
      input = %{kind: :compose, thread_id: 1, buffer: buffer, cursor: String.length(buffer)}

      assert [{_data, rect}] = composer_placements(View.compose(reads(%{input: input}), 120, 40))
      assert rect.h == 20
    end
  end

  describe "border titles + digits (clarity slice 1)" do
    defp border_of(placements, title) do
      Enum.find_value(placements, fn
        {Panel.Border, %{title: ^title} = data, _rect} -> data
        _ -> nil
      end)
    end

    test "boxes carry plain titles, NO pane digits (nav v2)" do
      placements = View.compose(reads(%{}), 120, 40)

      # The spine + rail borders show their title only — no leading number (digit is nil).
      assert %{digit: nil} = border_of(placements, "WS")
      assert %{digit: nil} = border_of(placements, "NOW")
      assert %{digit: nil} = border_of(placements, "CREW")
      assert %{digit: nil} = border_of(placements, "MEMORY")
      assert %{digit: nil} = border_of(placements, "STACK")
    end

    test "orbis boxes are titled too (shared pieces inherit)" do
      placements = View.compose(reads(%{active_key: :orbis, focus: nil}), 120, 40)
      # Orbis' rail is [Roster (ACTIVE), Triage (TRIAGE)] now — the retired BRIEF is gone.
      assert border_of(placements, "ACTIVE")
      assert border_of(placements, "TRIAGE")
      refute border_of(placements, "BRIEF")
    end
  end

  describe "contextual footer data (clarity slice 3)" do
    defp status_of(placements),
      do:
        Enum.find_value(placements, fn
          {Panel.StatusBar, data, _rect} -> data
          _ -> nil
        end)

    test "workspace + nav: mode :nav, workspace? true, and no retired carousel [/] hint" do
      focus = %Focus{in_terminal?: false, column: :right, pane: 1}
      data = status_of(View.compose(reads(%{focus: focus}), 120, 40))

      assert data.mode == :nav
      assert data.workspace? == true
      # The carousel is retired — no `[/]` view-cycle hint is appended to any rail pane.
      refute {"[/]", "view"} in data.pane_hints
    end

    test "workspace + terminal: mode :term, no pane hints" do
      data = status_of(View.compose(reads(%{focus: Focus.new()}), 120, 40))
      assert data.mode == :term
      assert data.pane_hints == []
    end

    test "orbis: mode nil (the shared table)" do
      data = status_of(View.compose(reads(%{active_key: :orbis, focus: nil}), 120, 40))
      assert data.mode == nil
      assert data.workspace? == false
    end

    test "a focused Stack pane's own verbs ride through" do
      # Nav v2: STACK is the last RAIL pane (left pane 3: NOW·CREW·MEMORY·STACK).
      focus = %Focus{in_terminal?: false, column: :left, pane: 3}
      data = status_of(View.compose(reads(%{focus: focus}), 120, 40))
      assert {"⏎", "diff"} in data.pane_hints
    end
  end
end
