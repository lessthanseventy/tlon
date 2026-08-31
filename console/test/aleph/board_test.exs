# A one-row panel that renders whatever raw string it's given, for probing the paint boundary.
defmodule SanitizeProbe do
  @moduledoc false
  @behaviour Console.Panel

  @impl true
  def topics(_), do: []
  @impl true
  def render(text, _rect) when is_binary(text), do: [[{text, :normal}]]
end

# A panel whose render/2 raises — a stand-in for any render-path footgun (a bad row shape, a
# NotLoaded assoc). The board must never let it take the whole cockpit down.
defmodule BoomProbe do
  @moduledoc false
  @behaviour Console.Panel

  @impl true
  def topics(_), do: []
  @impl true
  def render(_data, _rect), do: raise("kaboom")
end

defmodule Console.BoardTest do
  @moduledoc """
  The slice-1 render proof: the panel → styled-rows → composed-cells path is correct without a
  TTY. Actual on-screen paint (cells → termbox NIF) is the eye test, run in a real terminal.
  """
  use ExUnit.Case, async: true

  alias Console.Board
  alias Console.Panel
  alias Console.Panel.Activity
  alias Console.Panel.Border
  alias Console.Panel.Brief
  alias Console.Panel.Health
  alias Console.Panel.Overview
  alias Console.Panel.Roster
  alias Console.Panel.Sidebar
  alias Console.Panel.Stack
  alias Console.Panel.StatusBar
  alias Console.Panel.Terminal
  alias Console.Panel.Tertius
  alias Console.Panel.WindowBar
  alias Console.View

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

  # Flatten a styled row to its text, for assertions.
  defp text(row), do: Enum.map_join(row, fn {t, _style} -> t end)

  @roster [
    %{agent: "Sandra", thread_id: 1, thread_title: "review PR 329", pane_ref: nil, warm?: true},
    %{agent: "Robert", thread_id: 2, thread_title: "triage inbox", pane_ref: nil, warm?: false}
  ]

  @threads [
    %Server.Thread{id: 1, title: "review PR 329", state: "open"},
    %Server.Thread{id: 2, title: "triage inbox", state: "open"}
  ]

  defp reads(overrides \\ %{}) do
    Map.merge(
      %{
        active_key: :orbis,
        focused_id: 1,
        focused_title: "review PR 329",
        roster: @roster,
        threads: @threads,
        scope: nil,
        chatter: [],
        chorus: [],
        terminal: :no_session,
        health: nil,
        orbis: nil,
        triage: %{blockers: %{shown: [], more: 0}, failed_checks: %{shown: [], more: 0}, unassigned: []}
      },
      overrides
    )
  end

  describe "panels render styled rows" do
    test "roster: one row per session, warmth marked (title lives on the frame now)" do
      rect = %{x: 0, y: 0, w: 40, h: 10}
      assert [sandra, robert] = Roster.render(%{sessions: @roster}, rect)
      assert text(sandra) =~ "Sandra"
      assert text(sandra) =~ "review PR 329"
      assert text(sandra) =~ "●"
      assert text(robert) =~ "○"
    end

    test "thread rows live in the Leaves panel now (slice C/D) — no separate thread list" do
      refute Code.ensure_loaded?(Console.Panel.ThreadList)
    end

    test "stack (Tlön): branch then two rows per commit (subject, then meta line), hash dimmed" do
      rect = %{x: 0, y: 0, w: 60, h: 10}

      commits = [
        %{
          hash: "bc86cc8",
          subject: "funes: open_thread / close_thread",
          relative: "2 hours ago",
          date: "Nov 24 10:00",
          author: "andrew",
          agent?: false
        }
      ]

      data = %{branch: "main", dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: commits}
      assert [_label, branch, _rule, _commits_label, subject, meta] = Stack.render(data, rect)
      assert text(branch) =~ "main"
      assert text(meta) =~ "bc86cc8"
      assert text(meta) =~ "2 hours ago"
      assert text(subject) =~ "open_thread"
      assert Enum.any?(meta, fn {t, s} -> s == :dim and t =~ "bc86cc8" end)
    end

    test "stack (Tlön): ahead/behind tracking and dirty status" do
      rect = %{x: 0, y: 0, w: 60, h: 10}
      data_ahead = %{branch: "main", dirty: false, ahead: 3, behind: 1, status_summary: nil, commits: []}
      rows = Stack.render(data_ahead, rect)
      branch_row = Enum.find(rows, fn r -> text(r) =~ "main" end)
      assert text(branch_row) =~ "↑"
      assert text(branch_row) =~ "3"
      assert text(branch_row) =~ "↓"
      assert text(branch_row) =~ "1"

      data_dirty = %{
        branch: "main",
        dirty: true,
        ahead: 0,
        behind: 0,
        status_summary: %{staged: 2, unstaged: 1, untracked: 3},
        commits: []
      }

      rows_dirty = Stack.render(data_dirty, rect)
      joined = Enum.map_join(rows_dirty, "\n", &text/1)
      assert joined =~ "✗"
      assert joined =~ "+2"
      assert joined =~ "~1"
      assert joined =~ "?3"
    end

    test "stack (Tlön): honest when there is no git history" do
      rect = %{x: 0, y: 0, w: 60, h: 10}
      data = %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: []}
      assert [_label, branch, _rule, _commits_label, empty] = Stack.render(data, rect)
      assert text(branch) =~ "no branch"
      assert text(empty) =~ "no git history"
    end

    test "health (Tlön): services, system metrics, and tools in sections" do
      rect = %{x: 0, y: 0, w: 40, h: 20}

      data = %{
        funes_up: true,
        tlon_up: false,
        nix_gen: 21,
        nix_behind: 0,
        disk_pct: 67,
        mem_pct: 40,
        load_avg: 2.5,
        tools: [%{name: "pi", version: "0.9.1"}, %{name: "nix", version: "?"}]
      }

      rows = Health.render(data, rect)
      joined = Enum.map_join(rows, "\n", &text/1)
      assert joined =~ "server"
      assert joined =~ "tlon"
      assert joined =~ "SYS"
      assert joined =~ "nix gen 21"
      assert joined =~ "disk 67%"
      assert joined =~ "mem 40%"
      assert joined =~ "load 2.5"
      assert joined =~ "TOOLS"
      assert joined =~ "pi"
      assert joined =~ "0.9.1"
    end

    test "the brief panel renders sections from a brief map, honest about empties and cuts" do
      # todos/learnings/blockers/done are each %{shown, more} (funes Board): a cap is
      # always rendered WITH its count — a cut without a count lies. DONE is the merged
      # view (completed todos + work_landed events); NEXT is the first open todo.
      scope = %{
        goal: "ship the board",
        lead: "Sandra",
        todos: %{shown: [%{id: 1, text: "wire the composer"}, %{id: 2, text: "then the footer"}], more: 3},
        next: %{id: 1, text: "wire the composer"},
        learnings: %{shown: [%{text: "termbox compiles"}], more: 2},
        unknowns: %{shown: [%{text: "does raxol embed?"}], more: 0},
        blockers: %{shown: [], more: 0},
        checks: %{
          shown: [
            %{kind: "check_passed", detail: %{"cmd" => "mise run check"}},
            %{kind: "check_failed", detail: %{"cmd" => "mix test", "exit" => 1}}
          ],
          more: 0
        },
        done: %{
          shown: [
            %{source: :todo, row: %{text: "did a step"}},
            %{source: :event, row: %{detail: %{"summary" => "merged it"}}}
          ],
          more: 0
        },
        recent: []
      }

      rows = Brief.render(scope, %{x: 0, y: 0, w: 40, h: 40})
      joined = Enum.map_join(rows, "\n", &text/1)
      assert joined =~ "GOAL"
      assert joined =~ "ship the board"
      # TODOS with NEXT marked by an arrow; the rest plain
      assert joined =~ "TODOS"
      assert joined =~ "→ wire the composer"
      assert joined =~ "· then the footer"
      assert joined =~ "LEARNINGS"
      assert joined =~ "termbox compiles"
      # UNKNOWNS surfaces open questions with a "?"
      assert joined =~ "UNKNOWNS"
      assert joined =~ "? does raxol embed?"
      # CHECKS: a measured pass (✓) and a fail (✗ with its exit code)
      assert joined =~ "CHECKS"
      assert joined =~ "✓ mise run check"
      assert joined =~ "✗ mix test (exit 1)"
      # DONE merges a completed todo (✓) and a work_landed event's summary
      assert joined =~ "DONE"
      assert joined =~ "✓ did a step"
      assert joined =~ "merged it"
      # every cut is counted, never silent
      assert joined =~ "+2 more"
      assert joined =~ "+3 more"
      # empty section keeps its shape with a dim em-dash, never an invented value
      assert joined =~ "—"
    end

    test "terminal panel renders ghostty cells as truecolor runs, inverting the cursor cell" do
      render_state = %{
        cells: [[{"h", {255, 0, 0}, nil, 0}, {"i", nil, nil, 0}]],
        cursor: %{visible: true, x: 1, y: 0},
        foreground: {200, 200, 200},
        background: {10, 10, 10}
      }

      [row] = Terminal.render(render_state, %{x: 0, y: 0, w: 40, h: 4})

      # 'h' carries its own red fg; nil bg falls back to the terminal's default bg
      assert {"h", {:rgb, 0xFF0000, 0x0A0A0A}} = Enum.at(row, 0)
      # 'i' is under the cursor → fg/bg swapped so the cell reads as the cursor
      assert {"i", {:rgb, 0x0A0A0A, 0xC8C8C8}} = Enum.at(row, 1)
    end

    test "terminal panel shows a placeholder when there is no session" do
      rows = Terminal.render(:no_session, %{x: 0, y: 0, w: 40, h: 4})
      assert Enum.map_join(rows, "\n", &text/1) =~ "Enter to spawn"
    end

    test "chorus surveys workspaces — the ORBIS · workspaces header + a row per workspace with its rollup" do
      workspaces = [
        %{
          id: 1,
          name: "Tlön",
          summary: %{open: 2, stalled: 1, done: 3, conflicts: 4},
          leaves: [%{id: 1}, %{id: 2}]
        }
      ]

      rows = Overview.render(%{workspaces: workspaces}, %{x: 0, y: 0, w: 60, h: 40})
      joined = Enum.map_join(rows, "\n", &text/1)

      assert joined =~ "ORBIS · workspaces"
      assert joined =~ "Tlön"
      # the workspace's summary line carries the open/stalled/done/trouble rollup
      assert joined =~ "2 open"
      assert joined =~ "1 stalled"
      assert joined =~ "3 done"
      assert joined =~ "4 conflicts"
      # the workspace header row washes :header (the ▸ + name)
      workspace_head = Enum.find(rows, &(text(&1) =~ "Tlön" and text(&1) =~ "▸"))
      assert Enum.any?(workspace_head, fn {_t, s} -> s == :header end)
    end
  end

  describe "panel pick — click a row to select (pure decision, design §8)" do
    test "roster: a session row focuses the thread it's working (no header chrome — rows start at 0)" do
      data = %{sessions: @roster, scroll: 0}
      rect = %{x: 0, y: 0, w: 40, h: 10}
      assert {:focus_thread, 1} = Roster.pick(data, rect, 0)
      assert {:focus_thread, 2} = Roster.pick(data, rect, 1)
      assert Roster.pick(data, rect, 99) == nil
    end

    test "chorus: clicking a workspace row zooms to ITS OWN workspace id; the survey header + blank do not" do
      workspaces = [
        %{id: 3, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}
      ]

      data = %{workspaces: workspaces, scroll: 0}
      rect = %{x: 0, y: 0, w: 60, h: 40}
      # survey header (0) + blank (1) select nothing
      assert Overview.pick(data, rect, 0) == nil
      assert Overview.pick(data, rect, 1) == nil
      # the workspace's rows (head + summary + blank) span content rows 2–4 → zoom to its own id
      assert {:switch_space, 3} = Overview.pick(data, rect, 2)
      assert {:switch_space, 3} = Overview.pick(data, rect, 4)
      # a click past the last workspace selects nothing
      assert Overview.pick(data, rect, 5) == nil
    end
  end

  describe "render_scroll — windowing and the stale-offset clamp" do
    # A 10-row scrollable vehicle: the activity feed, one row per event, no header chrome.
    defp scroll_events, do: Enum.map(1..10, &{:fact_banked, %{id: &1, kind: "note", text: "t#{&1}"}})

    test "offset 0 renders exactly like a plain render (the every-tick fast path)" do
      data = %{events: scroll_events(), scroll: 0}
      rect = %{x: 0, y: 0, w: 30, h: 3}
      assert Panel.render_scroll(Activity, data, rect) == Activity.render(data, rect)
    end

    test "an offset past the end clamps to the last window instead of a blank panel" do
      # Content shrank while scrolled (an event buffer trimmed mid-scroll): the stored offset now
      # overshoots. render_scroll clamps so the panel shows the tail, not emptiness.
      data = %{events: scroll_events(), scroll: 50}
      rect = %{x: 0, y: 0, w: 30, h: 3}
      rows = Panel.render_scroll(Activity, data, rect)
      assert length(rows) == 3
      assert rows == %{data | scroll: 0} |> Activity.render(%{rect | h: 100}) |> Enum.take(-3)
    end
  end

  describe "status bar" do
    defp status(overrides \\ %{}) do
      Map.merge(
        %{
          space: "Sessions",
          thread: "flaky test hunt",
          thread_count: 3,
          live_count: 1,
          mode: nil,
          workspace?: false,
          lock?: false,
          pane_hints: []
        },
        overrides
      )
    end

    test "info line shows the space, thread, and global counts" do
      assert [info, _hints] = StatusBar.render(status(), %{x: 0, y: 0, w: 120, h: 2})
      joined = text(info)
      assert joined =~ "Sessions"
      assert joined =~ "flaky test hunt"
      # the underused right side now carries global state
      assert joined =~ "3 threads"
      assert joined =~ "1 live"
    end

    test "hints line is always present on the bottom row" do
      assert [_info, hints] = StatusBar.render(status(), %{x: 0, y: 0, w: 120, h: 2})
      joined = text(hints)
      assert joined =~ "quit"
      assert joined =~ "thread"
    end

    test "the info line fills the width without flooding it with a chip background" do
      w = 120
      assert [info, _hints] = StatusBar.render(status(), %{x: 0, y: 0, w: w, h: 2})
      # padded to the full width...
      assert Panel.row_width(info) == w
      # ...but the wide gap is neutral, never a chip/selection background (the old full-bar flood)
      refute Enum.any?(info, fn {t, s} ->
               s != :normal and String.trim(t) == "" and String.length(t) >= 3
             end)
    end

    test "the space renders as a discrete tab chip" do
      assert [info, _hints] = StatusBar.render(status(), %{x: 0, y: 0, w: 120, h: 2})
      chip = Enum.find(info, fn {t, s} -> s == :tab and t =~ "Sessions" end)
      assert chip, "space should render as a :tab chip"
    end

    test "composing shows the mode chip and the composer hints — the buffer lives in the compose box" do
      data = status(%{input: %{kind: :compose, thread_id: 2, buffer: "ship it"}})
      assert [info, hints] = StatusBar.render(data, %{x: 0, y: 0, w: 120, h: 2})
      assert text(info) =~ "COMPOSE"
      refute text(info) =~ "ship it"
      assert text(hints) =~ "post"
      assert text(hints) =~ "newline"
    end
  end

  describe "border box" do
    test "draws a rounded box framing the whole rect" do
      rows = Border.render(nil, %{x: 0, y: 0, w: 6, h: 4})
      assert length(rows) == 4
      assert text(Enum.at(rows, 0)) == "╭────╮"
      assert text(Enum.at(rows, 3)) == "╰────╯"
      mid = Enum.at(rows, 1)
      assert text(mid) == "│    │"
      # the frame is drawn in the separator style; the interior is neutral
      assert {"│", :separator} = hd(mid)
    end

    test "degenerates safely below 2×2" do
      assert Border.render(nil, %{x: 0, y: 0, w: 1, h: 5}) == []
    end
  end

  describe "clip" do
    test "clips rows to height and each row to width" do
      rows = [Panel.line("a very long header line", :header)]
      assert [clipped] = Panel.clip(rows, %{x: 0, y: 0, w: 5, h: 1})
      assert String.length(text(clipped)) == 5
    end
  end

  describe "view composition" do
    test "orbis space: picker, chorus surface, a box per section, status bar — all in bounds" do
      placements = View.compose(reads(), 120, 40)
      mods = Enum.map(placements, fn {m, _d, _r} -> m end)

      assert Sidebar in mods
      assert Overview in mods
      assert Brief in mods
      assert StatusBar in mods
      # every section gets its own bordered box (switcher, roster/triage, chorus, dossier)
      content_panels = Enum.reject(mods, &(&1 in [Border, StatusBar]))
      assert Enum.count(mods, &(&1 == Border)) == length(content_panels)
      assert length(content_panels) >= 4

      Enum.each(placements, fn {_m, _d, r} ->
        assert r.x >= 0 and r.y >= 0
        assert r.x + r.w <= 120
        assert r.y + r.h <= 40
      end)
    end

    test "content sits inside its column box, not against the frame" do
      placements = View.compose(reads(), 120, 40)
      {_m, _d, roster_rect} = Enum.find(placements, fn {m, _d, _r} -> m == Roster end)
      # the left sidebar is inset from the left frame — padded, not jammed to x=0
      assert roster_rect.x >= 2
    end

    test "tlön space centers ONE machine terminal (the embedded tmux client), fed by the :machine read" do
      tlon =
        reads(%{
          active_key: 0,
          machine: :no_session,
          stack: %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: [], tools: []},
          health: %{
            funes_up: false,
            tlon_up: true,
            nix_gen: nil,
            nix_behind: nil,
            disk_pct: nil,
            mem_pct: nil,
            load_avg: nil,
            tools: []
          }
        })

      placements = View.compose(tlon, 120, 40)

      # the terminal is framed: WindowBar above, Ticker below, each its own bordered box — no
      # longer the full-height center column a single-section surface would give it.
      assert [{Terminal, :no_session, term_rect}] = Enum.filter(placements, fn {m, _d, _r} -> m == Terminal end)
      assert [{WindowBar, _wb_data, wb_rect}] = Enum.filter(placements, fn {m, _d, _r} -> m == WindowBar end)
      assert [{Tertius, _data, pulse_rect}] = Enum.filter(placements, fn {m, _d, _r} -> m == Tertius end)

      assert wb_rect.y < term_rect.y
      assert pulse_rect.y > term_rect.y
      assert term_rect.h < 36
    end

    test "the PTY sizes to the placed Terminal rect — no overflow past the frame" do
      # center_rect is what the embedded PTY is sized to; it MUST equal the rect compose places the
      # Terminal into, or pi draws wider/taller than the visible area (content spills past the frame,
      # or a dead band opens below). One authority for both, asserted across sizes. Tlön is the only
      # terminal-bearing space since the Slice 0 collapse; its column also carries WindowBar/Ticker.
      for {key, w, h} <- [{0, 120, 40}, {0, 84, 30}] do
        r =
          reads(%{
            active_key: key,
            machine: :no_session,
            stack: %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: [], tools: []},
            health: nil
          })

        {_m, _d, term_rect} = Enum.find(View.compose(r, w, h), fn {m, _d, _r} -> m == Terminal end)

        assert View.center_rect(key, w, h) == term_rect,
               "center_rect drifted from the Terminal placement at #{key} #{w}x#{h}"
      end
    end

    test "a short Tlön terminal never places a section (or the PTY) past the frame" do
      # WindowBar(3) + Terminal(flex) + Ticker(3) stacked in the center column overflowed at short
      # heights: split_heights floored the flex Terminal at 1 but never clamped the SUM against the
      # column, so the Ticker box landed below the column (on/past the StatusBar). Clamp now shrinks
      # the fixed bands in stack order — a lower band collapses to 0 rather than going off-frame.
      # 12 is a comfortably short cockpit; 8 is the regime that used to overflow.
      for {key, w, h} <- [{0, 120, 12}, {0, 120, 8}] do
        r =
          reads(%{
            active_key: key,
            machine: :no_session,
            stack: %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: [], tools: []},
            health: nil
          })

        Enum.each(View.compose(r, w, h), fn {mod, _d, rect} ->
          assert rect.x >= 0 and rect.y >= 0, "#{inspect(mod)} placed above/left of the frame at #{key} #{w}x#{h}"
          assert rect.x + rect.w <= w, "#{inspect(mod)} overflowed the frame width at #{key} #{w}x#{h}"
          assert rect.y + rect.h <= h, "#{inspect(mod)} overflowed the frame height at #{key} #{w}x#{h}: #{inspect(rect)}"
        end)

        cr = View.center_rect(key, w, h)
        assert cr.y + cr.h <= h, "the PTY center_rect fell past the frame at #{key} #{w}x#{h}: #{inspect(cr)}"
        assert cr.x + cr.w <= w
      end
    end

    test "orbis space centers the chorus feed, with the roster (not a thread list) at its side" do
      placements = View.compose(reads(%{active_key: :orbis}), 120, 40)
      mods = Enum.map(placements, fn {m, _d, _r} -> m end)
      # the chorus (all threads, one feed) is the center; the roster is the left sidebar (presence) —
      # the feed is the navigator now (the old thread-list panel is deleted, slice D).
      assert Overview in mods
      assert Roster in mods
      refute Terminal in mods
    end
  end

  describe "responsive layout" do
    defp box_xs(placements) do
      placements
      |> Enum.filter(fn {m, _d, _r} -> m == Border end)
      |> Enum.map(fn {_m, _d, r} -> r.x end)
      |> Enum.uniq()
      |> Enum.sort()
    end

    test "a wide viewport lays out three columns" do
      xs = reads() |> View.compose(140, 40) |> box_xs()
      # three distinct column x-offsets (left at 0, center, right)
      assert length(xs) == 3
      assert 0 in xs
    end

    test "a narrow viewport collapses to a single column" do
      xs = reads() |> View.compose(50, 40) |> box_xs()
      # every section box sits in one column at x=0
      assert xs == [0]
    end

    test "the same sections are present in both layouts" do
      wide = reads() |> View.compose(140, 40) |> Enum.map(fn {m, _d, _r} -> m end)
      narrow = reads() |> View.compose(50, 40) |> Enum.map(fn {m, _d, _r} -> m end)
      assert Enum.sort(Enum.uniq(wide)) == Enum.sort(Enum.uniq(narrow))
    end
  end

  describe "board composes cells" do
    test "a placement produces cells at the rect origin" do
      rect = %{x: 3, y: 2, w: 40, h: 10}
      cells = Board.compose([{Roster, %{sessions: @roster}, rect}], 80, 24)
      assert Enum.any?(cells, &(&1.x == 3 and &1.y == 2))
      # every cell carries a codepoint and colours
      assert Enum.all?(cells, &(is_integer(&1.ch) and is_integer(&1.fg) and is_integer(&1.bg)))
    end

    test "a panel that raises degrades to an error row, never crashing the cockpit" do
      rect = %{x: 0, y: 0, w: 30, h: 3}
      good = {Roster, %{sessions: @roster}, %{x: 0, y: 5, w: 30, h: 5}}

      # compose must not raise even though BoomProbe.render/2 does — and the other panel still paints.
      cells = Board.compose([{BoomProbe, %{}, rect}, good], 80, 24)

      assert is_list(cells) and cells != []
      # the surviving panel still rendered (Roster's header row exists somewhere)
      assert Enum.any?(cells, &(&1.y == 5))
    end

    test "safe_read returns the fun's value on success" do
      assert Board.safe_read(:crew, nil, fn -> %{coworkers: []} end) == %{coworkers: []}
    end

    test "safe_read degrades a raise to the fallback and logs it" do
      File.rm(Console.CrashLog.path())

      assert Board.safe_read(:crew, :fallback, fn -> raise "kaboom" end) == :fallback

      log = File.read!(Console.CrashLog.path())
      assert log =~ "read error: crew"
      assert log =~ "kaboom"
    end

    test "safe_read degrades an exit (a dead funes GenServer) to the fallback and logs it" do
      File.rm(Console.CrashLog.path())

      read = fn -> GenServer.call(:no_such_process_anywhere, :probe) end
      assert Board.safe_read(:presence, %{}, read) == %{}

      assert File.read!(Console.CrashLog.path()) =~ "read error: presence"
    end

    test "safe_read degrades a throw to the fallback" do
      assert Board.safe_read(:stack, [], fn -> throw(:oops) end) == []
    end

    test "control bytes in panel content are never emitted to the terminal" do
      # A stray ESC (27) or other C0/C1 control byte from a captured tmux pane would, painted
      # raw, be read by the terminal as the start of an escape sequence and shift the whole
      # screen's colours. The paint boundary must neutralise them to a space (0x20).
      rect = %{x: 0, y: 0, w: 20, h: 3}
      panel = {SanitizeProbe, "a\e[31mb\tc", rect}

      chars = [panel] |> Board.compose(80, 24) |> Enum.map(& &1.ch)

      refute 27 in chars, "ESC leaked into a cell"
      refute 9 in chars, "TAB leaked into a cell"
      assert Enum.all?(chars, &(&1 >= 32 and &1 != 127)), "a control byte reached the terminal"
      # printable characters survive
      assert ?a in chars and ?b in chars and ?c in chars
    end
  end
end
