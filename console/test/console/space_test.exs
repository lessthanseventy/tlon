defmodule Console.SpaceTest do
  @moduledoc """
  Console.Space.all/0 + next/prev — the picker order after the Slice 0 collapse. Sessions is deleted;
  only Orbis (the god-view survey) and one Workspace space remain, and Tab cycles between the two.

  Phase C1.2: Workspace spaces are keyed by their funes id (not a name slug), so id-keying is exercised
  throughout — the fixture `@tlon` carries `id: 1` and the fallback (funes down / no workspaces) keys as
  the sentinel `0`.
  """
  use ExUnit.Case, async: true

  alias Console.Panel.Activity
  alias Console.Panel.Crew
  alias Console.Panel.Memory
  alias Console.Panel.NewThread
  alias Console.Panel.Stack
  alias Console.Panel.Terminal
  alias Console.Panel.Tertius
  alias Console.Space

  # `Space.workspace?/1` is a `defguard` (Phase C1.3), which requires the module, not just an alias.
  require Space

  # The seeded Tlön workspace, aleph-shaped (Console.Workspaces.all/0 output — string-keyed roster from JSON).
  @tlon %{
    id: 1,
    name: "Tlön",
    type: "code",
    scope: "machine",
    paths: ["modules/*"],
    roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
  }

  test "funes down → no spaces at all; no fake Workspace, no Home (UX slice 1, task 5)" do
    # Space.all/0 reads the live Console.Workspaces cache (funes down under test → []). The hardcoded
    # Tlön fallback is gone: funes self-seeds a default workspace at boot (Server.Bootstrap), so an
    # empty workspace list means funes is genuinely down — rendered honestly, not papered over.
    assert Space.all() == []
  end

  test "Tab with no workspaces goes nowhere (nil), and with one wraps to itself" do
    assert Space.next(1) == nil
    assert Space.prev(1) == nil
    [only] = Space.all([@tlon])
    assert Space.next(only.key, [only]).key == only.key
  end

  describe "all/1 (derived from funes workspaces)" do
    test "one seeded Tlön workspace → picker is exactly [1]" do
      assert Enum.map(Space.all([@tlon]), & &1.key) == [1]
    end

    test "the derived Tlön space matches the Slice-0 hardcoded surface/coworker/left/right" do
      tlon = Enum.find(Space.all([@tlon]), &(&1.key == 1))

      assert tlon.id == 1
      assert tlon.label == "Tlön"
      # Center bands (2026-09-01): the Terminal/thread-stack, the persistent new-thread input, then the
      # tertius orchestrator line.
      assert tlon.surface == [{Terminal, :machine}, NewThread, Tertius]
      # Slice 3.4: the funes panels stack in the left RAIL (NOW·CREW·MEMORY·STACK); the Sidebar
      # renders as the thin spine (split out in View.compose); the right rail is retired.
      assert tlon.left == [Activity, Crew, Memory, Stack]
      assert tlon.right == []
      # The roster lead's name (string-keyed JSON) becomes the center coworker.
      assert tlon.coworker == "tertius"
      # The full roster rides along too (C2/C3 read it), not just the derived coworker name.
      assert tlon.roster == @tlon.roster
    end

    test "empty workspaces → nothing, no fabricated Workspace" do
      assert Space.all([]) == []
    end

    test "two workspaces → [1, 2], keyed by funes id" do
      freedonia = %{@tlon | id: 2, name: "Freedonia", roster: [%{"archetype" => "surveyor", "name" => "rufus"}]}

      spaces = Space.all([@tlon, freedonia])
      assert Enum.map(spaces, & &1.key) == [1, 2]

      second = Enum.find(spaces, &(&1.key == 2))
      assert second.id == 2
      assert second.label == "Freedonia"
      assert second.coworker == "rufus"
    end

    test "a workspace space is keyed by its funes id" do
      spaces =
        Space.all([
          %{id: 7, name: "Tlön", roster: [%{"name" => "tertius"}], type: "code", paths: [], scope: "machine"}
        ])

      assert [%{key: 7, label: "Tlön", id: 7}] = spaces
    end

    test "a roster with atom keys still yields the lead coworker (defensive)" do
      atomish = %{@tlon | roster: [%{archetype: "surveyor", name: "tertius"}]}
      tlon = Enum.find(Space.all([atomish]), &(&1.key == 1))
      assert tlon.coworker == "tertius"
    end
  end

  describe "first_workspace/0 with no workspaces" do
    test "is nil — funes-genuinely-empty, no sentinel" do
      # Reads the live cache (down under test → []); callers own the nil.
      assert Space.first_workspace() == nil
    end
  end

  describe "fetch/2 (pure, over an explicit spaces list)" do
    test "returns the matching space" do
      spaces = Space.all([@tlon])
      assert Space.fetch(1, spaces).key == 1
    end

    test "returns nil on a missing key (no silent Orbis default)" do
      assert Space.fetch(999, Space.all([@tlon])) == nil
    end
  end

  describe "fetch/1 (reads the live cache)" do
    test "returns nil on a missing key" do
      assert Space.fetch(999) == nil
    end
  end

  describe "workspace?/1" do
    test "is the mode predicate: any integer key is a Workspace, anything else is not" do
      refute Space.workspace?(:orbis)
      refute Space.workspace?(nil)
      assert Space.workspace?(1)
      assert Space.workspace?(0)
    end
  end

  describe "roster/2 and active_workspace_id/1" do
    test "roster is the workspace's cast, [] for a missing workspace" do
      spaces = Space.all([@tlon])
      assert Space.roster(@tlon.id, spaces) == @tlon.roster
      assert Space.roster(999, spaces) == []
    end

    test "active_workspace_id is the active key when it names a Workspace" do
      assert Space.active_workspace_id(%{active_key: 7}) == 7
    end
  end

  describe "the retired right rail (Slice 3.4)" do
    test "every space has an empty right column" do
      [space] = Space.all([@tlon])

      # The right rail is gone: `right` is [] — the funes panels live in the drawer now.
      assert space.right == []
    end
  end
end
