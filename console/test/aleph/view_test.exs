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
        scope: nil,
        chatter: [],
        chorus: [],
        terminal: :no_session,
        machine: :no_session,
        stack: nil,
        health: nil,
        orbis: nil,
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

  # A Tlön layout with commits count, so Focus.cursor/2 clamps and the Commits pane is navigable.
  # Mirrors production `tlon_layout` since slice D: the Sidebar alone on the left; the right rail
  # is the pinned STACK + the carousel panel (MEMORY at view 0).
  defp layout(counts \\ %{Panel.Stack => 3}),
    do: %{left: [Panel.Sidebar], right: [Panel.Stack, Panel.Memory], sections: %{}, counts: counts}

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

    test "center_view :chat swaps the Terminal section for the thread conversation" do
      chat = %{title: "Tlön", messages: [], thinking: [], working: []}
      placements = View.compose(reads(%{center_view: :chat, center_chat: chat}), 120, 40)

      assert {Panel.Conversation, data, _rect} = Enum.find(placements, &match?({Panel.Conversation, _, _}, &1))
      assert data.title == "Tlön"
      refute placed?(placements, Panel.Terminal)
      # the WindowBar tab strip and the Ticker frame the chat exactly as they frame the PTY
      assert placed?(placements, Panel.WindowBar)
      assert placed?(placements, Panel.Ticker)
    end

    test "center_view :terminal (the default) keeps the live PTY" do
      placements = View.compose(reads(%{center_view: :terminal}), 120, 40)
      assert placed?(placements, Panel.Terminal)
      refute placed?(placements, Panel.Conversation)
    end

    test "a reads map without center_view (older/minimal) defaults to the terminal" do
      placements = View.compose(reads(%{}), 120, 40)
      assert placed?(placements, Panel.Terminal)
    end

    test "an open detail still outranks the chat face" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, detail?: true}
      detail = %{title: "commit abc · x", lines: [{"+added", :diff_add}]}
      chat = %{title: "Tlön", messages: []}

      placements =
        View.compose(
          reads(%{focus: focus, tlon_layout: layout(), detail: detail, center_view: :chat, center_chat: chat}),
          120,
          40
        )

      assert placed?(placements, Panel.Detail)
      refute placed?(placements, Panel.Conversation)
    end
  end

  describe "the contextual right rail (reshape slice D)" do
    test "workspace context (leader in the center): STACK pins the right column" do
      placements = View.compose(reads(%{focused_session: {:leader, "tertius"}}), 120, 40)

      assert {_p, _d, stack_rect} = Enum.find(placements, &match?({Panel.Stack, _, _}, &1))
      assert stack_rect.x > 0
      refute Enum.any?(placements, &match?({Panel.Brief, _, _}, &1))
    end

    test "thread context (a leaf holds the center): the BRIEF pins the right column instead" do
      # A full brief-shaped fixture — the pinned head is MEASURED (intrinsic height = a real
      # render), so the fixture carries every section Panel.Brief renders.
      brief = %{
        thread: nil,
        goal: "fix the tick",
        lead: "hronir",
        todos: %{shown: [], more: 0},
        next: nil,
        done: %{shown: [], more: 0},
        learnings: %{shown: [], more: 0},
        unknowns: %{shown: [], more: 0},
        blockers: %{shown: [], more: 0},
        checks: %{shown: [], more: 0},
        recent: []
      }

      placements =
        View.compose(reads(%{focused_session: {:leaf, 5}, brief: brief}), 120, 40)

      assert {Panel.Brief, data, rect} = Enum.find(placements, &match?({Panel.Brief, _, _}, &1))
      assert rect.x > 0
      assert data.goal == "fix the tick"
      refute Enum.any?(placements, &match?({Panel.Stack, _, _}, &1))
    end

    test "thread context with a failed brief read still pins the Brief placeholder (layout agreement)" do
      placements = View.compose(reads(%{focused_session: {:leaf, 5}, brief: nil}), 120, 40)
      assert Enum.any?(placements, &match?({Panel.Brief, _, _}, &1))
    end
  end

  describe "Tlön focus highlight" do
    test "in nav mode, exactly one sidebar border lights — the focused pane, in the left column" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0}
      placements = View.compose(reads(%{focus: focus}), 120, 40)

      assert [rect] = focused_borders(placements)
      # The left column sits at x = 0 (wide layout); the focused pane must be there.
      assert rect.x == 0
    end

    test "focusing the right column moves the highlight to a right-column border" do
      focus = %Focus{in_terminal?: false, column: :right, pane: 0}
      placements = View.compose(reads(%{focus: focus}), 120, 40)

      assert [rect] = focused_borders(placements)
      # The right column is offset well past the left — not at x = 0.
      assert rect.x > 0
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
      # right pane 0 = the pinned STACK (slice D: Stack lives in the right rail now).
      focus = %Focus{
        in_terminal?: false,
        column: :right,
        pane: 0,
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
      # the carousel pane below (Memory at view 0, not focused) gets no slice merged in
      assert {:ok, mem} = panel_data(placements, Panel.Memory)
      refute Map.has_key?(mem, :selected)
    end
  end

  # The right column is STACK pinned (workspace context) + ONE carousel panel (`[`/`]` cycle
  # right_pane_view among Memory/Crew/Activity/Leaves) — the pinned head never cycles away;
  # HEALTH demoted to the footer + /status (reshape slice D).
  describe "right-pane view (clarity slice 2)" do
    defp right_placed?(placements, mod), do: Enum.any?(placements, &match?({^mod, _, _}, &1))

    test "right_pane_view: 0 (default) shows Stack pinned + Memory (the carousel default)" do
      r = reads(%{active_key: 0, tlon_layout: layout(), right_pane_view: 0})
      placements = View.compose(r, 120, 40)

      assert right_placed?(placements, Panel.Stack)
      assert right_placed?(placements, Panel.Memory)
      refute right_placed?(placements, Panel.Health)
      refute right_placed?(placements, Panel.Crew)
      refute right_placed?(placements, Panel.Leaves)
    end

    test "right_pane_view: 1 shows Stack pinned + Crew (Stack never cycles away)" do
      # The Workspace space's right column is [Stack, Memory, Crew, Activity, Leaves] (Console.Space).
      r = reads(%{active_key: 0, tlon_layout: layout(), right_pane_view: 1})
      placements = View.compose(r, 120, 40)

      assert right_placed?(placements, Panel.Stack)
      assert right_placed?(placements, Panel.Crew)
      refute right_placed?(placements, Panel.Memory)
      refute right_placed?(placements, Panel.Health)
    end

    test "a missing right_pane_view (key absent from reads) defaults to 0 (Stack + Memory)" do
      r = Map.delete(reads(%{active_key: 0, tlon_layout: layout()}), :right_pane_view)
      placements = View.compose(r, 120, 40)

      assert right_placed?(placements, Panel.Stack)
      assert right_placed?(placements, Panel.Memory)
      refute right_placed?(placements, Panel.Crew)
    end

    test "a 1-panel right column (Orbis' [Brief]) degrades cleanly — rem clamps to index 0" do
      r = reads(%{active_key: :orbis, focus: nil, right_pane_view: 7})
      placements = View.compose(r, 120, 40)
      assert right_placed?(placements, Panel.Brief)
    end

    test "narrow layout applies the same pinned + carousel selection to the right portion" do
      r = reads(%{active_key: 0, tlon_layout: layout(), right_pane_view: 1})
      placements = View.compose(r, 60, 40)

      assert right_placed?(placements, Panel.Stack)
      assert right_placed?(placements, Panel.Crew)
      refute right_placed?(placements, Panel.Memory)
      refute right_placed?(placements, Panel.Health)
    end
  end

  describe "right column: pinned Stack + carousel (clarity slice 2)" do
    test "MEMORY is the default carousel view, below a pinned STACK" do
      placements = View.compose(reads(%{}), 120, 40)

      assert {_p, _d, stack_rect} = Enum.find(placements, &match?({Panel.Stack, _, _}, &1))
      assert {_p, _d, memory_rect} = Enum.find(placements, &match?({Panel.Memory, _, _}, &1))
      refute Enum.any?(placements, &match?({Panel.Leaves, _, _}, &1))
      assert memory_rect.y > stack_rect.y
      # pinned: Stack's box hugs its content instead of splitting the column evenly
      assert stack_rect.h < memory_rect.h
    end

    test "right_pane_view picks the carousel panel" do
      placements = View.compose(reads(%{right_pane_view: 3}), 120, 40)
      assert Enum.any?(placements, &match?({Panel.Leaves, _, _}, &1))
      refute Enum.any?(placements, &match?({Panel.Memory, _, _}, &1))
    end

    test "the carousel border is a tab strip with the active tab, digit 3" do
      placements = View.compose(reads(%{}), 120, 40)

      assert Enum.any?(placements, fn
               {Panel.Border,
                %{
                  digit: 3,
                  tabs: [{"MEMORY", true}, {"CREW", false}, {"ACTIVITY", false}, {"THREADS", false}]
                }, _r} ->
                 true

               _ ->
                 false
             end)
    end

    test "the carousel border carries the [ ] cycle corner hint" do
      placements = View.compose(reads(%{}), 120, 40)

      assert Enum.any?(placements, fn
               {Panel.Border, %{tabs: tabs, hint: "[ ] cycle"}, _r} when is_list(tabs) -> true
               _ -> false
             end)
    end

    test "a short frame never places a box (or its content) past the body — the status rows stay clean" do
      # Regression: the pinned head's intrinsic height could leave the carousel a 1-row sliver,
      # whose inset content landed one row PAST the column bottom (on the status bar). The
      # invariant is total: at any height, every non-status placement fits inside body_h. Boxes
      # too short for a real frame (h < 2) must be dropped whole, never emitted as slivers.
      for h <- [4, 8, 15] do
        placements = View.compose(reads(%{}), 120, h)
        body_h = h - 2

        for {panel, _data, rect} <- placements, panel != Panel.StatusBar do
          assert rect.y + rect.h <= body_h,
                 "#{inspect(panel)} ends past the body at 120x#{h}: #{inspect(rect)} (body_h #{body_h})"
        end
      end
    end
  end

  describe "digit-numbering agreement: View borders ⇄ Focus.jump (clarity slice 4)" do
    # The title (or, for the carousel box, the active tab's label) View painted at `digit` — the
    # one drift that would make Alt+N lie: the number on the frame must be the pane Focus.jump/3
    # actually reaches at that same digit.
    defp digit_title(placements, digit) do
      Enum.find_value(placements, fn
        {Panel.Border, %{digit: ^digit, title: title}, _r} when not is_nil(title) ->
          title

        {Panel.Border, %{digit: ^digit, tabs: tabs}, _r} when is_list(tabs) ->
          case Enum.find(tabs, fn {_label, active?} -> active? end) do
            {label, true} -> label
            _ -> nil
          end

        _ ->
          nil
      end)
    end

    test "border digits agree with Focus.jump over the same layout (Alt+N reaches pane N)" do
      placements = View.compose(reads(%{}), 120, 40)
      space = Console.Space.fetch(0)

      layout = %{
        left: [Panel.Sidebar | space.left],
        right: Console.Space.visible_right(space, 0),
        sections: %{},
        counts: %{}
      }

      # Slice D: Sidebar alone on the left (1); the right rail is pinned STACK (2) + the carousel
      # box (3) — whose "title" is its active tab (MEMORY at view 0).
      expected = %{1 => Panel.Sidebar, 2 => Panel.Stack, 3 => Panel.Memory}
      titles = %{1 => "WORKSPACES", 2 => "STACK", 3 => "MEMORY"}

      for d <- 1..3 do
        assert %Focus{} |> Focus.jump(layout, d) |> Focus.focused_pane(layout) == expected[d]
        assert digit_title(placements, d) == titles[d]
      end
    end
  end

  # C3.1: the tab strip is LEADERS only — a workspace's roster windows (+ the general console furniture);
  # `t<id>` leaf windows move to the Leaves panel, not the strip.
  describe "WindowBar leaders only" do
    defp tab(name), do: %{name: name, active?: false, index: "1"}

    test "leaf windows (t<id>) are excluded from the tab strip; leaders (roster + general) stay" do
      r = reads(%{active_key: 0, machine: %{tabs: [tab("tertius"), tab("hronir"), tab("general"), tab("t42")]}})

      %{tabs: tabs} = View.data_for(Panel.WindowBar, r)
      names = Enum.map(tabs, & &1.name)

      assert "tertius" in names
      assert "hronir" in names
      assert "general" in names
      refute "t42" in names
    end

    test "a thread-tagged leaf is excluded even when named descriptively (not t<id>)" do
      leaf = Map.put(tab("builder-hola-who-is-this-what"), :thread_id, 2)
      r = reads(%{active_key: 0, machine: %{tabs: [tab("hronir"), leaf]}})

      names = View.data_for(Panel.WindowBar, r).tabs |> Enum.map(& &1.name)

      assert "hronir" in names
      refute "builder-hola-who-is-this-what" in names
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
      # Directly above the 2-row status footer, full width.
      assert rect.y == 40 - 2 - 3
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

    test "workspace sidebar boxes carry digit-first titles derived from layout order" do
      placements = View.compose(reads(%{}), 120, 40)

      assert %{digit: 1} = border_of(placements, "WORKSPACES")
      assert %{digit: 2} = border_of(placements, "STACK")
      # MEMORY is the carousel box now — a tab strip, not a plain title (covered by the
      # digit-agreement test).
      refute border_of(placements, "MEMORY")
    end

    test "the center terminal box carries digit 0 and no title" do
      placements = View.compose(reads(%{}), 120, 40)

      assert Enum.any?(placements, fn
               {Panel.Border, %{digit: 0, title: nil}, _rect} -> true
               _ -> false
             end)
    end

    test "orbis boxes are titled too (shared pieces inherit)" do
      placements = View.compose(reads(%{active_key: :orbis, focus: nil}), 120, 40)
      assert border_of(placements, "ACTIVE")
      assert border_of(placements, "BRIEF")
    end
  end

  describe "contextual footer data (clarity slice 3)" do
    defp status_of(placements),
      do:
        Enum.find_value(placements, fn
          {Panel.StatusBar, data, _rect} -> data
          _ -> nil
        end)

    test "workspace + nav: mode :nav, workspace? true, and the focused pane's hints (carousel appends [/])" do
      focus = %Focus{in_terminal?: false, column: :right, pane: 1}
      data = status_of(View.compose(reads(%{focus: focus}), 120, 40))

      assert data.mode == :nav
      assert data.workspace? == true
      # right pane 1 is the carousel slot (MEMORY by default — no verbs of its own) → just [/]
      assert {"[/]", "view"} in data.pane_hints
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
      # Slice D: Stack is the right rail's pinned head (right pane 0), not a left pane.
      focus = %Focus{in_terminal?: false, column: :right, pane: 0}
      data = status_of(View.compose(reads(%{focus: focus}), 120, 40))
      assert {"⏎", "diff"} in data.pane_hints
    end
  end
end
