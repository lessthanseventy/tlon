defmodule Server.CoworkerStatusTest do
  # One seat status for every surface: working | waiting | idle | off | cold, from the facts the roster
  # and the office already hold.
  use ExUnit.Case, async: true

  alias Server.Coworker

  @live %{on_shift: true, session: true, windowed: true, warm: true, thinking: false, waiting: false}

  test "each state, from the facts" do
    assert Coworker.status(@live) == :idle
    assert Coworker.status(%{@live | thinking: true}) == :working
    assert Coworker.status(%{@live | waiting: true}) == :waiting
    assert Coworker.status(%{@live | warm: false, windowed: false}) == :cold
    assert Coworker.status(%{@live | on_shift: false}) == :off
    assert Coworker.status(%{@live | session: false, windowed: false, warm: false}) == :off
  end

  test "waiting on the operator outranks mid-turn; off outranks everything; a window with no session yet is up" do
    assert Coworker.status(%{@live | thinking: true, waiting: true}) == :waiting
    assert Coworker.status(%{@live | on_shift: false, thinking: true, waiting: true}) == :off
    assert Coworker.status(%{@live | session: false, warm: false}) == :idle
  end

  test "every state has its one glyph" do
    glyphs = for s <- Coworker.statuses(), do: Coworker.glyph(s)
    assert Enum.uniq(glyphs) == glyphs
    assert Coworker.statuses() == [:working, :waiting, :idle, :off, :cold]
  end

  test "the CLI roster line is the glyph, the agent, the status word, then its thread and pane" do
    row = %{status: :waiting, agent: "borges", thread_id: 12, title: "asked", pane_ref: "%3"}
    assert Coworker.roster_line(row) == "! borges waiting — #12 asked [%3]"
    assert Coworker.roster_line(%{row | status: :cold, pane_ref: nil}) == "◌ borges cold — #12 asked"
  end
end
