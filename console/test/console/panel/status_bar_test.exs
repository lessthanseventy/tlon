defmodule Console.Panel.StatusBarTest do
  # The contextual footer (design 2026-08-23): mode segment (TERM/NAV/LOCK's own verbs) → space
  # segment (workspace-only post/task/driver) → the focused pane's own hints. Keyed on workspace?, never
  # the space label — the stale "Tlön"-keyed table died with this.
  #
  # UX slice 1: ONE row. The info row (mode chip, space, thread, counts, HEALTH) is gone — where you
  # are moved to Console.Panel.TopBar, HEALTH to the drawer.
  use ExUnit.Case, async: true

  import Console.PanelText, only: [text: 1]

  alias Console.Panel.StatusBar

  defp rect, do: %{x: 0, y: 0, w: 120, h: 1}

  defp base(over) do
    Map.merge(
      %{
        input: nil,
        flash: nil,
        leader_pending?: false,
        mode: nil,
        workspace?: false,
        pane_hints: []
      },
      over
    )
  end

  # HEALTH left the footer with UX slice 1 (it lands in the drawer, task 4) — the footer must not
  # resurrect a second row for it.
  test "a health read no longer renders in the footer" do
    health = %{funes_up: true, tlon_up: false, disk_pct: 68, mem_pct: 28, load_avg: 2.18, tools: []}
    rows = StatusBar.render(base(%{health: health}), rect())

    assert length(rows) == 1
    refute text(rows) =~ "d68%"
  end

  test "an orchestrate input does NOT render in the footer (it lives in the Tertius band) — no duplication" do
    input = %{kind: :orchestrate, buffer: "file a ticket x", cursor: 15}
    [hints] = StatusBar.render(base(%{input: input}), rect())
    # falls through to the normal footer; the typed buffer is not repeated here
    refute text([hints]) =~ "file a ticket x"
  end

  test "TERM mode: the mode segment names the Alt door and the nav toggle" do
    [hints] = StatusBar.render(base(%{mode: :term, workspace?: true}), rect())
    line = text([hints])
    assert line =~ "Alt+#"
    assert line =~ "^␣"
    refute line =~ "space"
  end

  test "NAV mode: mode + space verbs + the focused pane's own verbs" do
    data = base(%{mode: :nav, workspace?: true, pane_hints: [{"j/k", "commits"}, {"⏎", "diff"}]})
    [hints] = StatusBar.render(data, rect())
    line = text([hints])
    assert line =~ "Alt+0"
    assert line =~ "c reply"
    assert line =~ "n new"
    assert line =~ "m model"
    assert line =~ "j/k commits"
    assert line =~ "⏎ diff"
  end

  test "NAV mode names the session pane's mode, so Alt+\\ says what it would leave" do
    for {mode, label} <- [{:auto, "Alt+\\ pane auto"}, {true, "Alt+\\ pane on"}, {false, "Alt+\\ pane off"}] do
      data = base(%{mode: :nav, workspace?: true, session_pane_mode: mode})
      assert text(StatusBar.render(data, rect())) =~ label
    end
  end

  test "LOCK mode: the unlock chord alone" do
    [hints] = StatusBar.render(base(%{mode: :lock, workspace?: true}), rect())
    line = text([hints])
    assert line =~ "Alt+g unlock"
    refute line =~ "post"
  end

  test "a non-workspace space (mode nil) keeps the shared leader table" do
    [hints] = StatusBar.render(base(%{}), rect())
    assert text([hints]) =~ "^␣n new"
  end

  test "hints keyed on workspace-ness, never the label: a renamed workspace still gets workspace hints" do
    data = base(%{mode: :nav, workspace?: true})
    [hints] = StatusBar.render(data, rect())
    assert text([hints]) =~ "c reply"
  end

  # UX slice 1: the footer's row is ONE row high, so every face has to fit its verbs onto that row.
  # These pin the load-bearing verb of each face — the escape hatch above all.
  describe "the one-row faces" do
    defp face(over) do
      rows = StatusBar.render(base(over), rect())
      assert length(rows) == 1
      text(rows)
    end

    test "the composer face: the chip, the reply verb and the escape hatch" do
      line = face(%{input: %{kind: :compose, buffer: "hi", cursor: 2}})

      assert line =~ "COMPOSE"
      assert line =~ "⏎ reply"
      assert line =~ "Esc cancel"
    end

    test "the new-ticket face: the prompt, the typed title and both verbs" do
      line = face(%{input: %{kind: :new_ticket, buffer: "flaky test", cursor: 10}})

      assert line =~ "NEW TICKET"
      assert line =~ "flaky test"
      assert line =~ "⏎ create"
      assert line =~ "Esc cancel"
    end

    test "the new-note face" do
      line = face(%{input: %{kind: :new_note, buffer: "jot", cursor: 3}})

      assert line =~ "NEW NOTE"
      assert line =~ "jot"
      assert line =~ "⏎ create"
      assert line =~ "Esc cancel"
    end

    test "the new-workspace face keeps its template cycler too" do
      line = face(%{input: %{kind: :new_workspace, template: "code", buffer: "aleph", cursor: 5}})

      assert line =~ "NEW WORKSPACE"
      assert line =~ "code"
      assert line =~ "aleph"
      assert line =~ "⏎ create"
      assert line =~ "h/l template"
      assert line =~ "Esc cancel"
    end

    test "the new-path face" do
      line = face(%{input: %{kind: :new_path, buffer: "modules/*", cursor: 9}})

      assert line =~ "NEW PATH"
      assert line =~ "modules/*"
      assert line =~ "⏎ add"
      assert line =~ "Esc cancel"
    end

    test "the new-roster face keeps its archetype cycler too" do
      line = face(%{input: %{kind: :new_roster, archetype: "builder", buffer: "hronir", cursor: 6}})

      assert line =~ "NEW ROSTER ENTRY"
      assert line =~ "builder"
      assert line =~ "hronir"
      assert line =~ "⏎ add"
      assert line =~ "h/l archetype"
      assert line =~ "Esc cancel"
    end

    test "a flash shares its row with the hints" do
      line = face(%{flash: "spawned %7", mode: :nav, workspace?: true})

      assert line =~ "spawned %7"
      assert line =~ "c reply"
    end

    test "the armed prefix names the state AND what the next key can be" do
      line = face(%{leader_pending?: true})

      assert line =~ "prefix armed"
      assert line =~ "Esc cancel"
      assert line =~ "n new"
    end

    test "too narrow for the verbs: the prompt survives and the row stays one line" do
      rows =
        StatusBar.render(base(%{input: %{kind: :new_ticket, buffer: "flaky test hunt", cursor: 15}}), %{
          x: 0,
          y: 0,
          w: 34,
          h: 1
        })

      assert [row] = rows
      assert text(rows) =~ "NEW TICKET"
      assert Console.Panel.row_width(row) <= 34
    end
  end

  # Esc must survive a narrow footer on every modal input face — it's the escape hatch, same as
  # the leader face. A realistic typed buffer used to push it off the tail before "⏎ create".
  describe "Esc cancel survives a narrow footer (modal input faces)" do
    defp narrow_face(input, w) do
      rows = StatusBar.render(base(%{input: input}), %{x: 0, y: 0, w: w, h: 1})
      assert length(rows) == 1
      text(rows)
    end

    test "new_ticket" do
      input = %{kind: :new_ticket, buffer: "flaky test hunt", cursor: 15}
      assert narrow_face(input, 60) =~ "Esc"
      assert narrow_face(input, 40) =~ "Esc"
    end

    test "new_note" do
      input = %{kind: :new_note, buffer: "flaky test hunt", cursor: 15}
      assert narrow_face(input, 60) =~ "Esc"
      assert narrow_face(input, 40) =~ "Esc"
    end

    test "new_workspace" do
      input = %{kind: :new_workspace, template: "code", buffer: "flaky test hunt", cursor: 15}
      assert narrow_face(input, 60) =~ "Esc"
      assert narrow_face(input, 40) =~ "Esc"
    end

    test "new_path" do
      input = %{kind: :new_path, buffer: "modules/*", cursor: 9}
      assert narrow_face(input, 60) =~ "Esc"
      assert narrow_face(input, 40) =~ "Esc"
    end

    # archetype "qa" (not "builder"): the fix clips the typed buffer, not the archetype chip —
    # at w:40 "◂ builder ▸ " alone leaves no room for Esc no matter how far the buffer shrinks.
    test "new_roster" do
      input = %{kind: :new_roster, archetype: "qa", buffer: "flaky test hunt", cursor: 15}
      assert narrow_face(input, 60) =~ "Esc"
      assert narrow_face(input, 40) =~ "Esc"
    end
  end
end
