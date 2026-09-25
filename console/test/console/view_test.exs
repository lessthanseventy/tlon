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
        tlon_layout: nil,
        detail: nil
      },
      overrides
    )
  end

  # A Tlön layout with item counts, so Focus.cursor/2 clamps against something. Mirrors production
  # `tlon_layout` (the focus walks the `left` column; `right` is empty).
  defp layout(counts \\ %{Panel.Rail => 3}), do: %{left: [Panel.Rail], right: [], sections: %{}, counts: counts}

  # The rects of every border flagged as focused.
  defp focused_borders(placements), do: for({Panel.Border, %{focused: true}, rect} <- placements, do: rect)

  # UX slice 1, task 4: the drawer is painted over the frame by the cockpit, but the FOOTER is the
  # View's — while it's open the footer must name the drawer's verbs and the open pane's, never the
  # rail's (the rail isn't walkable then).
  describe "the footer while the drawer is open" do
    test "the footer is in DRAWER mode and carries the open pane's hints" do
      reads = reads(%{active_key: 0, drawer: :memory, focus: %Focus{in_terminal?: false}, memory: nil})
      data = status_of(View.compose(reads, 120, 40))

      assert data.mode == :drawer
      assert data.pane_hints == Panel.Memory.hints(nil)
    end

    test "with it shut the footer is the rail's again" do
      reads = reads(%{active_key: 0, drawer: nil, focus: %Focus{in_terminal?: false}, tlon_layout: layout()})
      data = status_of(View.compose(reads, 120, 40))

      assert data.mode == :nav
      assert data.pane_hints == Panel.Rail.hints(nil)
    end
  end

  # UX slice 1, task 2: ONE rail (workspaces + the active workspace's threads) at x 0 — the thin
  # spine (the old Sidebar, deleted) and the funes rail (space.left) are no longer placed; the drawer hosts
  # those panes from task 4.
  describe "the rail replaces the Slack sidebar (UX slice 1)" do
    defp rail_of(placements), do: Enum.find(placements, &match?({Panel.Rail, _, _}, &1))

    # The rail's BOX (its bordered rect) — the content placement is inset inside it.
    defp rail_box(placements) do
      Enum.find_value(placements, fn
        {Panel.Border, %{title: "RAIL"}, rect} -> rect
        _ -> nil
      end)
    end

    test "the left column IS Panel.Rail, fed from reads[:sidebar]; the spine is gone" do
      groups = [%{workspace: %{id: 0, name: "ficciones"}, threads: [], crew: []}]
      placements = View.compose(reads(%{sidebar: groups}), 120, 40)

      assert {Panel.Rail, data, _rect} = rail_of(placements)
      assert data.groups == groups
      assert data.active_key == 0
      assert %{x: 0, y: 1} = rail_box(placements)
      refute Enum.any?(placements, &match?({Panel.Spaces, _, _}, &1))
    end

    test "the rail carries the OPENED thread, so it can mark the one the center holds" do
      stack = %{cards: [], opened: 7}
      assert {Panel.Rail, %{opened: 7}, _} = rail_of(View.compose(reads(%{thread_stack: stack}), 120, 40))
      assert {Panel.Rail, %{opened: nil}, _} = rail_of(View.compose(reads(%{}), 120, 40))
    end

    test "a fifth of the frame, floored at 22 columns (and never past a third)" do
      assert %{w: 24} = rail_box(View.compose(reads(%{}), 120, 40))
      assert 24 == max(22, div(120, 5))
      # At the wide threshold a fifth is under the floor, so the floor wins. The third-of-the-frame
      # cap never binds at a wide width (a fifth is always under a third) — it is kept as the guard
      # for the narrow/derived sizes `center_rect/3` can be asked for, and is not exercised here.
      assert %{w: 22} = rail_box(View.compose(reads(%{}), 82, 40))
    end

    test "the center starts one column right of the rail" do
      placements = View.compose(reads(%{}), 120, 40)
      rail = rail_box(placements)

      boxes =
        for {Panel.Border, %{title: title}, rect} <- placements, title != "RAIL", do: rect

      assert boxes != []
      assert Enum.all?(boxes, &(&1.x >= rail.x + rail.w + 1))
    end

    # The rail's j/k cursor is an ABSOLUTE row index and the scroll window is taken over the same
    # absolute rows, so the window has to follow the cursor or j walks it off the visible rail.
    test "the scroll window follows the j/k cursor: down past the last visible row scrolls" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, cursors: %{Panel.Rail => 40}}
      placements = View.compose(reads(%{focus: focus, tlon_layout: layout(%{Panel.Rail => 60})}), 120, 40)

      assert {Panel.Rail, %{scroll: scroll, selected: 40}, rect} = rail_of(placements)
      assert scroll == 40 - rect.h + 1
      assert scroll > 0
    end

    test "a cursor already inside the window leaves the offset alone" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, cursors: %{Panel.Rail => 2}}
      placements = View.compose(reads(%{focus: focus, tlon_layout: layout(%{Panel.Rail => 60})}), 120, 40)

      assert {Panel.Rail, %{scroll: 0}, _rect} = rail_of(placements)
    end

    test "a wheel scroll past the cursor snaps back so the cursor stays on screen" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, cursors: %{Panel.Rail => 2}}

      placements =
        View.compose(
          reads(%{focus: focus, tlon_layout: layout(%{Panel.Rail => 60}), scrolls: %{Panel.Rail => 30}}),
          120,
          40
        )

      assert {Panel.Rail, %{scroll: 2}, _rect} = rail_of(placements)
    end

    test "a missing sidebar read degrades to empty groups, not a crash" do
      assert {Panel.Rail, %{groups: []}, _rect} = rail_of(View.compose(reads(%{}), 120, 40))
    end

    test "the narrow layout stacks the rail above the center" do
      placements = View.compose(reads(%{}), 60, 30)
      rail = rail_box(placements)
      assert %{x: 0, y: 1, w: 60} = rail

      boxes = for {Panel.Border, %{title: title}, rect} <- placements, title != "RAIL", do: rect
      assert Enum.all?(boxes, &(&1.y >= rail.y + rail.h))
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

  describe "the toggleable right session pane (UX slice 1)" do
    # The chat centre, optionally with a thread OPEN — the two-pane frame keys off the open
    # conversation, the same read the centre's list⇄conversation switch uses.
    defp chat_reads(overrides, opened \\ nil) do
      stack = %{
        cards: [%{id: 7, title: "a", lead: nil, stage: nil, awaiting: nil, folded?: false, active?: true, messages: []}],
        opened: opened
      }

      reads(Map.merge(%{center_view: :chat, thread_stack: stack}, overrides))
    end

    defp stack_rect(placements) do
      {_, _, rect} = Enum.find(placements, &match?({Panel.ThreadStack, _, _}, &1))
      rect
    end

    test "nothing open, no session: the conversation spans the centre" do
      placements = View.compose(chat_reads(%{}), 120, 40)
      refute placed?(placements, Panel.Terminal)
      refute placed?(placements, Panel.Placeholder)
      assert placed?(placements, Panel.ThreadStack)
    end

    test "a live session splits the centre into two EQUAL panes" do
      wide = stack_rect(View.compose(chat_reads(%{}), 120, 40))
      placements = View.compose(chat_reads(%{session_pane: 7, session: :no_session}, 7), 120, 40)

      assert {Panel.Terminal, _data, sess} = Enum.find(placements, &match?({Panel.Terminal, _, _}, &1))
      stack = stack_rect(placements)

      assert abs(stack.w - sess.w) <= 1
      assert sess.x > stack.x
      assert stack.w < wide.w
    end

    test "a thread open with no live session: the terminal's place carries the spawn verb, equally split" do
      placements = View.compose(chat_reads(%{}, 9), 120, 40)

      assert {Panel.Placeholder, %{}, right} = Enum.find(placements, &match?({Panel.Placeholder, _, _}, &1))
      stack = stack_rect(placements)

      refute placed?(placements, Panel.Terminal)
      assert abs(stack.w - right.w) <= 1
      assert right.x > stack.x
    end

    test "too narrow for two panes: the conversation spans it rather than halving to nothing" do
      placements = View.compose(chat_reads(%{}, 9), 90, 40)
      refute placed?(placements, Panel.Placeholder)
      assert stack_rect(placements).w == stack_rect(View.compose(chat_reads(%{}), 90, 40)).w
    end

    test "the pane forced OFF places no right box at all — not even the stand-in" do
      placements = View.compose(chat_reads(%{session_pane: nil, session_pane_mode: false}, 9), 120, 40)

      refute placed?(placements, Panel.Placeholder)
      refute placed?(placements, Panel.Terminal)
      assert stack_rect(placements).w == stack_rect(View.compose(chat_reads(%{}), 120, 40)).w
    end

    test "under :auto a live session does NOT split a frame below the two-pane floor" do
      narrow = View.compose(chat_reads(%{session_pane: 7, session_pane_mode: :auto, session: :no_session}, 7), 90, 40)

      refute placed?(narrow, Panel.Terminal)
      assert stack_rect(narrow).w == stack_rect(View.compose(chat_reads(%{}), 90, 40)).w
    end

    test "pinned ON, the pane splits below the floor too — that split was asked for" do
      placements =
        View.compose(chat_reads(%{session_pane: 7, session_pane_mode: true, session: :no_session}, 7), 90, 40)

      assert {Panel.Terminal, _data, sess} = Enum.find(placements, &match?({Panel.Terminal, _, _}, &1))
      assert sess.x > stack_rect(placements).x
    end

    test "the terminal centre never splits — the pane sits beside the CONVERSATION" do
      placements = View.compose(reads(%{thread_stack: %{cards: [], opened: 9}}), 120, 40)
      refute placed?(placements, Panel.Placeholder)
    end
  end

  # UX slice 1, task 2: the funes rail (NOW·CREW·MEMORY·STACK) is off the frame — the panels' modules
  # stay, the drawer hosts them from task 4.
  describe "the funes rail is off the frame (UX slice 1)" do
    test "none of the four funes panels is placed; the one rail is" do
      placements = View.compose(reads(%{}), 120, 40)

      for mod <- [Panel.Activity, Panel.Crew, Panel.Memory, Panel.Stack] do
        refute Enum.any?(placements, &match?({^mod, _, _}, &1)), "#{inspect(mod)} is still placed"
      end

      assert Enum.any?(placements, &match?({Panel.Rail, _, _}, &1))
    end
  end

  describe "Tlön focus highlight" do
    test "in nav mode, the RAIL's border lights — it is the whole left column now (UX slice 1)" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0}
      placements = View.compose(reads(%{focus: focus}), 120, 40)

      assert [rect] = focused_borders(placements)
      # The rail is the frame's left edge since the spine went.
      assert rect.x == 0
    end

    test "past the rail nothing lights — the left column holds exactly one pane" do
      placements = View.compose(reads(%{focus: %Focus{in_terminal?: false, column: :left, pane: 1}}), 120, 40)

      assert focused_borders(placements) == []
    end

    test "in the terminal (default focus), no border is highlighted — the terminal is the active pane" do
      placements = View.compose(reads(%{focus: Focus.new()}), 120, 40)
      assert focused_borders(placements) == []
    end

    test "a stale space key (focus nil) never highlights a border" do
      placements = View.compose(reads(%{active_key: 999, focus: nil}), 120, 40)
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

  describe "the top bar's worktree" do
    test "the open thread's cwd rides into the TopBar data; nothing open → nil" do
      reads = reads(%{thread_stack: %{cards: [%{id: 9, title: "t", stage: nil}], opened: 9}, cwd: "/r/.worktrees/t9"})
      {_, data, _} = Enum.find(View.compose(reads, 120, 40), &match?({Panel.TopBar, _, _}, &1))
      assert data.cwd == "/r/.worktrees/t9"

      closed = reads(%{thread_stack: %{cards: [], opened: nil}, cwd: "/r/.worktrees/t9"})
      {_, data, _} = Enum.find(View.compose(closed, 120, 40), &match?({Panel.TopBar, _, _}, &1))
      assert data.cwd == nil
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
      # UX slice 1: the rail IS the focus `left` column (left pane 0).
      focus = %Focus{
        in_terminal?: false,
        column: :left,
        pane: 0,
        cursors: %{Panel.Rail => 2},
        section: 0,
        detail?: false
      }

      placements =
        View.compose(
          reads(%{focus: focus, tlon_layout: layout(%{Panel.Rail => 5})}),
          120,
          40
        )

      assert {:ok, %{selected: 2, section: 0}} = panel_data(placements, Panel.Rail)
      # The tertius band (unfocused) gets no slice merged in.
      assert {:ok, tertius} = panel_data(placements, Panel.Tertius)
      refute Map.has_key?(tertius, :selected)
    end
  end

  # Every space gets the same frame now (UX slice 1): one rail, one center. The situational panes
  # (funes rail, Orbis' ACTIVE/TRIAGE) are drawer material from task 4.
  describe "one frame for every space (UX slice 1)" do
    defp right_placed?(placements, mod), do: Enum.any?(placements, &match?({^mod, _, _}, &1))

    test "a workspace gets the rail and no situational panes" do
      placements = View.compose(reads(%{active_key: 0, tlon_layout: layout()}), 120, 40)

      assert right_placed?(placements, Panel.Rail)

      for mod <- [Panel.Activity, Panel.Crew, Panel.Memory, Panel.Stack, Panel.Health] do
        refute right_placed?(placements, mod)
      end
    end

    test "a missing space (the server-down sentinel) gets the same rail, and neither ACTIVE nor TRIAGE" do
      placements = View.compose(reads(%{active_key: 0, focus: nil}), 120, 40)

      assert right_placed?(placements, Panel.Rail)
      refute right_placed?(placements, Panel.Roster)
      refute right_placed?(placements, Panel.Triage)
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

    test "the narrow layout gets the same two bars and keeps the body between them" do
      boxes = View.compose(reads(%{}), 60, 30)

      assert {Panel.TopBar, _, %{x: 0, y: 0, w: 60, h: 1}} = Enum.find(boxes, &match?({Panel.TopBar, _, _}, &1))
      assert {Panel.StatusBar, _, %{x: 0, y: 29, w: 60, h: 1}} = Enum.find(boxes, &match?({Panel.StatusBar, _, _}, &1))

      body = for {p, _, r} <- boxes, p not in [Panel.TopBar, Panel.StatusBar], do: r
      assert body != []
      assert Enum.all?(body, &(&1.y >= 1 and &1.y + &1.h <= 29))
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

    test "boxes carry NO pane digits (nav v2)" do
      placements = View.compose(reads(%{}), 120, 40)
      digits = for {Panel.Border, %{digit: d}, _rect} <- placements, do: d

      assert digits != []
      assert Enum.all?(digits, &is_nil/1)
    end

    test "the rail's box is titled, and the retired panes' titles are gone with them" do
      placements = View.compose(reads(%{}), 120, 40)

      assert %{digit: nil} = border_of(placements, "RAIL")
      refute border_of(placements, "WS")
      refute border_of(placements, "NOW")
      refute border_of(placements, "STACK")
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

    test "off a workspace key: mode nil (the shared table)" do
      data = status_of(View.compose(reads(%{active_key: :stale, focus: nil}), 120, 40))
      assert data.mode == nil
      assert data.workspace? == false
    end

    test "the focused rail's own verbs ride through" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0}
      data = status_of(View.compose(reads(%{focus: focus}), 120, 40))
      assert {"⏎", "open"} in data.pane_hints
    end
  end
end
