defmodule Console.ReadsTest do
  @moduledoc """
  The pure shaping in the render preamble — reachable now that it lives outside the GenServer.
  The reads themselves (server, tmux, git) are exercised by the suites that boot a scratch db.
  """
  use ExUnit.Case, async: true

  alias Console.Panel.Rail
  alias Console.Reads

  setup do
    Console.TestWorkspaces.put()
  end

  describe "thread_cards/4 — the two-step card set" do
    test "every block is a row; only the opened thread carries its messages; the cursor is active" do
      blocks = [
        %{thread: %{id: 1, title: "one", stage: nil, awaiting: nil}, messages: [:m1]},
        %{thread: %{id: 2, title: "two", stage: "build", awaiting: "gate"}, messages: [:m2]}
      ]

      cards = Reads.thread_cards(blocks, 2, 1, %{2 => %{"hronir-machine" => 1}})

      assert [%{id: 1, active?: false, typing: nil, messages: [:m1]}, %{id: 2, active?: true, messages: []}] = cards
      assert Enum.at(cards, 1).typing == "hronir"
      assert Enum.at(cards, 1).stage == "build"
    end
  end

  describe "stack_focus/2 and focused_thread/2" do
    @blocks [%{thread: %{id: 5}}, %{thread: %{id: 6}}]
    @threads [%{id: 5, title: "a"}, %{id: 6, title: "b"}]

    test "the focused thread when it's in the stack, else the first card" do
      assert Reads.stack_focus(@blocks, 6) == 6
      assert Reads.stack_focus(@blocks, 99) == 5
      assert Reads.stack_focus([], 99) == nil
    end

    test "focused_thread resolves an id, defaults to the first, nil on an empty list" do
      assert Reads.focused_thread(@threads, 6).title == "b"
      assert Reads.focused_thread(@threads, nil).title == "a"
      assert Reads.focused_thread(@threads, 99).title == "a"
      assert Reads.focused_thread([], 6) == nil
    end
  end

  describe "the activity feed: first-sight gate + workspace scoping" do
    test "seen_key is {tag, id} for a durable row, the whole term otherwise" do
      assert Reads.seen_key(:fact_banked, %{id: 3}) == {:fact_banked, 3}
      assert Reads.seen_key(:todo_added, %{id: nil, body: "x"}) == {:todo_added, %{id: nil, body: "x"}}
    end

    test "fresh? is false once the key was seen; cap_seen bounds the set" do
      state = %{seen_events: [{:fact_banked, 3}]}
      refute Reads.fresh?(state, :fact_banked, %{id: 3})
      assert Reads.fresh?(state, :fact_banked, %{id: 4})
      assert length(Reads.cap_seen(Enum.to_list(1..500))) == 100
    end

    test "push_activity prepends newest-first and caps the ring" do
      state = %{activity: Enum.map(1..60, &{:old, %{id: &1}})}
      %{activity: [{:new, %{id: 0}} | rest]} = Reads.push_activity(state, :new, %{id: 0})
      assert length(rest) == 49
    end

    test "scope_activity keeps global rows and this workspace's threads; nil ids = unfiltered" do
      feed = [{:a, %{thread_id: 1}}, {:b, %{thread_id: 2}}, {:c, %{}}]
      assert Reads.scope_activity(feed, MapSet.new([2])) == [{:b, %{thread_id: 2}}, {:c, %{}}]
      assert Reads.scope_activity(feed, nil) == feed
    end
  end

  # UX slice 1, task 2: the rail is the only left pane, so the focus's j/k count and Enter both
  # resolve against the SAME stashed sidebar read the frame rendered from.
  describe "the rail's keyboard: tlon_layout/1 counts and enter_verb/2" do
    @sidebar [
      %{workspace: %{id: 0, name: "Tlön"}, threads: [%{id: 9, title: "general"}, %{id: 8, title: "aleph"}]},
      %{workspace: %{id: 1, name: "ficciones"}, threads: [%{id: 5, title: "hidden"}]}
    ]

    defp rail_state(over \\ %{}) do
      Map.merge(
        %{
          active_key: 0,
          sidebar: @sidebar,
          stack: nil,
          memory: nil,
          focus: %Console.Tlon.Focus{in_terminal?: false, column: :left, pane: 0, cursors: %{}}
        },
        over
      )
    end

    defp at(cursor, over \\ %{}) do
      state = rail_state(over)
      %{state | focus: %{state.focus | cursors: %{Rail => cursor}}}
    end

    test "the layout counts the rail's rows — the active workspace's threads, not every group's" do
      layout = Reads.tlon_layout(rail_state())

      # workspace 0, its two threads, workspace 1 (collapsed).
      assert layout.counts[Rail] == 4
      assert layout.left == [Rail]
    end

    test "an empty sidebar read counts zero rows, so j/k is a no-op instead of a crash" do
      assert Reads.tlon_layout(rail_state(%{sidebar: []})).counts[Rail] == 0
    end

    test "Enter on the rail is a pick verb — a thread opens, a workspace switches; never a detail" do
      state = at(0)
      assert Reads.enter_verb(state, Reads.tlon_layout(state)) == {:pick, {:switch_space, 0}}

      state = at(1)
      assert Reads.enter_verb(state, Reads.tlon_layout(state)) == {:pick, {:open_thread_view, 9}}

      state = at(3)
      assert Reads.enter_verb(state, Reads.tlon_layout(state)) == {:pick, {:switch_space, 1}}
    end

    test "Enter with nothing to land on does nothing — it never arms the detail mode" do
      state = at(0, %{sidebar: []})
      assert Reads.enter_verb(state, Reads.tlon_layout(state)) == :none
    end

    test "Enter outside a workspace (no pane focused) does nothing" do
      state = rail_state(%{active_key: :orbis})
      assert Reads.enter_verb(state, Reads.tlon_layout(state)) == :none
    end
  end

  describe "the session pane" do
    test "targets the stack cursor only when toggled on, in a workspace, in chat view" do
      on = %{session_pane: true, active_key: 0, center_view: :chat, stack_focus: 7}
      assert Reads.session_pane_target(on) == 7
      assert Reads.session_pane_target(%{on | session_pane: false}) == nil
      assert Reads.session_pane_target(%{on | center_view: :terminal}) == nil
      assert Reads.session_pane_target(%{on | active_key: :orbis}) == nil
      assert Reads.session_pane_target(%{on | stack_focus: nil}) == nil
    end

    test "dims are a third of the width, never zero" do
      assert Reads.session_pane_dims(%{w: 120, h: 40}) == {38, 37}
      assert Reads.session_pane_dims(%{w: 3, h: 2}) == {1, 1}
    end
  end

  describe "fact_detail/1 and habit_detail/1" do
    test "a fact lists kind/provenance and only the non-blank metadata" do
      fact = %{kind: "gotcha", provenance: "andrew", text: "mind the gap", check_cmd: "", incident: "x", taught: nil}
      %{title: "FLOOR FACT", lines: lines} = Reads.fact_detail(fact)
      texts = Enum.map(lines, fn {t, _} -> t end)
      assert "mind the gap" in texts
      assert "incident: x" in texts
      refute Enum.any?(texts, &String.starts_with?(&1, "check:"))
    end

    test "a habit names its proposer and rationale when present; nil in → nil out" do
      habit = %{text: "run the gate", proposed_by: "tertius", rationale: "green before commit"}
      %{title: title, lines: lines} = Reads.habit_detail(habit)
      assert title =~ "proposed by tertius"
      assert {"green before commit", :dim} in lines
      assert Reads.habit_detail(nil) == nil
      assert Reads.fact_detail(nil) == nil
    end
  end

  # `c` targets the thread you're actually LOOKING at (Slice 3.3): in chat view (the thread
  # stack is the center) that's the stack-focused card.
  describe "composer_thread_id/1 — which thread `c` posts to" do
    test "in chat view, targets the stack-focused card" do
      state = %{active_key: 0, center_view: :chat, stack_focus: 7}
      assert Reads.composer_thread_id(state) == 7
    end
  end

  # /status (reshape slice D): HEALTH's full readout as a MAIN detail, built from the same
  # health read the footer condenses. Pure so the composer command is testable without a TTY.
  describe "status_detail_content/1 — the /status readout" do
    test "a live health read becomes a titled detail with the panel's lines" do
      health = %{
        funes_up: true,
        tlon_up: true,
        nix_gen: 36,
        nix_behind: 0,
        disk_pct: 68,
        mem_pct: 28,
        load_avg: 2.18,
        tools: [%{name: "pi", version: "0.84.2"}]
      }

      assert %{title: "status", lines: lines} = Reads.status_detail_content(health)
      joined = Enum.map_join(lines, "\n", fn {t, _style} -> t end)
      assert joined =~ "server"
      assert joined =~ "disk 68%"
      assert joined =~ "pi"
    end

    test "a nil health read (probe not run) says so instead of crashing" do
      assert %{title: "status", lines: [{line, _style}]} = Reads.status_detail_content(nil)
      assert line =~ "health"
    end
  end

  describe "orbis_workspaces/1: the survey reads the CACHED rollup, never re-gathers funes" do
    test "returns the cached rollup's workspaces — no live funes gather" do
      # ensure_probes fills state.leaves with the full rollup (workspaces key included) on the @probe_ms
      # throttle; the survey must read THAT, so a known cache flows straight through untouched.
      cached = %{
        summary: %{open: 1, stalled: 0, done: 0, conflicts: 0},
        rows: [%{id: 1}],
        workspaces: [%{workspace: "Tlön", summary: %{open: 1, stalled: 0, done: 0, conflicts: 0}, leaves: [%{id: 1}]}]
      }

      assert Reads.orbis_workspaces(%{leaves: cached}) == cached.workspaces
    end

    test "a cold / funes-down cache (nil leaves) is an empty survey, not a crash" do
      assert Reads.orbis_workspaces(%{leaves: nil}) == []
    end
  end
end
