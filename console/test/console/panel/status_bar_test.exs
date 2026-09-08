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
end
