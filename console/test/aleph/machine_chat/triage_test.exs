defmodule Console.MachineChat.TriageTest do
  @moduledoc "Slice E: unrouted-thread intent → specialist archetype → roster worker handle."
  use ExUnit.Case, async: true

  alias Console.MachineChat.Triage

  @roster [
    %{"archetype" => "surveyor", "name" => "tertius"},
    %{"archetype" => "builder", "name" => "hronir"},
    %{"archetype" => "reviewer", "name" => "vera"},
    %{"archetype" => "planner", "name" => "borges"},
    %{"archetype" => "researcher", "name" => "ireneo"}
  ]

  describe "archetype/1 — explicit intent only" do
    test "review verbs → reviewer" do
      assert Triage.archetype("review the staffing diff") == :reviewer
      assert Triage.archetype("please audit the sandbox policy") == :reviewer
    end

    test "plan verbs → planner" do
      assert Triage.archetype("plan the per-thread agents work") == :planner
      assert Triage.archetype("break this down into tickets") == :planner
    end

    test "research verbs and question-shaped text → researcher" do
      assert Triage.archetype("research warm-pool eviction strategies") == :researcher
      assert Triage.archetype("investigate the DECCKM arrow bug") == :researcher
      assert Triage.archetype("why does the cache miss on rebind?") == :researcher
    end

    test "a review that contains a question stays a review — first rule wins" do
      assert Triage.archetype("review this diff — why does it leak?") == :reviewer
    end

    test "build asks and 'can you …?' questions don't classify — nil, the default decides" do
      assert Triage.archetype("add a teardown pass for closed leaves") == nil
      assert Triage.archetype("can you fix the window naming?") == nil
      assert Triage.archetype(nil) == nil
    end
  end

  describe "lead/2 — archetype resolved against the roster" do
    test "staffs the matching worker's handle" do
      assert Triage.lead("review the diff", @roster) == "vera-machine"
      assert Triage.lead("plan the migration", @roster) == "borges-machine"
      assert Triage.lead("what broke the build last night?", @roster) == "ireneo-machine"
    end

    test "no matching archetype in the roster → nil (caller's default decides)" do
      assert Triage.lead("review the diff", [%{"archetype" => "builder", "name" => "hronir"}]) == nil
    end

    test "no intent → nil even with a full roster" do
      assert Triage.lead("wire the teardown pass", @roster) == nil
    end
  end
end
