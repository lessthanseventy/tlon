defmodule Console.Panel.StatusBarTest do
  # The contextual footer (design 2026-08-23): mode segment (TERM/NAV/LOCK's own verbs) → space
  # segment (workspace-only post/task/driver) → the focused pane's own hints. Keyed on workspace?, never
  # the space label — the stale "Tlön"-keyed table died with this.
  use ExUnit.Case, async: true

  alias Console.Panel.StatusBar

  defp rect, do: %{x: 0, y: 0, w: 120, h: 2}

  defp base(over) do
    Map.merge(
      %{
        space: "Tlön",
        thread: nil,
        thread_count: 0,
        live_count: 0,
        input: nil,
        flash: nil,
        leader_pending?: false,
        focus: nil,
        mode: nil,
        workspace?: false,
        lock?: false,
        pane_hints: []
      },
      over
    )
  end

  # HEALTH demoted to the footer (reshape slice D): a condensed one-line segment on the info
  # line's right — service dots + disk/mem/load. The full readout moved to /status.
  test "the info line carries a condensed health segment when the read is up" do
    health = %{
      funes_up: true,
      tlon_up: false,
      nix_gen: 36,
      nix_behind: 0,
      disk_pct: 68,
      mem_pct: 28,
      load_avg: 2.18,
      tools: []
    }

    [info, _hints] = StatusBar.render(base(%{health: health}), rect())
    line = Enum.map_join(info, fn {t, _} -> t end)

    assert line =~ "funes"
    assert line =~ "tlon"
    assert line =~ "d68%"
    assert line =~ "m28%"
    assert line =~ "l2.2"
  end

  test "a nil health read (probe not run) leaves the footer clean" do
    [info, _hints] = StatusBar.render(base(%{health: nil}), rect())
    line = Enum.map_join(info, fn {t, _} -> t end)
    refute line =~ "funes"
  end

  test "TERM mode: the mode segment names the Alt door and the nav toggle" do
    [_info, hints] = StatusBar.render(base(%{mode: :term, workspace?: true}), rect())
    line = Enum.map_join(hints, fn {t, _} -> t end)
    assert line =~ "Alt+#"
    assert line =~ "^␣"
    refute line =~ "space"
  end

  test "NAV mode: mode + space verbs + the focused pane's own verbs" do
    data = base(%{mode: :nav, workspace?: true, pane_hints: [{"j/k", "commits"}, {"⏎", "diff"}]})
    [_info, hints] = StatusBar.render(data, rect())
    line = Enum.map_join(hints, fn {t, _} -> t end)
    assert line =~ "Alt+0"
    assert line =~ "c post"
    assert line =~ "n task"
    assert line =~ "m driver"
    assert line =~ "j/k commits"
    assert line =~ "⏎ diff"
  end

  test "LOCK mode: the unlock chord alone, and a warning chip" do
    [info, hints] = StatusBar.render(base(%{mode: :lock, workspace?: true}), rect())
    assert {" LOCK ", :stat_warn} in info
    line = Enum.map_join(hints, fn {t, _} -> t end)
    assert line =~ "Alt+g unlock"
    refute line =~ "post"
  end

  test "a non-workspace space (mode nil) keeps the shared leader table" do
    [_info, hints] = StatusBar.render(base(%{space: "Orbis"}), rect())
    assert Enum.map_join(hints, fn {t, _} -> t end) =~ "^␣n new"
  end

  test "hints keyed on workspace-ness, never the label: a renamed workspace still gets workspace hints" do
    data = base(%{space: "Uqbar", mode: :nav, workspace?: true})
    [_info, hints] = StatusBar.render(data, rect())
    assert Enum.map_join(hints, fn {t, _} -> t end) =~ "c post"
  end
end
