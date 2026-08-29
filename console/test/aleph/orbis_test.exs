defmodule Console.OrbisTest do
  # The rollup DATA semantics (Orbis Tertius slice 2): the pure status + tally rules shared by the
  # Tlön sidebar panel and the chat-tab strip. `rollup/0` itself reads funes (exercised live, not
  # here, like the cockpit reads); these pin the pure rules so the two surfaces can never drift.
  use ExUnit.Case, async: true

  alias Console.Orbis

  describe "status/2" do
    test "a closed thread is done, regardless of conflicts" do
      assert Orbis.status("closed", 0) == :done
      assert Orbis.status("closed", 3) == :done
    end

    test "an open thread with a blocker or failed check is stalled" do
      assert Orbis.status("open", 1) == :stalled
    end

    test "an open thread with a clean board is open" do
      assert Orbis.status("open", 0) == :open
    end
  end

  describe "summarize/1" do
    test "tallies each bucket and sums conflicts across rows" do
      rows = [
        %{status: :stalled, conflicts: 2},
        %{status: :open, conflicts: 0},
        %{status: :open, conflicts: 0},
        %{status: :done, conflicts: 0}
      ]

      assert Orbis.summarize(rows) == %{open: 2, stalled: 1, done: 1, conflicts: 2}
    end

    test "an empty list is all zeros" do
      assert Orbis.summarize([]) == %{open: 0, stalled: 0, done: 0, conflicts: 0}
    end
  end

  describe "workspaces/1" do
    # workspaces/1 reads the live Console.Workspaces cache (funes down under test → []). The literal-Tlön
    # fallback is gone (reshape slice A): no workspace refs means no survey rows — honest, since funes
    # self-seeds a default workspace at boot.
    test "funes down → no survey rows, no fake workspace" do
      rows = [%{status: :open, conflicts: 0}]
      assert Orbis.workspaces(rows) == []
    end
  end

  describe "workspaces/2 (grouped by real workspace refs — D0.3: every row carries its funes id)" do
    # workspaces/1 reads the live Console.Workspaces cache (funes down under test → [] → literal "Tlön"
    # fallback, covered above). workspaces/2 is the pure grouping it delegates to, tested with
    # injected `%{id, name}` refs so a real funes workspace's id/name drives the survey row.
    test "one workspace → the rollup rows group under that workspace's real id + name" do
      rows = [%{status: :open, conflicts: 0}, %{status: :stalled, conflicts: 1}]

      assert [%{id: 7, name: "Freedonia", summary: summary, leaves: ^rows}] =
               Orbis.workspaces(rows, [%{id: 7, name: "Freedonia"}])

      assert summary == %{open: 1, stalled: 1, done: 0, conflicts: 1}
    end

    test "rows group under THEIR OWN workspace (real membership, reshape slice C)" do
      rows = [
        %{status: :open, conflicts: 0, workspace_id: 1},
        %{status: :stalled, conflicts: 2, workspace_id: 2},
        %{status: :open, conflicts: 0, workspace_id: 2}
      ]

      assert [freedonia, ruritania] =
               Orbis.workspaces(rows, [%{id: 1, name: "Freedonia"}, %{id: 2, name: "Ruritania"}])

      assert %{id: 1, name: "Freedonia", summary: %{open: 1, stalled: 0}} = freedonia
      assert length(freedonia.leaves) == 1
      assert %{id: 2, name: "Ruritania", summary: %{open: 1, stalled: 1, conflicts: 2}} = ruritania
      assert length(ruritania.leaves) == 2
    end

    test "a row matching no ref lands in the FIRST workspace — belt over slice A's repair" do
      rows = [%{status: :open, conflicts: 0, workspace_id: 999}, %{status: :open, conflicts: 0}]

      assert [%{id: 1, leaves: leaves}, %{id: 2, leaves: []}] =
               Orbis.workspaces(rows, [%{id: 1, name: "A"}, %{id: 2, name: "B"}])

      assert length(leaves) == 2
    end

    test "no workspace refs → no rows (the fake-Tlön fallback is gone)" do
      rows = [%{status: :open, conflicts: 0}]
      assert Orbis.workspaces(rows, []) == []
    end
  end
end
