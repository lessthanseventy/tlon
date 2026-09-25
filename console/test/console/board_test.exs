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

  import Console.PanelText, only: [row_text: 1]

  alias Console.Board
  alias Console.Panel
  alias Console.Panel.Activity
  alias Console.Panel.Border
  alias Console.Panel.Health
  alias Console.Panel.Rail
  alias Console.Panel.Roster
  alias Console.Panel.Stack
  alias Console.Panel.StatusBar
  alias Console.Panel.Terminal
  alias Console.Panel.Tertius
  alias Console.Panel.TopBar
  alias Console.View

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

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
        active_key: 0,
        focused_id: 1,
        focused_title: "review PR 329",
        bench: @roster,
        threads: @threads,
        chorus: [],
        health: nil,
        triage: %{blockers: %{shown: [], more: 0}, failed_checks: %{shown: [], more: 0}, unassigned: []}
      },
      overrides
    )
  end

  # A Workspace chat with a thread OPEN and the session pane pinned on — the only Panel.Terminal in
  # the frame is then the pane's (the centre holds the conversation).
  defp pane_reads(overrides \\ %{}) do
    reads(
      Map.merge(
        %{
          active_key: 0,
          center_view: :chat,
          thread_stack: %{cards: [], opened: 7},
          session_pane: 7,
          session_pane_mode: true,
          session: :no_session,
          machine: :no_session,
          stack: nil,
          health: nil
        },
        overrides
      )
    )
  end

  describe "panels render styled rows" do
    test "bench: one row per session, warmth marked (title lives on the frame now)" do
      rect = %{x: 0, y: 0, w: 40, h: 10}
      assert [sandra, robert] = Roster.render(%{sessions: @roster}, rect)
      assert row_text(sandra) =~ "Sandra"
      assert row_text(sandra) =~ "review PR 329"
      assert row_text(sandra) =~ "●"
      assert row_text(robert) =~ "○"
    end

    test "no separate thread-list panel — the center thread-stack is the list" do
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
      assert row_text(branch) =~ "main"
      assert row_text(meta) =~ "bc86cc8"
      assert row_text(meta) =~ "2 hours ago"
      assert row_text(subject) =~ "open_thread"
      assert Enum.any?(meta, fn {t, s} -> s == :dim and t =~ "bc86cc8" end)
    end

    test "stack (Tlön): ahead/behind tracking and dirty status" do
      rect = %{x: 0, y: 0, w: 60, h: 10}
      data_ahead = %{branch: "main", dirty: false, ahead: 3, behind: 1, status_summary: nil, commits: []}
      rows = Stack.render(data_ahead, rect)
      branch_row = Enum.find(rows, fn r -> row_text(r) =~ "main" end)
      assert row_text(branch_row) =~ "↑"
      assert row_text(branch_row) =~ "3"
      assert row_text(branch_row) =~ "↓"
      assert row_text(branch_row) =~ "1"

      data_dirty = %{
        branch: "main",
        dirty: true,
        ahead: 0,
        behind: 0,
        status_summary: %{staged: 2, unstaged: 1, untracked: 3},
        commits: []
      }

      rows_dirty = Stack.render(data_dirty, rect)
      joined = Enum.map_join(rows_dirty, "\n", &row_text/1)
      assert joined =~ "✗"
      assert joined =~ "+2"
      assert joined =~ "~1"
      assert joined =~ "?3"
    end

    test "stack (Tlön): honest when there is no git history" do
      rect = %{x: 0, y: 0, w: 60, h: 10}
      data = %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: []}
      assert [_label, branch, _rule, _commits_label, empty] = Stack.render(data, rect)
      assert row_text(branch) =~ "no branch"
      assert row_text(empty) =~ "no git history"
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
      joined = Enum.map_join(rows, "\n", &row_text/1)
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

    test "terminal panel shows the empty state when there is no session — no dead verb" do
      rows = Terminal.render(:no_session, %{x: 0, y: 0, w: 60, h: 4})
      shown = Enum.map_join(rows, "\n", &row_text/1)

      # ONE copy source (Panel.Placeholder) so the two empty states can't drift apart, and no verb
      # that doesn't exist: `Enter` never spawned anything here.
      assert shown =~ Console.Panel.Placeholder.copy()
      refute shown =~ "Enter to spawn"
    end
  end

  describe "panel pick — click a row to select (pure decision, design §8)" do
    test "bench: a session row focuses the thread it's working (no header chrome — rows start at 0)" do
      data = %{sessions: @roster, scroll: 0}
      rect = %{x: 0, y: 0, w: 40, h: 10}
      assert {:focus_thread, 1} = Roster.pick(data, rect, 0)
      assert {:focus_thread, 2} = Roster.pick(data, rect, 1)
      assert Roster.pick(data, rect, 99) == nil
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
      Map.merge(%{mode: nil, workspace?: false, pane_hints: []}, overrides)
    end

    # UX slice 1: the footer is ONE row of hints — the space/thread/counts info row moved to
    # Console.Panel.TopBar.
    test "the footer is a single hints row" do
      assert [hints] = StatusBar.render(status(), %{x: 0, y: 0, w: 120, h: 1})
      joined = row_text(hints)
      assert joined =~ "go to"
      assert joined =~ "commands"
      refute joined =~ "threads "
    end

    # UX slice 1: one row — the chip and the composer verbs share it.
    test "composing shows the mode chip and the composer verbs — the buffer lives in the compose box" do
      data = status(%{input: %{kind: :compose, thread_id: 2, buffer: "ship it"}})
      assert [row] = StatusBar.render(data, %{x: 0, y: 0, w: 120, h: 1})
      joined = row_text(row)
      assert joined =~ "COMPOSE"
      refute joined =~ "ship it"
      assert joined =~ "reply"
      assert joined =~ "newline"
    end
  end

  describe "border box" do
    test "draws a rounded box framing the whole rect" do
      rows = Border.render(nil, %{x: 0, y: 0, w: 6, h: 4})
      assert length(rows) == 4
      assert row_text(Enum.at(rows, 0)) == "╭────╮"
      assert row_text(Enum.at(rows, 3)) == "╰────╯"
      mid = Enum.at(rows, 1)
      assert row_text(mid) == "│    │"
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
      assert String.length(row_text(clipped)) == 5
    end
  end

  describe "view composition" do
    test "a workspace: the rail, the centre surface, a box per section, status bar — all in bounds" do
      placements = View.compose(reads(), 120, 40)
      mods = Enum.map(placements, fn {m, _d, _r} -> m end)

      assert Rail in mods
      assert Terminal in mods
      assert StatusBar in mods
      # every section gets its own bordered box (rail, centre) — the frame's two bars are borderless.
      content_panels = Enum.reject(mods, &(&1 in [Border, TopBar, StatusBar]))
      assert Enum.count(mods, &(&1 == Border)) == length(content_panels)
      assert length(content_panels) >= 2

      Enum.each(placements, fn {_m, _d, r} ->
        assert r.x >= 0 and r.y >= 0
        assert r.x + r.w <= 120
        assert r.y + r.h <= 40
      end)
    end

    test "content sits inside its column box, not against the frame" do
      placements = View.compose(reads(), 120, 40)
      {_m, _d, rail_rect} = Enum.find(placements, fn {m, _d, _r} -> m == Rail end)
      # the rail's content is inset from the left frame — padded, not jammed to x=0
      assert rail_rect.x >= 2
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

      # the terminal is framed by the tertius band below it — no longer the full-height center column
      # a single-section surface would give it.
      assert [{Terminal, :no_session, term_rect}] = Enum.filter(placements, fn {m, _d, _r} -> m == Terminal end)
      assert [{Tertius, _data, pulse_rect}] = Enum.filter(placements, fn {m, _d, _r} -> m == Tertius end)

      assert pulse_rect.y > term_rect.y
      assert term_rect.h < 38
    end

    test "the PTY sizes to the placed Terminal rect — no overflow past the frame" do
      # center_rect is what the embedded PTY is sized to; it MUST equal the rect compose places the
      # Terminal into, or pi draws wider/taller than the visible area (content spills past the frame,
      # or a dead band opens below). One authority for both, asserted across sizes. A Workspace is the
      # only terminal-bearing space; its column also carries the NewThread/Tertius bands.
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

    test "the session pane's PTY sizes to the placed pane rect — the twin of center_rect" do
      # session_rect is what the ATTACHED tmux client is sized to; like center_rect it must equal the
      # rect compose places the pane into, or the coworker's terminal draws past its half (or short
      # of it). The pane is pinned on so the split holds below the two-pane floor too.
      for {w, h} <- [{120, 40}, {100, 30}, {84, 30}, {200, 50}, {101, 24}, {100, 12}] do
        {_m, _d, pane_rect} = Enum.find(View.compose(pane_reads(), w, h), fn {m, _d, _r} -> m == Terminal end)

        assert View.session_rect(w, h) == pane_rect,
               "session_rect drifted from the pane placement at #{w}x#{h}"
      end
    end

    test "an open composer shrinks both PTY authorities — neither draws under the compose box" do
      # compose/3 subtracts the composer's rows from the body; center_rect/session_rect must too, or
      # a PTY attached while `c` is open is two rows too tall.
      input = %{kind: :compose, thread_id: 1, buffer: "one\ntwo", cursor: 7}

      centre =
        reads(%{
          active_key: 0,
          machine: :no_session,
          stack: %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: [], tools: []},
          health: nil,
          input: input
        })

      {_m, _d, term_rect} = Enum.find(View.compose(centre, 120, 40), fn {m, _d, _r} -> m == Terminal end)
      assert View.center_rect(0, 120, 40, input) == term_rect

      {_m, _d, pane_rect} =
        Enum.find(View.compose(pane_reads(%{input: input}), 120, 40), fn {m, _d, _r} -> m == Terminal end)

      assert View.session_rect(120, 40, input) == pane_rect
    end

    test "a short Tlön terminal never places a section (or the PTY) past the frame" do
      # Fixed bands + a flex Terminal stacked in the center column can overflow at short heights if
      # split_heights never clamps the SUM against the column (a lower band lands on/past the
      # StatusBar). The clamp shrinks the fixed bands in stack order — a lower band collapses to 0
      # rather than going off-frame.
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

          assert rect.y + rect.h <= h,
                 "#{inspect(mod)} overflowed the frame height at #{key} #{w}x#{h}: #{inspect(rect)}"
        end)

        cr = View.center_rect(key, w, h)
        assert cr.y + cr.h <= h, "the PTY center_rect fell past the frame at #{key} #{w}x#{h}: #{inspect(cr)}"
        assert cr.x + cr.w <= w
      end
    end

    test "a workspace centers its thread surface, with the rail at its side" do
      placements = View.compose(reads(%{active_key: 0}), 120, 40)
      mods = Enum.map(placements, fn {m, _d, _r} -> m end)
      # the rail is the left column in EVERY space since UX slice 1 — ROSTER/TRIAGE are drawer panes
      assert Terminal in mods
      assert Rail in mods
      refute Roster in mods
    end

    test "a thread with a worktree splits the right column: the coworker above, lazygit below, each PTY sized to its rect" do
      for {w, h} <- [{120, 40}, {200, 50}, {101, 24}] do
        terms =
          %{git_pane: 7, git: :no_session}
          |> pane_reads()
          |> View.compose(w, h)
          |> Enum.filter(fn {m, _d, _r} -> m == Terminal end)
          |> Enum.sort_by(fn {_m, _d, r} -> r.y end)

        assert [{_, _, top}, {_, _, bottom}] = terms
        assert {top.x, top.w} == {bottom.x, bottom.w}
        assert bottom.y > top.y + top.h

        assert View.right_rects(w, h, nil, true) == %{session: top, git: bottom}, "right_rects drifted at #{w}x#{h}"
      end
    end

    test "the pane forced off takes lazygit with it — no right column, no git pane" do
      r = pane_reads(%{session_pane: nil, session_pane_mode: false, git_pane: 7, git: :no_session})
      assert [] = Enum.filter(View.compose(r, 120, 40), fn {m, _d, _r} -> m == Terminal end)
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

    test "a wide viewport lays out two columns" do
      xs = reads() |> View.compose(140, 40) |> box_xs()
      # two distinct column x-offsets since UX slice 1: the rail at 0, the center past it
      assert length(xs) == 2
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
