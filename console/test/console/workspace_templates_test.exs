defmodule Console.WorkspaceTemplatesTest do
  # The nix-owned workspace-archetype registry (capabilities): starter type/repos/roster the author
  # face's "new workspace" composes a funes row from. Distinct from Server.Profiles' coworker archetypes.
  use ExUnit.Case, async: true

  alias Console.WorkspaceTemplates

  test "the three workspace archetypes exist" do
    assert MapSet.new(WorkspaceTemplates.names()) == MapSet.new([:code, :life, :blank])
  end

  test "the code template carries a full starter crew over modules/*" do
    t = WorkspaceTemplates.template(:code)
    assert t.type == "code"
    assert t.repos == ["modules/*"]
    # A real crew so a fresh workspace feels alive: orchestrator, lead, reviewer, planner.
    assert Enum.map(t.roster, & &1.archetype) == [:surveyor, :builder, :reviewer, :planner]
  end

  test "the blank template is empty (no roster, no repos)" do
    t = WorkspaceTemplates.template(:blank)
    assert t.type == "blank"
    assert t.roster == []
    assert t.repos == []
  end

  test "template/1 raises on an unknown key" do
    assert_raise KeyError, fn -> WorkspaceTemplates.template(:nope) end
  end

  test "new_workspace_attrs builds register_workspace attrs from a template + name (string-keyed bench entries)" do
    attrs = WorkspaceTemplates.new_workspace_attrs(:code, "Ficciones2")

    assert attrs.name == "Ficciones2"
    assert attrs.type == "code"
    assert attrs.scope == "machine"
    assert attrs.repos == ["modules/*"]
    # roster is the funes wire shape: string-keyed maps, matching the seed roster
    assert attrs.roster == [
             %{"archetype" => "surveyor", "name" => "surveyor"},
             %{"archetype" => "builder", "name" => "builder"},
             %{"archetype" => "reviewer", "name" => "reviewer"},
             %{"archetype" => "planner", "name" => "planner"}
           ]
  end

  test "new_workspace_attrs from :blank yields an empty roster" do
    assert WorkspaceTemplates.new_workspace_attrs(:blank, "Scratch").roster == []
  end
end
